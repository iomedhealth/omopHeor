#' Fit Propensity Score Model (Stage 3: Causal Adjustment)
#'
#' @description
#' `fit_ps()` estimates the probability (propensity score) of a patient being
#' assigned to the target cohort versus the comparator cohort, based on their baseline
#' covariates (e.g., age, sex).
#'
#' Because observational data lacks randomization, direct comparison between treatments
#' is often biased by confounding variables. Propensity scores are used in HEOR to
#' emulate a randomized controlled trial by matching or weighting patients who have
#' similar baseline characteristics. This function currently uses regularized logistic
#' regression via the `Cyclops` package.
#'
#' @param hcru_obj An `omopheor_hcru` (`hermes_hcru`) object containing the cohort data.
#' @param ... Additional arguments passed to the underlying model fitting functions.
#'
#' @return An `omopheor_ps` (`hermes_ps`) object containing the propensity score model and covariate data.
#'
#' @export
#' @importFrom stats predict
fit_ps <- function(hcru_obj, ...) {
  # ==============================================================================
  # Propensity Score Model Fitting (Stage 3: Causal Adjustment)
  # ==============================================================================
  #
  #  Covariates & Target/Comparator Union:
  #    Target Cohort (T=1)     Comparator Cohort (T=0)
  #            |                         |
  #            v                         v
  #      PatientProfiles (Age, Sex, Baseline Covariates)
  #            |
  #            v
  #     Cyclops Regularized Logistic Regression:
  #       P(Treatment = 1 | Covariates) -> propensity_score
  # ==============================================================================

  cm_data <- hcru_obj$cm_data
  model_fit <- NULL

  if (is.null(cm_data) && !is.null(hcru_obj$cdm) && !is.null(hcru_obj$target_cohort) && !is.null(hcru_obj$comparator_cohort)) {
    # Step 1: Extract baseline demographics for Target cohort
    target <- hcru_obj$cdm[[hcru_obj$target_cohort]] |>
      dplyr::select("subject_id", "cohort_start_date") |>
      PatientProfiles::addAge() |>
      PatientProfiles::addSex() |>
      dplyr::mutate(treatment = 1) |>
      dplyr::collect()

    # Step 2: Extract baseline demographics for Comparator cohort
    comp <- hcru_obj$cdm[[hcru_obj$comparator_cohort]] |>
      dplyr::select("subject_id", "cohort_start_date") |>
      PatientProfiles::addAge() |>
      PatientProfiles::addSex() |>
      dplyr::mutate(treatment = 0) |>
      dplyr::collect()

    # Step 3: Union populations and encode categorical covariates
    cm_data <- dplyr::bind_rows(target, comp) |>
      dplyr::mutate(sex_num = ifelse(.data$sex == "Female", 1, 0))

    # Step 4: Attach first outcome occurrence date if outcome cohort exists
    if (!is.null(hcru_obj$outcome_cohort) && hcru_obj$outcome_cohort %in% names(hcru_obj$cdm)) {
      outcomes <- hcru_obj$cdm[[hcru_obj$outcome_cohort]] |>
        dplyr::select(subject_id = "subject_id", outcome_date = "cohort_start_date") |>
        dplyr::collect() |>
        dplyr::group_by(.data$subject_id) |>
        dplyr::slice_min(.data$outcome_date, with_ties = FALSE) |>
        dplyr::ungroup()

      cm_data <- cm_data |>
        dplyr::left_join(outcomes, by = "subject_id")
    }

    # Step 5: Fit regularized logistic regression via Cyclops and predict propensity scores
    if (nrow(cm_data) > 0) {
      cyclops_data <- Cyclops::createCyclopsData(
        treatment ~ age + sex_num,
        modelType = "lr",
        data = cm_data
      )

      model_fit <- Cyclops::fitCyclopsModel(cyclops_data)
      cm_data$propensity_score <- predict(model_fit)
    }
  } else if (!is.null(cm_data) && inherits(cm_data, "CohortMethodData")) {
    model_fit <- CohortMethod::createPs(
      cohortMethodData = cm_data,
      prior = Cyclops::createPrior("laplace", useCrossValidation = TRUE),
      control = Cyclops::createControl(cvType = "auto", fold = 10, cvRepetitions = 1)
    )
  }

  # Step 6: Construct and return hermes_ps S3 object
  new_omopheor_ps(
    list(
      cm_data = cm_data,
      model = model_fit,
      hcru_obj = hcru_obj
    )
  )
}

#' Adjust Propensity Scores (Stage 3: Causal Adjustment)
#'
#' @description
#' `adjust_ps()` applies a matching algorithm based on the propensity scores calculated
#' by `fit_ps()`.
#'
#' By default, it performs greedy nearest-neighbor caliper matching. This pairs patients
#' in the target cohort with similar patients in the comparator cohort, discarding
#' unmatched patients. The resulting matched population is less biased and suitable
#' for generating the transition probabilities and costs used in the economic simulation.
#'
#' @param ps_obj An `omopheor_ps` (`hermes_ps`) object returned by `fit_ps()`.
#' @param caliper A numeric value specifying the maximum allowed distance between matched
#' propensity scores. Default is 0.2.
#' @param ... Additional arguments passed to the matching function.
#'
#' @return An `omopheor_ps` (`hermes_ps`) object updated with a `matched_pop` attribute containing the matched cohort.
#'
#' @export
adjust_ps <- function(ps_obj, caliper = 0.2, ...) {
  # ==============================================================================
  # Greedy Nearest-Neighbor Caliper Matching Algorithm
  # ==============================================================================
  #
  #  Target Patients (T=1):      [ P1: PS=0.42 ]    [ P2: PS=0.78 ]
  #                                     |                  |
  #  Caliper Distance (|PS_T - PS_C| <= 0.20):             |
  #                                     |                  |
  #  Comparator Pool (T=0):      [ C1: PS=0.45 ]    [ C2: PS=0.99 (Discarded) ]
  #                                     |
  #  Matched Cohort:             (P1 <---> C1 matched pair)
  # ==============================================================================

  matched <- data.frame()
  if (inherits(ps_obj$model, "cyclopsFit")) {
    # Step 1: Identify target and comparator pools
    t_idx <- which(ps_obj$cm_data$treatment == 1)
    c_idx <- which(ps_obj$cm_data$treatment == 0)

    if (length(t_idx) > 0 && length(c_idx) > 0) {
      t_ps <- ps_obj$cm_data$propensity_score[t_idx]
      c_ps <- ps_obj$cm_data$propensity_score[c_idx]

      matched_c_idx <- rep(NA, length(t_idx))
      available_c <- rep(TRUE, length(c_idx))

      # Step 2: Perform 1:1 nearest-neighbor matching without replacement within caliper
      for (i in seq_along(t_idx)) {
        ps_t <- t_ps[i]
        diffs <- abs(c_ps - ps_t)
        diffs[!available_c] <- Inf
        min_idx <- which.min(diffs)
        if (length(min_idx) > 0 && diffs[min_idx] <= caliper) {
          matched_c_idx[i] <- min_idx
          available_c[min_idx] <- FALSE
        }
      }

      # Step 3: Extract matched subset
      valid <- !is.na(matched_c_idx)
      t_matched <- t_idx[valid]
      c_matched <- c_idx[matched_c_idx[valid]]

      cols_to_keep <- c("subject_id", "treatment", "propensity_score", "cohort_start_date")
      if ("outcome_date" %in% colnames(ps_obj$cm_data)) {
        cols_to_keep <- c(cols_to_keep, "outcome_date")
      }

      matched <- ps_obj$cm_data[c(t_matched, c_matched), cols_to_keep]
    }
  } else if (!is.null(ps_obj$model)) {
    matched <- CohortMethod::matchOnPs(ps_obj$model, caliper = caliper, caliperScale = "standardized logit")
  }

  ps_obj$matched_pop <- matched
  new_omopheor_ps(ps_obj)
}

#' Assess Covariate Balance (Stage 3: Causal Adjustment)
#'
#' @description
#' `assess_balance()` calculates the Standardized Mean Differences (SMD) for covariates
#' before and after propensity score matching.
#'
#' In HEOR, this is a critical diagnostic step. A well-specified propensity score model
#' should balance the baseline covariates between the treatment and comparator arms,
#' resulting in SMDs close to zero (typically < 0.1).
#'
#' @param ps_obj An `omopheor_ps` (`hermes_ps`) object returned by `adjust_ps()`.
#' @param ... Additional arguments.
#'
#' @return An `omopheor_ps` (`hermes_ps`) object updated with an `smd_summary` attribute.
#'
#' @export
assess_balance <- function(ps_obj, ...) {
  # ponytail: minimal balance wrapper
  smd <- data.frame()
  if (is.data.frame(ps_obj$matched_pop) && nrow(ps_obj$matched_pop) > 0 && !is.null(ps_obj$hcru_obj$cm_data)) {
    if (inherits(ps_obj$hcru_obj$cm_data, "CohortMethodData")) {
      smd <- CohortMethod::computeCovariateBalance(ps_obj$matched_pop, ps_obj$hcru_obj$cm_data)
    }
  }

  ps_obj$smd_summary <- smd
  new_omopheor_ps(ps_obj)
}
