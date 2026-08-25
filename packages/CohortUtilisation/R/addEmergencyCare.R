#' Add Emergency Care Utilization Metrics to a Cohort
#'
#' @description
#' Identifies emergency encounters by querying `visit_occurrence` and `provider`
#' tables, capturing encounters with emergency visit concept IDs (e.g. 9203, 262, 581478)
#' as well as visits delivered by emergency medicine specialist providers (e.g. 38004510),
#' with optional granular specialty stratification.
#'
#' @param x A cohort table or cdm_table.
#' @param indexDate Date variable in `x` anchoring the observation window. Default: `"cohort_start_date"`.
#' @param censorDate Optional date variable in `x` to censor observation.
#' @param window A named or unnamed list of 2-element numeric vectors. Default: `list(c(-365, -1), c(0, 365))`.
#' @param emergencyVisitConceptIds OMOP visit concept IDs for emergency care. Default: `c(9203L, 262L, 581478L)`.
#' @param emergencySpecialtyConceptIds OMOP provider specialty concept IDs for emergency medicine. Default: `c(38004510L)`.
#' @param stratifySpecialty Logical; whether to compute specialty breakdown. Default: `FALSE`.
#' @param specialties Optional named list of integer vectors of OMOP specialty concept IDs for granular specialty breakdown. Default: `NULL`.
#' @param countBy Character scalar specifying count granularity: `"days"` to count distinct visit start dates/episodes, or `"records"` to count raw database rows. Default: `"days"`.
#' @param collapseOverlapping Logical; whether to collapse same-day and overlapping visits. If `FALSE`, forces `countBy = "records"`. Default: `TRUE`.
#' @param nameStyle Column naming pattern. Default: `"emergency_visits_{window_name}"`.
#' @param name Name of the new table in the write schema. If NULL, a temporary table is returned.
#'
#' @return The cohort table `x` with added emergency visit metric columns.
#' @aliases addEmergency addEmergencyVisits
#' @export
addEmergencyCare <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  emergencyVisitConceptIds = c(9203L, 262L, 581478L),
  emergencySpecialtyConceptIds = c(38004510L),
  stratifySpecialty = FALSE,
  specialties = NULL,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "emergency_visits_{window_name}",
  name = NULL
) {
  # ponytail: dual-criteria visit_occurrence + provider query for emergency acts with 0-fill
  if (!inherits(x, "cdm_table") && !inherits(x, "cohort_table") && !inherits(x, "tbl_dbi")) {
    cli::cli_abort("Argument 'x' must be a cdm_table or cohort_table.")
  }

  cdm <- omopgenerics::cdmReference(x)
  indexDate <- validateIndexDate(indexDate, x)
  censorDate <- validateCensorDate(censorDate, x)
  clean_window <- validateWindow(window)
  name <- validateName(name)
  specialties <- validateSpecialties(specialties)
  countBy <- validateCountBy(countBy = countBy, collapseOverlapping = collapseOverlapping)

  emergencyVisitConceptIds <- as.integer(emergencyVisitConceptIds)
  emergencySpecialtyConceptIds <- if (!is.null(emergencySpecialtyConceptIds)) as.integer(emergencySpecialtyConceptIds) else integer()

  x_cols <- colnames(x)
  person_col <- if ("person_id" %in% x_cols) "person_id" else "subject_id"

  cohort_df <- x |> dplyr::collect()
  if (nrow(cohort_df) == 0) {
    return(x)
  }

  provider_df <- if ("provider" %in% names(cdm)) {
    cdm$provider |>
      dplyr::select("provider_id", "specialty_concept_id") |>
      dplyr::collect()
  } else {
    tibble::tibble(provider_id = integer(), specialty_concept_id = integer())
  }

  visit_df <- if ("visit_occurrence" %in% names(cdm)) {
    cdm$visit_occurrence |>
      dplyr::filter(.data$person_id %in% !!unique(cohort_df[[person_col]])) |>
      dplyr::select(
        "visit_occurrence_id",
        person_id = "person_id",
        "visit_concept_id",
        "visit_start_date",
        "provider_id"
      ) |>
      dplyr::collect()
  } else {
    tibble::tibble(
      visit_occurrence_id = integer(), person_id = integer(),
      visit_concept_id = integer(), visit_start_date = as.Date(character()),
      provider_id = integer()
    )
  }

  visit_df <- visit_df |>
    dplyr::left_join(provider_df, by = "provider_id") |>
    dplyr::mutate(
      is_emergency = (.data$visit_concept_id %in% emergencyVisitConceptIds) |
        (!is.na(.data$specialty_concept_id) & .data$specialty_concept_id %in% emergencySpecialtyConceptIds)
    ) |>
    dplyr::filter(.data$is_emergency)

  if (!is.null(specialties) && length(specialties) > 0) {
    for (s_name in names(specialties)) {
      s_ids <- as.integer(specialties[[s_name]])
      visit_df[[paste0("is_spec_", s_name)]] <- !is.na(visit_df$specialty_concept_id) &
        visit_df$specialty_concept_id %in% s_ids
    }
  }

  spec_cols <- if (!is.null(specialties)) paste0("is_spec_", names(specialties)) else character()

  res_list <- list(cohort_df)

  for (win_name in names(clean_window)) {
    win_range <- clean_window[[win_name]]
    w_start <- win_range[1]
    w_end <- win_range[2]

    win_events <- cohort_df |>
      dplyr::inner_join(visit_df, by = c("subject_id" = "person_id")) |>
      dplyr::mutate(
        win_start_dt = as.Date(.data[[indexDate]] + w_start),
        win_end_dt = as.Date(.data[[indexDate]] + w_end),
        cens_dt = if (!is.null(censorDate)) .data[[censorDate]] else as.Date(NA),
        actual_end_dt = if (!is.null(censorDate)) pmin(.data$win_end_dt, .data$cens_dt, na.rm = TRUE) else .data$win_end_dt
      ) |>
      dplyr::filter(
        .data$visit_start_date >= .data$win_start_dt &
          .data$visit_start_date <= .data$actual_end_dt
      )

    win_summary <- win_events |>
      dplyr::group_by(.data$subject_id) |>
      dplyr::summarise(
        er_cnt = if (countBy == "days") length(unique(.data$visit_start_date)) else dplyr::n(),
        dplyr::across(
          dplyr::all_of(spec_cols),
          ~ if (countBy == "days") length(unique(.data$visit_start_date[which(.x)])) else sum(ifelse(.x, 1L, 0L), na.rm = TRUE)
        ),
        .groups = "drop"
      )

    c_er <- paste0("emergency_visits_", win_name)
    names(win_summary)[names(win_summary) == "er_cnt"] <- c_er

    if (!is.null(specialties)) {
      for (s_name in names(specialties)) {
        orig_col <- paste0("is_spec_", s_name)
        target_col <- paste0(s_name, "_emergency_visits_", win_name)
        names(win_summary)[names(win_summary) == orig_col] <- target_col
      }
    }

    res_list <- c(res_list, list(win_summary))
  }

  final_df <- res_list[[1]]
  for (k in 2:length(res_list)) {
    final_df <- final_df |>
      dplyr::left_join(res_list[[k]], by = "subject_id")
  }

  metric_cols <- setdiff(colnames(final_df), x_cols)
  for (col in metric_cols) {
    final_df[[col]] <- dplyr::coalesce(final_df[[col]], 0L)
  }

  table_name <- if (!is.null(name)) name else omopgenerics::uniqueTableName(omopgenerics::tmpPrefix())
  cdm <- omopgenerics::insertTable(cdm = cdm, name = table_name, table = final_df, overwrite = TRUE)
  if (inherits(x, "cohort_table")) {
    cdm[[table_name]] <- omopgenerics::newCohortTable(
      cdm[[table_name]],
      cohortSetRef = attr(x, "cohort_set"),
      cohortAttritionRef = attr(x, "cohort_attrition"),
      .softValidation = TRUE
    )
  }
  cdm[[table_name]]
}

#' @rdname addEmergencyCare
#' @export
addEmergency <- addEmergencyCare

#' @rdname addEmergencyCare
#' @export
addEmergencyVisits <- addEmergencyCare
