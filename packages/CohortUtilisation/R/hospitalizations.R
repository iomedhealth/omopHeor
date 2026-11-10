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
#' @param study_cohort_table Optional cohort table name (or `cohort_table`) in `cdm` used to pre-filter visits to each subject's follow-up window (`[index_date, censor_date]`) before collapsing episodes. Default: `NULL`.
#' @param index_date Date column in `study_cohort_table` marking start of follow-up. Default: `"cohort_start_date"`.
#' @param censor_date Optional date column in `study_cohort_table` marking end of follow-up. Default: `"cohort_end_date"`.
#' @param exclude_icu_specialty Logical; if `TRUE`, excludes visits whose provider specialty is in `icu_specialty_concept_ids` (matching `addHospitalizations()` general inpatient definition). Default: `FALSE`.
#' @param icu_specialty_concept_ids Integer vector of OMOP provider specialty concept IDs for ICU. Default: `c(38004500L)`.
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
  gap_days = NULL,
  study_cohort_table = NULL,
  index_date = "cohort_start_date",
  censor_date = "cohort_end_date",
  exclude_icu_specialty = FALSE,
  icu_specialty_concept_ids = c(38004500L)
) {
  # ==============================================================================
  # Inpatient Episode Collapsing & Readmission Architecture
  # ==============================================================================
  #
  #  Raw Visits:      [ Visit 1 ]   [ Visit 2 ]          [ Visit 3 ]
  #                      |               |                    |
  #  Overlap / Gap:      +-- gap <= 1d --+                    |
  #                      v                                    v
  #  Collapsed Ep:    [     Episode 1 (LOS)     ]        [ Episode 2 ]
  #                                             \______  ____/
  #                                                    \/
  #  Readmission Check:                     gap <= readmission_window (e.g. 30d)?
  #                                         --> YES => Marked as Readmission (id=2)
  #
  #  In-Database Interval Collapsing (dbplyr window functions):
  #    1. Group by patient (subject_id) and order by start_date, end_date.
  #    2. Track running maximum end date: max_end_so_far = cummax(cohort_end_date).
  #    3. Detect episode boundary: if row_number == 1 or start_date > lag(max_end) + gap,
  #       flag is_new_episode = 1, else 0.
  #    4. Group by subject_id & cumsum(is_new_episode) to aggregate [min(start), max(end)].
  # ==============================================================================

  # Validate inputs and harmonize parameters
  omopgenerics::assertCharacter(name, length = 1)
  omopgenerics::assertClass(cdm, "cdm_reference")
  visit_concept_ids <- as.integer(visit_concept_ids)
  readmission_window <- as.integer(readmission_window)
  gap_val <- if (!is.null(gap_days)) gap_days else collapse_gap
  collapse_gap <- validateGapDays(gapDays = gap_val)
  icu_specialty_concept_ids <- if (!is.null(icu_specialty_concept_ids)) as.integer(icu_specialty_concept_ids) else integer()

  prefix <- omopgenerics::tmpPrefix()

  # Step 1: Extract inpatient visits and sanitize invalid/missing end dates
  vis_tbl <- cdm[["visit_occurrence"]] |>
    dplyr::filter(.data$visit_concept_id %in% .env$visit_concept_ids)

  if (isTRUE(exclude_icu_specialty) && length(icu_specialty_concept_ids) > 0 && "provider" %in% names(cdm)) {
    vis_tbl <- vis_tbl |>
      dplyr::left_join(
        cdm[["provider"]] |> dplyr::select("provider_id", "specialty_concept_id"),
        by = "provider_id"
      ) |>
      dplyr::filter(
        is.na(.data$specialty_concept_id) | !(.data$specialty_concept_id %in% .env$icu_specialty_concept_ids)
      )
  }

  raw_visits <- vis_tbl |>
    dplyr::select(
      subject_id = "person_id",
      cohort_start_date = "visit_start_date",
      cohort_end_date = "visit_end_date"
    ) |>
    dplyr::mutate(
      # If end date is missing or precedes start date, default to start date
      cohort_end_date = dplyr::case_when(
        is.na(.data$cohort_end_date) ~ .data$cohort_start_date,
        .data$cohort_end_date < .data$cohort_start_date ~ .data$cohort_start_date,
        .default = .data$cohort_end_date
      )
    )

  if (!is.null(study_cohort_table)) {
    study_tbl <- if (is.character(study_cohort_table)) cdm[[study_cohort_table]] else study_cohort_table
    study_cols <- colnames(study_tbl)
    s_person <- if ("subject_id" %in% study_cols) "subject_id" else "person_id"
    if (!is.null(censor_date) && censor_date %in% study_cols) {
      study_bounds <- study_tbl |>
        dplyr::select(
          subject_id = dplyr::all_of(s_person),
          win_start = dplyr::all_of(index_date),
          win_end = dplyr::all_of(censor_date)
        ) |>
        dplyr::distinct()
      raw_visits <- raw_visits |>
        dplyr::inner_join(study_bounds, by = "subject_id") |>
        dplyr::filter(
          .data$cohort_start_date >= .data$win_start &
            (is.na(.data$win_end) | .data$cohort_start_date <= .data$win_end)
        ) |>
        dplyr::select("subject_id", "cohort_start_date", "cohort_end_date") |>
        dplyr::distinct()
    } else {
      study_bounds <- study_tbl |>
        dplyr::select(
          subject_id = dplyr::all_of(s_person),
          win_start = dplyr::all_of(index_date)
        ) |>
        dplyr::distinct()
      raw_visits <- raw_visits |>
        dplyr::inner_join(study_bounds, by = "subject_id") |>
        dplyr::filter(.data$cohort_start_date >= .data$win_start) |>
        dplyr::select("subject_id", "cohort_start_date", "cohort_end_date") |>
        dplyr::distinct()
    }
  }

  raw_visits <- raw_visits |>
    dplyr::compute(name = paste0(prefix, "raw_vis"), temporary = FALSE, overwrite = TRUE)

  # Step 2: Track cumulative maximum end date within patient history
  cum_spans <- raw_visits |>
    dplyr::group_by(.data$subject_id) |>
    dbplyr::window_order(.data$cohort_start_date, .data$cohort_end_date) |>
    dplyr::mutate(
      max_end_so_far = cummax(.data$cohort_end_date)
    ) |>
    dplyr::compute(name = paste0(prefix, "cum_spans"), temporary = FALSE, overwrite = TRUE)

  # Step 3: Identify discrete episode boundaries using gap threshold & collapse overlapping spans
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

  # Step 4: Identify readmission episodes occurring within the washout window after previous discharge
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

  # Step 5: Format primary hospitalization episodes (cohort_definition_id = 1)
  hosp <- episodes |>
    dplyr::mutate(cohort_definition_id = 1L) |>
    dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")

  # Step 6: Combine hospitalization and readmission cohorts into target table
  cohort_table <- hosp |>
    dplyr::union_all(readm) |>
    dplyr::compute(name = name, temporary = FALSE, overwrite = TRUE)

  # Cleanup temporary database tables
  omopgenerics::dropSourceTable(cdm = cdm, name = dplyr::starts_with(prefix))

  # Build cohort metadata and return validated cohort table
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
#' @param studyCohortTable Optional cohort table name (or `cohort_table`) in `cdm` used to pre-filter visits to each subject's follow-up window before collapsing episodes. Default: `NULL`.
#' @param indexDate Date column in `studyCohortTable` marking start of follow-up. Default: `"cohort_start_date"`.
#' @param censorDate Optional date column in `studyCohortTable` marking end of follow-up. Default: `"cohort_end_date"`.
#' @param excludeIcuSpecialty Logical; if `TRUE`, excludes visits whose provider specialty is in `icuSpecialtyConceptIds`. Default: `FALSE`.
#' @param icuSpecialtyConceptIds Integer vector of OMOP provider specialty concept IDs for ICU. Default: `c(38004500L)`.
#' @export
computeHospitalizationCohorts <- function(
  cdm,
  name,
  visitConceptIds = c(9201L, 262L, 581379L),
  icuConceptIds = 32037L,
  readmissionWindow = 30L,
  gapDays = 1L,
  collapseGap = NULL,
  readmission_window = NULL,
  studyCohortTable = NULL,
  indexDate = "cohort_start_date",
  censorDate = "cohort_end_date",
  excludeIcuSpecialty = FALSE,
  icuSpecialtyConceptIds = c(38004500L)
) {
  win <- if (!is.null(readmission_window)) readmission_window else readmissionWindow
  gap <- if (!is.null(collapseGap)) collapseGap else gapDays
  all_concepts <- unique(c(visitConceptIds, icuConceptIds))
  compute_hospitalization_cohorts(
    cdm = cdm,
    name = name,
    visit_concept_ids = all_concepts,
    readmission_window = win,
    collapse_gap = gap,
    study_cohort_table = studyCohortTable,
    index_date = indexDate,
    censor_date = censorDate,
    exclude_icu_specialty = excludeIcuSpecialty,
    icu_specialty_concept_ids = icuSpecialtyConceptIds
  )
}
