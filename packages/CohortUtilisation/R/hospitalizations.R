#' Generate Hospitalization and Readmission Cohorts (Stage 1 & 2)
#'
#' @description
#' Extracts inpatient visits from `visit_occurrence`, collapses contiguous or
#' overlapping stays into discrete hospitalization episodes, and derives
#' readmission cohorts within a specified washout window.
#'
#' @param cdm A `cdm_reference` object.
#' @param name String specifying the cohort table name in the write schema.
#' @param visit_concept_ids Integer vector of OMOP visit concept IDs. Default: `c(9201L, 262L, 32037L, 581379L)`.
#' @param readmission_window Maximum days between previous discharge and next admission. Default: 30.
#' @param collapse_gap Maximum gap in days between contiguous stays to collapse into a single episode. Default: `1L`.
#' @param gap_days Optional alias for `collapse_gap`.
#'
#' @note For in-database Healthcare Resource Utilization (HCRU) characterization on existing study cohorts, prefer \code{\link{addInpatients}}.
#'
#' @return An `omopgenerics` cohort table with cohort definitions:
#' - `1`: `hospitalization` (collapsed inpatient episodes)
#' - `2`: `readmission` (episodes occurring within `readmission_window` days of prior discharge)
#'
#' @export
compute_hospitalization_cohorts <- function(
  cdm,
  name,
  visit_concept_ids = c(9201L, 262L, 32037L, 581379L),
  readmission_window = 30L,
  collapse_gap = 1L,
  gap_days = NULL
) {
  # ponytail: interval collapsing via cumulative max end date and lagged boundary detection
  omopgenerics::assertCharacter(name, length = 1)
  omopgenerics::assertClass(cdm, "cdm_reference")
  visit_concept_ids <- as.integer(visit_concept_ids)
  readmission_window <- as.integer(readmission_window)
  gap_val <- if (!is.null(gap_days)) gap_days else collapse_gap
  collapse_gap <- validateGapDays(gapDays = gap_val)

  prefix <- omopgenerics::tmpPrefix()

  # 1. Extract & clean visit spans
  raw_visits <- cdm[["visit_occurrence"]] |>
    dplyr::filter(.data$visit_concept_id %in% .env$visit_concept_ids) |>
    dplyr::select(
      subject_id = "person_id",
      cohort_start_date = "visit_start_date",
      cohort_end_date = "visit_end_date"
    ) |>
    dplyr::mutate(
      cohort_end_date = dplyr::case_when(
        is.na(.data$cohort_end_date) ~ .data$cohort_start_date,
        .data$cohort_end_date < .data$cohort_start_date ~ .data$cohort_start_date,
        .default = .data$cohort_end_date
      )
    ) |>
    dplyr::compute(name = paste0(prefix, "raw_vis"), temporary = FALSE, overwrite = TRUE)

  # 2. Cumulative max tracking for overlap collapse
  cum_spans <- raw_visits |>
    dplyr::group_by(.data$subject_id) |>
    dbplyr::window_order(.data$cohort_start_date, .data$cohort_end_date) |>
    dplyr::mutate(
      max_end_so_far = cummax(.data$cohort_end_date)
    ) |>
    dplyr::compute(name = paste0(prefix, "cum_spans"), temporary = FALSE, overwrite = TRUE)

  # 3. Mark episode boundaries & assign episode IDs
  episodes <- cum_spans |>
    dplyr::group_by(.data$subject_id) |>
    dbplyr::window_order(.data$cohort_start_date, .data$cohort_end_date) |>
    dplyr::mutate(
      prev_max_end = dplyr::lag(.data$max_end_so_far),
      is_new_episode = dplyr::if_else(
        dplyr::row_number() == 1L | .data$cohort_start_date > .data$prev_max_end + .env$collapse_gap,
        1L,
        0L
      )
    ) |>
    dplyr::mutate(episode_id = cumsum(.data$is_new_episode)) |>
    dplyr::group_by(.data$subject_id, .data$episode_id) |>
    dplyr::summarise(
      cohort_start_date = min(.data$cohort_start_date, na.rm = TRUE),
      cohort_end_date = max(.data$cohort_end_date, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::select("subject_id", "cohort_start_date", "cohort_end_date") |>
    dplyr::compute(name = paste0(prefix, "collapsed"), temporary = FALSE, overwrite = TRUE)

  # 4. Identify readmissions
  readm <- episodes |>
    dplyr::group_by(.data$subject_id) |>
    dbplyr::window_order(.data$cohort_start_date) |>
    dplyr::mutate(prev_discharge = dplyr::lag(.data$cohort_end_date)) |>
    dplyr::ungroup() |>
    dplyr::filter(
      !is.na(.data$prev_discharge) &
        .data$cohort_start_date <= .data$prev_discharge + .env$readmission_window &
        .data$cohort_start_date > .data$prev_discharge
    ) |>
    dplyr::mutate(cohort_definition_id = 2L) |>
    dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")

  hosp <- episodes |>
    dplyr::mutate(cohort_definition_id = 1L) |>
    dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")

  cohort_table <- hosp |>
    dplyr::union_all(readm) |>
    dplyr::compute(name = name, temporary = FALSE, overwrite = TRUE)

  # Cleanup intermediates
  omopgenerics::dropSourceTable(cdm = cdm, name = dplyr::starts_with(prefix))

  # Build cohort metadata
  cohort_set <- dplyr::tibble(
    cohort_definition_id = c(1L, 2L),
    cohort_name = c("hospitalization", "readmission")
  )

  omopgenerics::newCohortTable(
    table = cohort_table,
    cohortSetRef = cohort_set,
    .softValidation = TRUE
  )
}

#' @rdname compute_hospitalization_cohorts
#' @param visitConceptIds Integer vector of OMOP visit concept IDs. Default: `c(9201L, 262L, 581379L)`.
#' @param icuConceptIds Integer vector of OMOP ICU visit concept IDs. Default: `32037L`.
#' @param readmissionWindow Maximum days between previous discharge and next admission. Default: 30.
#' @param gapDays Maximum gap in days between contiguous stays to collapse into a single episode. Default: `1L`.
#' @param collapseGap Optional alias for `gapDays`. Default: `NULL`.
#' @param readmission_window Backward compatible snake_case parameter.
#' @export
computeHospitalizationCohorts <- function(
  cdm,
  name,
  visitConceptIds = c(9201L, 262L, 581379L),
  icuConceptIds = 32037L,
  readmissionWindow = 30L,
  gapDays = 1L,
  collapseGap = NULL,
  readmission_window = NULL
) {
  win <- if (!is.null(readmission_window)) readmission_window else readmissionWindow
  gap <- if (!is.null(collapseGap)) collapseGap else gapDays
  all_concepts <- unique(c(visitConceptIds, icuConceptIds))
  compute_hospitalization_cohorts(
    cdm = cdm,
    name = name,
    visit_concept_ids = all_concepts,
    readmission_window = win,
    collapse_gap = gap
  )
}
