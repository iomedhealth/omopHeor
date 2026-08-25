#' Add Inpatient and ICU Hospitalization Metrics to a Cohort
#'
#' @param x A cohort table or cdm_table.
#' @param indexDate Date variable in `x` anchoring the observation window. Default: `"cohort_start_date"`.
#' @param censorDate Optional date variable in `x` to censor observation.
#' @param window A named or unnamed list of 2-element numeric vectors. Default: `list(c(-365, -1), c(0, 365))`.
#' @param visitConceptIds OMOP visit concept IDs for general inpatient stays. Default: `c(9201L, 8717L, 581379L)`.
#' @param icuConceptIds OMOP visit concept IDs for ICU stays. Default: `32037L`.
#' @param icuSpecialtyConceptIds OMOP provider specialty concept IDs for ICU stays. Default: `c(38004500L)`.
#' @param stratifySpecialty Logical; whether to compute specialty breakdown. Default: `FALSE`.
#' @param specialties Optional named list of integer vectors of OMOP specialty concept IDs for granular specialty breakdown. Default: `NULL`.
#' @param readmissions Logical; whether to compute 30-day and 90-day readmissions. Default: `FALSE`.
#' @param countBy Character scalar specifying count granularity: `"days"` to collapse overlapping/contiguous stays into episodes, or `"records"` to count raw rows. Default: `"days"`.
#' @param collapseOverlapping Logical; whether to collapse overlapping and contiguous stays. If `FALSE`, forces `countBy = "records"`. Default: `TRUE`.
#' @param nameStyle Column naming pattern. Default: `"{domain}_{metric}_{window_name}"`.
#' @param name Name of the new table in the write schema. If NULL, a temporary table is returned.
#'
#' @return The cohort table `x` with added inpatient metric columns.
#' @aliases addHospitalizations addInpatient addIcuStays
#' @export
addInpatients <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  visitConceptIds = c(9201L, 8717L, 581379L),
  icuConceptIds = 32037L,
  icuSpecialtyConceptIds = c(38004500L),
  stratifySpecialty = FALSE,
  specialties = NULL,
  readmissions = FALSE,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "{domain}_{metric}_{window_name}",
  name = NULL
) {
  # ponytail: windowed dbplyr query against visit_occurrence with 0-fill left join
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

  visitConceptIds <- as.integer(visitConceptIds)
  icuConceptIds <- as.integer(icuConceptIds)
  icuSpecialtyConceptIds <- if (!is.null(icuSpecialtyConceptIds)) as.integer(icuSpecialtyConceptIds) else integer()
  all_concepts <- unique(c(visitConceptIds, icuConceptIds))

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
      dplyr::filter(.data$person_id %in% !!unique(cohort_df[[person_col]]) &
        .data$visit_concept_id %in% !!all_concepts) |>
      dplyr::select(
        "visit_occurrence_id",
        person_id = "person_id",
        "visit_concept_id",
        "visit_start_date",
        "visit_end_date",
        "provider_id"
      ) |>
      dplyr::collect()
  } else {
    tibble::tibble(
      visit_occurrence_id = integer(), person_id = integer(),
      visit_concept_id = integer(), visit_start_date = as.Date(character()),
      visit_end_date = as.Date(character()), provider_id = integer()
    )
  }

  visit_df <- visit_df |>
    dplyr::left_join(provider_df, by = "provider_id")

  if (!is.null(specialties) && length(specialties) > 0) {
    for (s_name in names(specialties)) {
      s_ids <- as.integer(specialties[[s_name]])
      visit_df[[paste0("is_spec_", s_name)]] <- !is.na(visit_df$specialty_concept_id) &
        visit_df$specialty_concept_id %in% s_ids
    }
  }

  spec_cols <- if (!is.null(specialties)) paste0("is_spec_", names(specialties)) else character()

  # Process metrics per window
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
      ) |>
      dplyr::mutate(
        end_dt = dplyr::coalesce(.data$visit_end_date, .data$visit_start_date),
        los_days = pmax(0, as.numeric(difftime(.data$end_dt, .data$visit_start_date, units = "days"))),
        is_icu = (.data$visit_concept_id %in% icuConceptIds) |
          (!is.na(.data$specialty_concept_id) & .data$specialty_concept_id %in% icuSpecialtyConceptIds)
      )

    if (countBy == "days" && nrow(win_events) > 0) {
      # Interval collapsing for overlapping/contiguous stays
      ordered_stays <- win_events |>
        dplyr::arrange(.data$subject_id, .data$visit_start_date, .data$end_dt) |>
        dplyr::group_by(.data$subject_id) |>
        dplyr::mutate(
          max_end_num = cummax(as.numeric(.data$end_dt)),
          is_new_episode = dplyr::if_else(
            dplyr::row_number() == 1L | as.numeric(.data$visit_start_date) > dplyr::lag(.data$max_end_num) + 1,
            1L,
            0L
          ),
          episode_id = cumsum(.data$is_new_episode)
        )

      episodes <- ordered_stays |>
        dplyr::group_by(.data$subject_id, .data$episode_id) |>
        dplyr::summarise(
          ep_start = min(.data$visit_start_date, na.rm = TRUE),
          ep_end = max(.data$end_dt, na.rm = TRUE),
          ep_los = max(0, as.numeric(difftime(max(.data$end_dt), min(.data$visit_start_date), units = "days"))),
          has_inp = any(!.data$is_icu),
          icu_adm_cnt = sum(ifelse(.data$is_icu, 1L, 0L), na.rm = TRUE),
          icu_los_cnt = sum(ifelse(.data$is_icu, .data$los_days, 0), na.rm = TRUE),
          dplyr::across(
            dplyr::all_of(spec_cols),
            ~ any(.x & !.data$is_icu)
          ),
          .groups = "drop"
        )

      if (readmissions && nrow(episodes) > 0) {
        episodes <- episodes |>
          dplyr::arrange(.data$subject_id, .data$ep_start) |>
          dplyr::group_by(.data$subject_id) |>
          dplyr::mutate(
            prev_ep_end = dplyr::lag(.data$ep_end),
            ep_gap = as.numeric(difftime(.data$ep_start, .data$prev_ep_end, units = "days")),
            readm_30 = ifelse(!is.na(.data$ep_gap) & .data$ep_gap >= 0 & .data$ep_gap <= 30, 1L, 0L),
            readm_90 = ifelse(!is.na(.data$ep_gap) & .data$ep_gap >= 0 & .data$ep_gap <= 90, 1L, 0L)
          ) |>
          dplyr::ungroup()
      } else {
        episodes$readm_30 <- 0L
        episodes$readm_90 <- 0L
      }

      win_summary <- episodes |>
        dplyr::group_by(.data$subject_id) |>
        dplyr::summarise(
          inp_adm = sum(ifelse(.data$has_inp, 1L, 0L), na.rm = TRUE),
          inp_los = sum(ifelse(.data$has_inp, .data$ep_los, 0), na.rm = TRUE),
          icu_adm = sum(.data$icu_adm_cnt, na.rm = TRUE),
          icu_los = sum(.data$icu_los_cnt, na.rm = TRUE),
          readm_30 = sum(.data$readm_30, na.rm = TRUE),
          readm_90 = sum(.data$readm_90, na.rm = TRUE),
          dplyr::across(
            dplyr::all_of(spec_cols),
            ~ sum(ifelse(.x, 1L, 0L), na.rm = TRUE)
          ),
          .groups = "drop"
        ) |>
        dplyr::mutate(
          inp_mean_los = ifelse(.data$inp_adm > 0, .data$inp_los / .data$inp_adm, 0),
          icu_mean_los = ifelse(.data$icu_adm > 0, .data$icu_los / .data$icu_adm, 0)
        )
    } else {
      if (readmissions && nrow(win_events) > 0) {
        win_events <- win_events |>
          dplyr::arrange(.data$subject_id, .data$visit_start_date) |>
          dplyr::group_by(.data$subject_id) |>
          dplyr::mutate(
            prev_end = dplyr::lag(.data$end_dt),
            gap = as.numeric(difftime(.data$visit_start_date, .data$prev_end, units = "days")),
            readm_30 = ifelse(!is.na(.data$gap) & .data$gap >= 0 & .data$gap <= 30, 1L, 0L),
            readm_90 = ifelse(!is.na(.data$gap) & .data$gap >= 0 & .data$gap <= 90, 1L, 0L)
          ) |>
          dplyr::ungroup()
      } else {
        win_events$readm_30 <- 0L
        win_events$readm_90 <- 0L
      }

      win_summary <- win_events |>
        dplyr::group_by(.data$subject_id) |>
        dplyr::summarise(
          inp_adm = sum(ifelse(!.data$is_icu, 1L, 0L), na.rm = TRUE),
          inp_los = sum(ifelse(!.data$is_icu, .data$los_days, 0), na.rm = TRUE),
          icu_adm = sum(ifelse(.data$is_icu, 1L, 0L), na.rm = TRUE),
          icu_los = sum(ifelse(.data$is_icu, .data$los_days, 0), na.rm = TRUE),
          readm_30 = sum(.data$readm_30, na.rm = TRUE),
          readm_90 = sum(.data$readm_90, na.rm = TRUE),
          dplyr::across(
            dplyr::all_of(spec_cols),
            ~ sum(ifelse(.x & !.data$is_icu, 1L, 0L), na.rm = TRUE)
          ),
          .groups = "drop"
        ) |>
        dplyr::mutate(
          inp_mean_los = ifelse(.data$inp_adm > 0, .data$inp_los / .data$inp_adm, 0),
          icu_mean_los = ifelse(.data$icu_adm > 0, .data$icu_los / .data$icu_adm, 0)
        )
    }

    # Naming
    c_inp_adm <- paste0("inpatient_admissions_", win_name)
    c_inp_los <- paste0("inpatient_los_days_", win_name)
    c_inp_mean_los <- paste0("inpatient_mean_los_days_", win_name)
    c_icu_adm <- paste0("icu_admissions_", win_name)
    c_icu_los <- paste0("icu_los_days_", win_name)
    c_icu_mean_los <- paste0("icu_mean_los_days_", win_name)
    c_readm_30 <- paste0("readmissions_30d_", win_name)
    c_readm_90 <- paste0("readmissions_90d_", win_name)

    names(win_summary)[names(win_summary) == "inp_adm"] <- c_inp_adm
    names(win_summary)[names(win_summary) == "inp_los"] <- c_inp_los
    names(win_summary)[names(win_summary) == "inp_mean_los"] <- c_inp_mean_los
    names(win_summary)[names(win_summary) == "icu_adm"] <- c_icu_adm
    names(win_summary)[names(win_summary) == "icu_los"] <- c_icu_los
    names(win_summary)[names(win_summary) == "icu_mean_los"] <- c_icu_mean_los
    names(win_summary)[names(win_summary) == "readm_30"] <- c_readm_30
    names(win_summary)[names(win_summary) == "readm_90"] <- c_readm_90

    if (!is.null(specialties)) {
      for (s_name in names(specialties)) {
        orig_col <- paste0("is_spec_", s_name)
        target_col <- paste0(s_name, "_inpatient_admissions_", win_name)
        names(win_summary)[names(win_summary) == orig_col] <- target_col
      }
    }

    if (!readmissions) {
      win_summary <- win_summary |> dplyr::select(-dplyr::all_of(c(c_readm_30, c_readm_90)))
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
    final_df[[col]] <- dplyr::coalesce(final_df[[col]], 0)
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

#' @rdname addInpatients
#' @export
addHospitalizations <- addInpatients

#' @rdname addInpatients
#' @export
addInpatient <- addInpatients

#' @rdname addInpatients
#' @export
addIcuStays <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  icuConceptIds = 32037L,
  icuSpecialtyConceptIds = c(38004500L),
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "{domain}_{metric}_{window_name}",
  name = NULL
) {
  # Call addInpatients with visitConceptIds set to empty to focus on ICU metrics.
  res <- addInpatients(
    x = x,
    indexDate = indexDate,
    censorDate = censorDate,
    window = window,
    visitConceptIds = integer(),
    icuConceptIds = icuConceptIds,
    icuSpecialtyConceptIds = icuSpecialtyConceptIds,
    readmissions = FALSE,
    countBy = countBy,
    collapseOverlapping = collapseOverlapping,
    nameStyle = nameStyle,
    name = name
  )

  # Drop general inpatient columns to return ONLY ICU-related values
  cols_to_remove <- grep("^inpatient_", colnames(res), value = TRUE)
  if (length(cols_to_remove) > 0) {
    res <- res |> dplyr::select(-dplyr::all_of(cols_to_remove))
  }

  return(res)
}
