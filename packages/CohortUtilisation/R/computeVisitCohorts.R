#' Generate Multi-Setting and Specialty Visit Cohorts
#'
#' @description
#' Extracts healthcare visits from `visit_occurrence` and `provider` tables across
#' emergency, outpatient (general practitioner, specialist, and custom specialty strata),
#' inpatient, and ICU settings, and materializes them as an `omopgenerics` cohort table.
#'
#' Unlike \code{\link{addVisits}}, which aggregates visit counts directly onto a study cohort,
#' `computeVisitCohorts()` returns a cohort table where each visit episode is a cohort record.
#' This allows downstream cohort-to-cohort operations such as \code{CohortConstructor::requireCohortIntersect()}
#' to identify visits temporally associated with another clinical event (e.g., Herpes Zoster
#' within a 7-day window).
#'
#' @param cdm A `cdm_reference` object.
#' @param name String specifying the cohort table name in the write schema.
#' @param settings Character vector of care settings to include. Allowed values:
#'   `"emergency"`, `"outpatient"`, `"inpatient"`, `"icu"`. Default: `c("emergency", "outpatient")`.
#' @param specialties Optional named list of integer vectors of OMOP provider `specialty_concept_id`s
#'   for granular outpatient specialty cohorts (e.g., `list(oncology = 38004507L, dermatology = 38004452L)`).
#'   Default: `NULL`.
#' @param stratifySpecialty Logical; whether to partition outpatient visits into `"gp_visit"` and
#'   `"specialist_visit"` cohorts. Default: `TRUE`.
#' @param gpSpecialtyConceptIds OMOP provider specialty concept IDs for General Practice. Default: `c(38004446L)`.
#' @param emergencyVisitConceptIds OMOP visit concept IDs for emergency care. Default: `c(9203L, 262L, 581478L)`.
#' @param emergencySpecialtyConceptIds OMOP provider specialty concept IDs for emergency medicine. Default: `c(38004510L)`.
#' @param outpatientVisitConceptIds OMOP visit concept IDs for outpatient care. Default: `c(9202L, 581477L)`.
#' @param inpatientVisitConceptIds OMOP visit concept IDs for general inpatient stays. Default: `c(9201L, 8717L, 581379L)`.
#' @param icuConceptIds OMOP visit concept IDs for ICU stays. Default: `32037L`.
#' @param icuSpecialtyConceptIds OMOP provider specialty concept IDs for ICU stays. Default: `c(38004500L)`.
#' @param gapDays Integer scalar >= 0. Maximum gap in days between contiguous inpatient/ICU stays
#'   to collapse into a single episode. Default: `1L`.
#' @param collapseGap Optional alias for `gapDays`. Default: `NULL`.
#' @param countBy Character scalar specifying granularity: `"days"` to collapse same-day/overlapping visits,
#'   or `"records"` to keep distinct start-end spans. Default: `"days"`.
#' @param collapseOverlapping Logical; whether to collapse same-day and overlapping visits. Default: `TRUE`.
#' @param studyCohortTable Optional cohort table name (or `cohort_table`) in `cdm` to pre-filter
#'   visits to each subject's follow-up window (`[indexDate, censorDate]`) prior to episode collapsing.
#'   Default: `NULL`.
#' @param indexDate Date column in `studyCohortTable` marking start of follow-up. Default: `"cohort_start_date"`.
#' @param censorDate Optional date column in `studyCohortTable` marking end of follow-up. Default: `"cohort_end_date"`.
#'
#' @return An `omopgenerics::cohort_table` object with one `cohort_definition_id` per requested
#'   visit setting and specialty.
#' @export
computeVisitCohorts <- function(
  cdm,
  name,
  settings = c("emergency", "outpatient"),
  specialties = NULL,
  stratifySpecialty = TRUE,
  gpSpecialtyConceptIds = c(38004446L),
  emergencyVisitConceptIds = c(9203L, 262L, 581478L),
  emergencySpecialtyConceptIds = c(38004510L),
  outpatientVisitConceptIds = c(9202L, 581477L),
  inpatientVisitConceptIds = c(9201L, 8717L, 581379L),
  icuConceptIds = 32037L,
  icuSpecialtyConceptIds = c(38004500L),
  gapDays = 1L,
  collapseGap = NULL,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  studyCohortTable = NULL,
  indexDate = "cohort_start_date",
  censorDate = "cohort_end_date"
) {
  omopgenerics::assertCharacter(name, length = 1)
  omopgenerics::assertClass(cdm, "cdm_reference")

  valid_settings <- c("emergency", "outpatient", "inpatient", "icu")
  if (!is.character(settings) || length(settings) == 0 || !all(settings %in% valid_settings)) {
    cli::cli_abort("Argument 'settings' must be a non-empty subset of c('emergency', 'outpatient', 'inpatient', 'icu').")
  }

  specialties <- validateSpecialties(specialties)
  gapDays <- validateGapDays(gapDays = gapDays, collapseGap = collapseGap)
  countBy <- validateCountBy(countBy = countBy, collapseOverlapping = collapseOverlapping)

  gpSpecialtyConceptIds <- if (!is.null(gpSpecialtyConceptIds)) as.integer(gpSpecialtyConceptIds) else integer()
  emergencyVisitConceptIds <- if (!is.null(emergencyVisitConceptIds)) as.integer(emergencyVisitConceptIds) else integer()
  emergencySpecialtyConceptIds <- if (!is.null(emergencySpecialtyConceptIds)) as.integer(emergencySpecialtyConceptIds) else integer()
  outpatientVisitConceptIds <- if (!is.null(outpatientVisitConceptIds)) as.integer(outpatientVisitConceptIds) else integer()
  inpatientVisitConceptIds <- if (!is.null(inpatientVisitConceptIds)) as.integer(inpatientVisitConceptIds) else integer()
  icuConceptIds <- if (!is.null(icuConceptIds)) as.integer(icuConceptIds) else integer()
  icuSpecialtyConceptIds <- if (!is.null(icuSpecialtyConceptIds)) as.integer(icuSpecialtyConceptIds) else integer()

  # Step 1: Build deterministic cohort_set catalog
  cohort_names <- character()
  if ("inpatient" %in% settings) {
    cohort_names <- c(cohort_names, "inpatient_visit")
  }
  if ("icu" %in% settings) {
    cohort_names <- c(cohort_names, "icu_visit")
  }
  if ("emergency" %in% settings) {
    cohort_names <- c(cohort_names, "emergency_visit")
  }
  if ("outpatient" %in% settings) {
    if (isTRUE(stratifySpecialty)) {
      cohort_names <- c(cohort_names, "gp_visit", "specialist_visit")
    } else {
      cohort_names <- c(cohort_names, "outpatient_visit")
    }
    if (!is.null(specialties) && length(specialties) > 0) {
      spec_cohort_names <- paste0(tolower(names(specialties)), "_visit")
      cohort_names <- c(cohort_names, spec_cohort_names)
    }
  }

  cohort_set <- dplyr::tibble(
    cohort_definition_id = seq_along(cohort_names),
    cohort_name = cohort_names
  )
  id_map <- stats::setNames(cohort_set$cohort_definition_id, cohort_set$cohort_name)

  # Step 2: Extract visits and provider specialty mapping
  provider_df <- if ("provider" %in% names(cdm)) {
    cdm$provider |>
      dplyr::select("provider_id", "specialty_concept_id") |>
      dplyr::collect()
  } else {
    tibble::tibble(provider_id = integer(), specialty_concept_id = integer())
  }

  vis_tbl <- cdm$visit_occurrence |>
    dplyr::select(
      "visit_occurrence_id",
      subject_id = "person_id",
      "visit_concept_id",
      "visit_start_date",
      "visit_end_date",
      "provider_id"
    )

  if (!is.null(studyCohortTable)) {
    study_tbl <- if (is.character(studyCohortTable)) cdm[[studyCohortTable]] else studyCohortTable
    study_cols <- colnames(study_tbl)
    s_person <- if ("subject_id" %in% study_cols) "subject_id" else "person_id"
    if (!is.null(censorDate) && censorDate %in% study_cols) {
      study_bounds <- study_tbl |>
        dplyr::select(
          subject_id = dplyr::all_of(s_person),
          win_start = dplyr::all_of(indexDate),
          win_end = dplyr::all_of(censorDate)
        ) |>
        dplyr::distinct()
      vis_tbl <- vis_tbl |>
        dplyr::inner_join(study_bounds, by = "subject_id") |>
        dplyr::filter(
          .data$visit_start_date >= .data$win_start &
            (is.na(.data$win_end) | .data$visit_start_date <= .data$win_end)
        ) |>
        dplyr::select(
          "visit_occurrence_id", "subject_id", "visit_concept_id",
          "visit_start_date", "visit_end_date", "provider_id"
        ) |>
        dplyr::distinct()
    } else {
      study_bounds <- study_tbl |>
        dplyr::select(
          subject_id = dplyr::all_of(s_person),
          win_start = dplyr::all_of(indexDate)
        ) |>
        dplyr::distinct()
      vis_tbl <- vis_tbl |>
        dplyr::inner_join(study_bounds, by = "subject_id") |>
        dplyr::filter(.data$visit_start_date >= .data$win_start) |>
        dplyr::select(
          "visit_occurrence_id", "subject_id", "visit_concept_id",
          "visit_start_date", "visit_end_date", "provider_id"
        ) |>
        dplyr::distinct()
    }
  }

  visit_df <- vis_tbl |>
    dplyr::collect() |>
    dplyr::left_join(provider_df, by = "provider_id") |>
    dplyr::mutate(
      visit_end_date = dplyr::case_when(
        is.na(.data$visit_end_date) ~ .data$visit_start_date,
        .data$visit_end_date < .data$visit_start_date ~ .data$visit_start_date,
        .default = .data$visit_end_date
      )
    )

  cohort_rows <- list()

  # Step 3: Inpatient & ICU episodes (if requested)
  if (any(c("inpatient", "icu") %in% settings) && nrow(visit_df) > 0) {
    inp_icu_concepts <- unique(c(inpatientVisitConceptIds, icuConceptIds))
    inp_df <- visit_df |>
      dplyr::filter(.data$visit_concept_id %in% inp_icu_concepts) |>
      dplyr::mutate(
        is_icu = (.data$visit_concept_id %in% icuConceptIds) |
          (!is.na(.data$specialty_concept_id) & .data$specialty_concept_id %in% icuSpecialtyConceptIds)
      )

    if (nrow(inp_df) > 0) {
      if (countBy == "days") {
        ordered_stays <- inp_df |>
          dplyr::arrange(.data$subject_id, .data$visit_start_date, .data$visit_end_date) |>
          dplyr::group_by(.data$subject_id) |>
          dplyr::mutate(
            max_end_num = cummax(as.numeric(.data$visit_end_date)),
            is_new_episode = dplyr::if_else(
              dplyr::row_number() == 1L | as.numeric(.data$visit_start_date) > dplyr::lag(.data$max_end_num) + gapDays,
              1L,
              0L
            ),
            episode_id = cumsum(.data$is_new_episode)
          ) |>
          dplyr::ungroup()

        if ("inpatient" %in% settings) {
          inp_episodes <- ordered_stays |>
            dplyr::group_by(.data$subject_id, .data$episode_id) |>
            dplyr::summarise(
              cohort_start_date = min(.data$visit_start_date, na.rm = TRUE),
              cohort_end_date = max(.data$visit_end_date, na.rm = TRUE),
              has_inp = any(!.data$is_icu),
              .groups = "drop"
            ) |>
            dplyr::filter(.data$has_inp) |>
            dplyr::mutate(cohort_definition_id = as.integer(id_map[["inpatient_visit"]])) |>
            dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")
          cohort_rows <- c(cohort_rows, list(inp_episodes))
        }

        if ("icu" %in% settings) {
          icu_stays <- inp_df |>
            dplyr::filter(.data$is_icu) |>
            dplyr::arrange(.data$subject_id, .data$visit_start_date, .data$visit_end_date) |>
            dplyr::group_by(.data$subject_id) |>
            dplyr::mutate(
              max_end_num = cummax(as.numeric(.data$visit_end_date)),
              is_new_episode = dplyr::if_else(
                dplyr::row_number() == 1L | as.numeric(.data$visit_start_date) > dplyr::lag(.data$max_end_num) + gapDays,
                1L,
                0L
              ),
              episode_id = cumsum(.data$is_new_episode)
            ) |>
            dplyr::group_by(.data$subject_id, .data$episode_id) |>
            dplyr::summarise(
              cohort_start_date = min(.data$visit_start_date, na.rm = TRUE),
              cohort_end_date = max(.data$visit_end_date, na.rm = TRUE),
              .groups = "drop"
            ) |>
            dplyr::mutate(cohort_definition_id = as.integer(id_map[["icu_visit"]])) |>
            dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")
          cohort_rows <- c(cohort_rows, list(icu_stays))
        }
      } else {
        if ("inpatient" %in% settings) {
          inp_recs <- inp_df |>
            dplyr::filter(!.data$is_icu) |>
            dplyr::distinct(.data$subject_id, cohort_start_date = .data$visit_start_date) |>
            dplyr::mutate(
              cohort_end_date = .data$cohort_start_date,
              cohort_definition_id = as.integer(id_map[["inpatient_visit"]])
            ) |>
            dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")
          cohort_rows <- c(cohort_rows, list(inp_recs))
        }
        if ("icu" %in% settings) {
          icu_recs <- inp_df |>
            dplyr::filter(.data$is_icu) |>
            dplyr::distinct(.data$subject_id, cohort_start_date = .data$visit_start_date) |>
            dplyr::mutate(
              cohort_end_date = .data$cohort_start_date,
              cohort_definition_id = as.integer(id_map[["icu_visit"]])
            ) |>
            dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")
          cohort_rows <- c(cohort_rows, list(icu_recs))
        }
      }
    }
  }

  # Step 4: Emergency visits (if requested)
  if ("emergency" %in% settings && nrow(visit_df) > 0) {
    em_df <- visit_df |>
      dplyr::filter(
        (.data$visit_concept_id %in% emergencyVisitConceptIds) |
          (!is.na(.data$specialty_concept_id) & .data$specialty_concept_id %in% emergencySpecialtyConceptIds)
      ) |>
      dplyr::distinct(.data$subject_id, cohort_start_date = .data$visit_start_date) |>
      dplyr::mutate(
        cohort_end_date = .data$cohort_start_date,
        cohort_definition_id = as.integer(id_map[["emergency_visit"]])
      ) |>
      dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")
    cohort_rows <- c(cohort_rows, list(em_df))
  }

  # Step 5: Outpatient visits and specialty strata (if requested)
  if ("outpatient" %in% settings && nrow(visit_df) > 0) {
    out_df <- visit_df |>
      dplyr::filter(.data$visit_concept_id %in% outpatientVisitConceptIds)

    if (nrow(out_df) > 0) {
      if (isTRUE(stratifySpecialty)) {
        gp_df <- out_df |>
          dplyr::filter(is.na(.data$specialty_concept_id) | .data$specialty_concept_id %in% gpSpecialtyConceptIds) |>
          dplyr::distinct(.data$subject_id, cohort_start_date = .data$visit_start_date) |>
          dplyr::mutate(
            cohort_end_date = .data$cohort_start_date,
            cohort_definition_id = as.integer(id_map[["gp_visit"]])
          ) |>
          dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")

        spec_df <- out_df |>
          dplyr::filter(!is.na(.data$specialty_concept_id) & !(.data$specialty_concept_id %in% gpSpecialtyConceptIds)) |>
          dplyr::distinct(.data$subject_id, cohort_start_date = .data$visit_start_date) |>
          dplyr::mutate(
            cohort_end_date = .data$cohort_start_date,
            cohort_definition_id = as.integer(id_map[["specialist_visit"]])
          ) |>
          dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")

        cohort_rows <- c(cohort_rows, list(gp_df, spec_df))
      } else {
        all_out_df <- out_df |>
          dplyr::distinct(.data$subject_id, cohort_start_date = .data$visit_start_date) |>
          dplyr::mutate(
            cohort_end_date = .data$cohort_start_date,
            cohort_definition_id = as.integer(id_map[["outpatient_visit"]])
          ) |>
          dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")
        cohort_rows <- c(cohort_rows, list(all_out_df))
      }

      if (!is.null(specialties) && length(specialties) > 0) {
        for (s_name in names(specialties)) {
          s_ids <- as.integer(specialties[[s_name]])
          c_name <- paste0(tolower(s_name), "_visit")
          s_df <- out_df |>
            dplyr::filter(!is.na(.data$specialty_concept_id) & .data$specialty_concept_id %in% s_ids) |>
            dplyr::distinct(.data$subject_id, cohort_start_date = .data$visit_start_date) |>
            dplyr::mutate(
              cohort_end_date = .data$cohort_start_date,
              cohort_definition_id = as.integer(id_map[[c_name]])
            ) |>
            dplyr::select("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date")
          cohort_rows <- c(cohort_rows, list(s_df))
        }
      }
    }
  }

  # Step 6: Combine all visit cohorts and materialize in CDM write schema
  final_df <- if (length(cohort_rows) > 0) {
    dplyr::bind_rows(cohort_rows) |>
      dplyr::arrange(.data$cohort_definition_id, .data$subject_id, .data$cohort_start_date)
  } else {
    tibble::tibble(
      cohort_definition_id = integer(),
      subject_id = integer(),
      cohort_start_date = as.Date(character()),
      cohort_end_date = as.Date(character())
    )
  }

  cdm <- omopgenerics::insertTable(cdm = cdm, name = name, table = final_df, overwrite = TRUE)

  omopgenerics::newCohortTable(
    table = cdm[[name]],
    cohortSetRef = cohort_set,
    .softValidation = TRUE
  )
}

#' @rdname computeVisitCohorts
#' @export
compute_visit_cohorts <- computeVisitCohorts
