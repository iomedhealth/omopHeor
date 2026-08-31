#' Compile State Trajectories and Costs (Stage 4: Trajectory Compilation)
#'
#' @description
#' `compile_trajectories()` aggregates the longitudinal patient timelines from the
#' matched cohorts into discrete health states and calculates transition probabilities.
#'
#' To run a Markov model for economic simulation, we need to know the probability
#' of a patient moving from one state (e.g., 'Baseline') to another (e.g., 'Outcome').
#' This function calculates those probabilities empirically from the OMOP data. It also
#' aggregates the total costs incurred by patients while residing in each specific
#' health state.
#'
#' @param ps_obj An `omopheor_ps` (`hermes_ps`) object containing the matched population and cost data.
#'
#' @return An `omopheor_trajectories` (`hermes_trajectories`) object containing transition matrices and state-specific cost summaries.
#'
#' @export
compile_trajectories <- function(ps_obj) {
  # ==============================================================================
  # Markov State Trajectory & State-Cost Compilation Architecture
  # ==============================================================================
  #
  #  State Space & Transitions:
  #
  #                     +------------------------+
  #                     |     State_Baseline     | <------+
  #                     | (Pre-outcome HCRU/Cost)|        | (1 - p_outcome)
  #                     +-----------+------------+        |
  #                                 |                     |
  #                      p_outcome  |  (Transition)       |
  #                                 v                     |
  #                     +------------------------+        |
  #                     |     State_Outcome      |--------+
  #                     | (Post-outcome HCRU/Cost| (Absorbing State in Base Model)
  #                     +------------------------+
  #
  #  Workflow:
  #    1. Partition matched cohort into target (treatment = 1) & comparator (0).
  #    2. Compute empirical transition probabilities from baseline to outcome state.
  #    3. Aggregate patient-level total costs by health state.
  #    4. Derive mean and standard error of costs for probabilistic sensitivity analysis.
  # ==============================================================================

  matrices <- list()
  costs_summary <- data.frame()

  if (!is.null(ps_obj$matched_pop) && is.data.frame(ps_obj$matched_pop)) {
    pop <- ps_obj$matched_pop

    # Helper: calculate 2x2 state transition probability matrix from observed events
    calc_trans <- function(df) {
      if (nrow(df) == 0) {
        return(matrix(c(1, 0, 0, 1),
          nrow = 2, byrow = TRUE,
          dimnames = list(
            c("State_Baseline", "State_Outcome"),
            c("State_Baseline", "State_Outcome")
          )
        ))
      }

      n_total <- nrow(df)
      if ("outcome_date" %in% colnames(df)) {
        has_outcome <- !is.na(df$outcome_date)
        days_to_outcome <- as.numeric(difftime(df$outcome_date, df$cohort_start_date, units = "days"))
        n_outcome_30d <- sum(has_outcome & days_to_outcome <= 30, na.rm = TRUE)
      } else {
        n_outcome_30d <- 0
      }

      # Compute 30-day cycle transition rate
      p_outcome <- n_outcome_30d / n_total
      p_baseline <- 1 - p_outcome

      matrix(
        c(
          p_baseline, p_outcome,
          0, 1
        ),
        nrow = 2, byrow = TRUE,
        dimnames = list(
          c("State_Baseline", "State_Outcome"),
          c("State_Baseline", "State_Outcome")
        )
      )
    }

    # Step 1: Stratify by treatment group
    if ("treatment" %in% colnames(pop)) {
      target_pop <- pop[pop$treatment == 1, ]
      comp_pop <- pop[pop$treatment == 0, ]
    } else {
      target_pop <- pop
      comp_pop <- pop[0, ]
    }

    # Step 2: Calculate empirical transition matrices
    matrices$target_transition <- calc_trans(target_pop)
    matrices$comparator_transition <- calc_trans(comp_pop)

    # Step 3: Aggregate health-state specific costs and standard errors
    if (!is.null(ps_obj$hcru_obj$costs)) {
      costs <- ps_obj$hcru_obj$costs
      if (nrow(costs) > 0 && "total_paid" %in% colnames(costs)) {
        if (!"health_state" %in% colnames(costs)) {
          costs$health_state <- "State_Baseline"
        }

        costs_summary <- as.data.frame(
          costs |>
            dplyr::group_by(.data$health_state, .data$subject_id) |>
            dplyr::summarise(
              patient_total = sum(.data$total_paid, na.rm = TRUE),
              .groups = "drop"
            ) |>
            dplyr::group_by(.data$health_state) |>
            dplyr::summarise(
              n_patients = dplyr::n(),
              mean_cost = mean(.data$patient_total, na.rm = TRUE),
              sd_cost = stats::sd(.data$patient_total, na.rm = TRUE),
              .groups = "drop"
            ) |>
            dplyr::mutate(
              se_cost = ifelse(.data$n_patients > 1, .data$sd_cost / sqrt(.data$n_patients), 0)
            ) |>
            dplyr::select("health_state", "n_patients", "mean_cost", "se_cost")
        )
      }
    }
  }

  # Step 4: Construct and return hermes_trajectories S3 object
  new_omopheor_trajectories(
    list(
      ps_obj = ps_obj,
      matrices = matrices,
      costs = costs_summary,
      utilities = data.frame()
    )
  )
}
