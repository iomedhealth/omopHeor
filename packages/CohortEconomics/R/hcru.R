#' Extract Healthcare Resource Utilization (HCRU) from OMOP CDM (Stage 2: HCRU)
#'
#' @description
#' `extract_hcru()` queries the OMOP CDM to extract direct medical costs and
#' resource utilization across five core clinical domains (inpatient, outpatient,
#' pharmacotherapy, diagnostics/procedures, post-acute care) for patients in the
#' study cohorts across baseline and follow-up temporal windows.
#'
#' In Cost-Effectiveness Analysis (CEA), Healthcare Resource Utilization (HCRU) forms
#' the numerator of the Incremental Cost-Effectiveness Ratio (ICER). This function
#' links OMOP `cost` records to clinical events and tags costs with the patient's
#' health state (e.g., before or after the outcome event).
#'
#' @param study An `omopheor_study` (`hermes_study`) or `omopheor_hcru` (`hermes_hcru`) object.
#' @param baseline_window Relative days from cohort start date defining baseline (default `c(-365, -1)`).
#' @param followup_window Relative days from cohort start date defining follow-up (default `c(0, 365)`).
#' @param cost_field Column name in `cost` table to aggregate (default `"total_paid"`).
#' @param visit_domains Visit categories to extract from `visit_occurrence`.
#' @param pharmacotherapy Logical, whether to extract drug exposures (default `TRUE`).
#' @param diagnostics Logical, whether to extract procedures and measurements (default `TRUE`).
#' @param post_acute Logical, whether to extract post-acute/SNF/hospice care (default `TRUE`).
#' @param calculate_readmissions Logical, whether to compute 30-day and 90-day readmissions (default `FALSE`).
#' @param persistence Logical, whether to calculate Proportion of Days Covered (PDC) (default `FALSE`).
#' @param count_by Character scalar, either `"days"` (count distinct visit dates) or `"records"` (count raw rows) (default `"days"`).
#'
#' @return An `omopheor_hcru` (`hermes_hcru`) object enriched with `study$costs` and `study$hcru`.
#'
#' @export
extract_hcru <- function(
  study,
  baseline_window = c(-365, -1),
  followup_window = c(0, 365),
  cost_field = "total_paid",
  visit_domains = c("inpatient", "outpatient", "emergency", "specialist"),
  pharmacotherapy = TRUE,
  diagnostics = TRUE,
  post_acute = TRUE,
  calculate_readmissions = FALSE,
  persistence = FALSE,
  count_by = c("days", "records")
) {
  # ponytail: database-side filtering by cohort subjects and windowed aggregation
  if (!inherits(study, "omopheor_study") && !inherits(study, "hermes_study") &&
      !inherits(study, "omopheor_hcru") && !inherits(study, "hermes_hcru")) {
    stop("Argument 'study' must be an omopheor_study or omopheor_hcru object")
  }
  if (!is.numeric(baseline_window) || length(baseline_window) != 2 || baseline_window[1] > baseline_window[2]) {
    stop("Argument 'baseline_window' must be a numeric vector of length 2 with start <= end")
  }
  if (!is.numeric(followup_window) || length(followup_window) != 2 || followup_window[1] > followup_window[2]) {
    stop("Argument 'followup_window' must be a numeric vector of length 2 with start <= end")
  }
  if (!is.character(cost_field) || length(cost_field) != 1) {
    stop("Argument 'cost_field' must be a single string")
  }
  count_by <- if (is.character(count_by)) tolower(count_by[1]) else "days"
  if (!count_by %in% c("days", "records")) count_by <- "days"

  cdm <- study$cdm
  target_name <- study$target_cohort
  comp_name <- study$comparator_cohort

  # 1. Extract study cohort patients and index dates
  target_df <- if (!is.null(target_name) && target_name %in% names(cdm)) {
    cdm[[target_name]] |>
      dplyr::select(subject_id = "subject_id", cohort_start_date = "cohort_start_date", cohort_end_date = "cohort_end_date") |>
      dplyr::collect()
  } else {
    tibble::tibble(subject_id = integer(), cohort_start_date = as.Date(character()), cohort_end_date = as.Date(character()))
  }

  comp_df <- if (!is.null(comp_name) && comp_name %in% names(cdm)) {
    cdm[[comp_name]] |>
      dplyr::select(subject_id = "subject_id", cohort_start_date = "cohort_start_date", cohort_end_date = "cohort_end_date") |>
      dplyr::collect()
  } else {
    tibble::tibble(subject_id = integer(), cohort_start_date = as.Date(character()), cohort_end_date = as.Date(character()))
  }

  cohort_pts <- dplyr::bind_rows(target_df, comp_df) |>
    dplyr::group_by(.data$subject_id) |>
    dplyr::summarise(
      cohort_start_date = min(.data$cohort_start_date, na.rm = TRUE),
      cohort_end_date = max(.data$cohort_end_date, na.rm = TRUE),
      .groups = "drop"
    )

  outcome_name <- study$outcome_cohort
  if (!is.null(outcome_name) && outcome_name %in% names(cdm)) {
    outcome_df <- cdm[[outcome_name]] |>
      dplyr::select(subject_id = "subject_id", outcome_date = "cohort_start_date") |>
      dplyr::collect() |>
      dplyr::group_by(.data$subject_id) |>
      dplyr::summarise(outcome_date = min(.data$outcome_date, na.rm = TRUE), .groups = "drop")
    cohort_pts <- cohort_pts |>
      dplyr::left_join(outcome_df, by = "subject_id")
  } else {
    cohort_pts$outcome_date <- as.Date(NA)
  }

  cohort_pts <- cohort_pts |>
    dplyr::mutate(
      baseline_start = as.Date(.data$cohort_start_date + baseline_window[1]),
      baseline_end = as.Date(.data$cohort_start_date + baseline_window[2]),
      followup_start = as.Date(.data$cohort_start_date + followup_window[1]),
      followup_end = as.Date(.data$cohort_start_date + followup_window[2])
    )

  # 2. Zero-utilization scaffolding across baseline and followup windows
  scaffold <- if (nrow(cohort_pts) > 0) {
    as.data.frame(
      expand.grid(
        subject_id = cohort_pts$subject_id,
        window = c("baseline", "followup"),
        stringsAsFactors = FALSE
      )
    ) |>
      tibble::as_tibble() |>
      dplyr::arrange(.data$subject_id, .data$window)
  } else {
    tibble::tibble(subject_id = integer(), window = character())
  }

  # Helper: Window event mapper
  map_to_windows <- function(df) {
    if (nrow(df) == 0 || nrow(cohort_pts) == 0) {
      return(df |> dplyr::mutate(window = character()) |> dplyr::filter(FALSE))
    }
    j <- df |> dplyr::inner_join(cohort_pts, by = "subject_id")
    b <- j |>
      dplyr::filter(.data$event_date >= .data$baseline_start & .data$event_date <= .data$baseline_end) |>
      dplyr::mutate(window = "baseline")
    f <- j |>
      dplyr::filter(.data$event_date >= .data$followup_start & .data$event_date <= .data$followup_end) |>
      dplyr::mutate(window = "followup")
    dplyr::bind_rows(b, f)
  }

  # 3. Domain: Inpatient & ICU
  visit_raw <- if ("visit_occurrence" %in% names(cdm) && nrow(cohort_pts) > 0) {
    cohort_sub_ids <- cohort_pts$subject_id
    cdm$visit_occurrence |>
      dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
      dplyr::select(
        "visit_occurrence_id",
        subject_id = "person_id",
        "visit_concept_id",
        "visit_start_date",
        "visit_end_date",
        "provider_id"
      ) |>
      dplyr::collect()
  } else {
    tibble::tibble(
      visit_occurrence_id = integer(), subject_id = integer(),
      visit_concept_id = integer(), visit_start_date = as.Date(character()),
      visit_end_date = as.Date(character()), provider_id = integer()
    )
  }

  inp_visits <- visit_raw |>
    dplyr::filter(.data$visit_concept_id %in% c(9201L, 32037L, 8717L, 581379L)) |>
    dplyr::mutate(
      event_date = .data$visit_start_date,
      end_date = dplyr::coalesce(.data$visit_end_date, .data$visit_start_date),
      los_days = pmax(0, as.numeric(difftime(.data$end_date, .data$visit_start_date, units = "days"))),
      is_icu = .data$visit_concept_id == 32037L
    )

  if (calculate_readmissions && nrow(inp_visits) > 0) {
    inp_visits <- inp_visits |>
      dplyr::arrange(.data$subject_id, .data$visit_start_date) |>
      dplyr::group_by(.data$subject_id) |>
      dplyr::mutate(
        prev_end_date = dplyr::lag(.data$end_date),
        days_gap = as.numeric(difftime(.data$visit_start_date, .data$prev_end_date, units = "days")),
        readmissions_30d = ifelse(!is.na(.data$days_gap) & .data$days_gap >= 0 & .data$days_gap <= 30, 1L, 0L),
        readmissions_90d = ifelse(!is.na(.data$days_gap) & .data$days_gap >= 0 & .data$days_gap <= 90, 1L, 0L)
      ) |>
      dplyr::ungroup()
  } else {
    inp_visits$readmissions_30d <- 0L
    inp_visits$readmissions_90d <- 0L
  }

  inp_windowed <- map_to_windows(inp_visits)
  inp_sum <- if (count_by == "days" && nrow(inp_windowed) > 0) {
    ordered_inp <- inp_windowed |>
      dplyr::arrange(.data$subject_id, .data$window, .data$event_date, .data$end_date) |>
      dplyr::group_by(.data$subject_id, .data$window) |>
      dplyr::mutate(
        max_end_num = cummax(as.numeric(.data$end_date)),
        is_new_ep = dplyr::if_else(
          dplyr::row_number() == 1L | as.numeric(.data$event_date) > dplyr::lag(.data$max_end_num) + 1,
          1L,
          0L
        ),
        ep_id = cumsum(.data$is_new_ep)
      )

    ep_summary <- ordered_inp |>
      dplyr::group_by(.data$subject_id, .data$window, .data$ep_id) |>
      dplyr::summarise(
        ep_start = min(.data$event_date, na.rm = TRUE),
        ep_end = max(.data$end_date, na.rm = TRUE),
        ep_los = max(0, as.numeric(difftime(max(.data$end_date), min(.data$event_date), units = "days"))),
        has_inp = any(!.data$is_icu),
        icu_adm = sum(ifelse(.data$is_icu, 1L, 0L), na.rm = TRUE),
        icu_los = sum(ifelse(.data$is_icu, .data$los_days, 0), na.rm = TRUE),
        .groups = "drop"
      )

    if (calculate_readmissions && nrow(ep_summary) > 0) {
      ep_summary <- ep_summary |>
        dplyr::arrange(.data$subject_id, .data$window, .data$ep_start) |>
        dplyr::group_by(.data$subject_id, .data$window) |>
        dplyr::mutate(
          prev_ep_end = dplyr::lag(.data$ep_end),
          ep_gap = as.numeric(difftime(.data$ep_start, .data$prev_ep_end, units = "days")),
          readmissions_30d = ifelse(!is.na(.data$ep_gap) & .data$ep_gap >= 0 & .data$ep_gap <= 30, 1L, 0L),
          readmissions_90d = ifelse(!is.na(.data$ep_gap) & .data$ep_gap >= 0 & .data$ep_gap <= 90, 1L, 0L)
        ) |>
        dplyr::ungroup()
    } else {
      ep_summary$readmissions_30d <- 0L
      ep_summary$readmissions_90d <- 0L
    }

    ep_summary |>
      dplyr::group_by(.data$subject_id, .data$window) |>
      dplyr::summarise(
        inpatient_admissions = sum(ifelse(.data$has_inp, 1L, 0L), na.rm = TRUE),
        inpatient_los_days = sum(ifelse(.data$has_inp, .data$ep_los, 0), na.rm = TRUE),
        icu_admissions = sum(.data$icu_adm, na.rm = TRUE),
        icu_los_days = sum(.data$icu_los, na.rm = TRUE),
        readmissions_30d = sum(.data$readmissions_30d, na.rm = TRUE),
        readmissions_90d = sum(.data$readmissions_90d, na.rm = TRUE),
        .groups = "drop"
      )
  } else {
    inp_windowed |>
      dplyr::group_by(.data$subject_id, .data$window) |>
      dplyr::summarise(
        inpatient_admissions = sum(ifelse(!.data$is_icu, 1L, 0L), na.rm = TRUE),
        inpatient_los_days = sum(ifelse(!.data$is_icu, .data$los_days, 0), na.rm = TRUE),
        icu_admissions = sum(ifelse(.data$is_icu, 1L, 0L), na.rm = TRUE),
        icu_los_days = sum(ifelse(.data$is_icu, .data$los_days, 0), na.rm = TRUE),
        readmissions_30d = sum(.data$readmissions_30d, na.rm = TRUE),
        readmissions_90d = sum(.data$readmissions_90d, na.rm = TRUE),
        .groups = "drop"
      )
  }

  inpatient_df <- scaffold |>
    dplyr::left_join(inp_sum, by = c("subject_id", "window")) |>
    dplyr::mutate(
      inpatient_admissions = dplyr::coalesce(.data$inpatient_admissions, 0L),
      inpatient_los_days = dplyr::coalesce(.data$inpatient_los_days, 0),
      icu_admissions = dplyr::coalesce(.data$icu_admissions, 0L),
      icu_los_days = dplyr::coalesce(.data$icu_los_days, 0),
      readmissions_30d = dplyr::coalesce(.data$readmissions_30d, 0L),
      readmissions_90d = dplyr::coalesce(.data$readmissions_90d, 0L)
    )

  # 4. Domain: Outpatient & Emergency
  provider_raw <- if ("provider" %in% names(cdm)) {
    cdm$provider |>
      dplyr::select("provider_id", "specialty_concept_id") |>
      dplyr::collect()
  } else {
    tibble::tibble(provider_id = integer(), specialty_concept_id = integer())
  }

  out_visits <- visit_raw |>
    dplyr::filter(.data$visit_concept_id %in% c(9202L, 9203L, 581477L)) |>
    dplyr::left_join(provider_raw, by = "provider_id") |>
    dplyr::mutate(
      event_date = .data$visit_start_date,
      is_ed = .data$visit_concept_id == 9203L,
      is_gp = .data$visit_concept_id %in% c(9202L, 581477L) &
        (is.na(.data$specialty_concept_id) | .data$specialty_concept_id == 38004446L),
      is_spec = .data$visit_concept_id %in% c(9202L, 581477L) &
        (!is.na(.data$specialty_concept_id) & .data$specialty_concept_id != 38004446L),
      is_other = .data$visit_concept_id %in% c(9202L, 581477L) & !.data$is_gp & !.data$is_spec
    )

  out_windowed <- map_to_windows(out_visits)
  out_sum <- out_windowed |>
    dplyr::group_by(.data$subject_id, .data$window) |>
    dplyr::summarise(
      emergency_visits = if (count_by == "days") length(unique(.data$event_date[which(.data$is_ed)])) else sum(ifelse(.data$is_ed, 1L, 0L), na.rm = TRUE),
      gp_visits = if (count_by == "days") length(unique(.data$event_date[which(.data$is_gp)])) else sum(ifelse(.data$is_gp, 1L, 0L), na.rm = TRUE),
      specialist_visits = if (count_by == "days") length(unique(.data$event_date[which(.data$is_spec)])) else sum(ifelse(.data$is_spec, 1L, 0L), na.rm = TRUE),
      other_outpatient_visits = if (count_by == "days") length(unique(.data$event_date[which(.data$is_other)])) else sum(ifelse(.data$is_other, 1L, 0L), na.rm = TRUE),
      .groups = "drop"
    )

  outpatient_df <- scaffold |>
    dplyr::left_join(out_sum, by = c("subject_id", "window")) |>
    dplyr::mutate(
      emergency_visits = dplyr::coalesce(.data$emergency_visits, 0L),
      gp_visits = dplyr::coalesce(.data$gp_visits, 0L),
      specialist_visits = dplyr::coalesce(.data$specialist_visits, 0L),
      other_outpatient_visits = dplyr::coalesce(.data$other_outpatient_visits, 0L)
    )

  # 5. Domain: Pharmacotherapy
  pharma_df <- if (pharmacotherapy && "drug_exposure" %in% names(cdm) && nrow(cohort_pts) > 0) {
    cohort_sub_ids <- cohort_pts$subject_id
    drug_raw <- cdm$drug_exposure |>
      dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
      dplyr::select("drug_exposure_id", subject_id = "person_id", "drug_concept_id", "drug_exposure_start_date", "days_supply") |>
      dplyr::collect() |>
      dplyr::mutate(
        event_date = .data$drug_exposure_start_date,
        days_supply = dplyr::coalesce(as.numeric(.data$days_supply), 0)
      )

    drug_windowed <- map_to_windows(drug_raw)
    pharma_sum <- drug_windowed |>
      dplyr::group_by(.data$subject_id, .data$window) |>
      dplyr::summarise(
        prescription_fills = dplyr::n(),
        total_days_supply = sum(.data$days_supply, na.rm = TRUE),
        .groups = "drop"
      )

    p_df <- scaffold |>
      dplyr::left_join(pharma_sum, by = c("subject_id", "window")) |>
      dplyr::mutate(
        prescription_fills = dplyr::coalesce(.data$prescription_fills, 0L),
        total_days_supply = dplyr::coalesce(.data$total_days_supply, 0)
      )

    if (persistence) {
      base_len <- abs(baseline_window[2] - baseline_window[1]) + 1
      foll_len <- abs(followup_window[2] - followup_window[1]) + 1
      p_df |>
        dplyr::mutate(
          win_len = ifelse(.data$window == "baseline", base_len, foll_len),
          pdc = pmin(1.0, .data$total_days_supply / .data$win_len)
        ) |>
        dplyr::select(-"win_len")
    } else {
      p_df |> dplyr::mutate(pdc = NA_real_)
    }
  } else {
    scaffold |> dplyr::mutate(prescription_fills = 0L, total_days_supply = 0, pdc = NA_real_)
  }

  # 6. Domain: Diagnostics & Procedures
  proc_diag_df <- if (diagnostics && nrow(cohort_pts) > 0) {
    cohort_sub_ids <- cohort_pts$subject_id
    proc_sum <- if ("procedure_occurrence" %in% names(cdm)) {
      cdm$procedure_occurrence |>
        dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
        dplyr::select("procedure_occurrence_id", subject_id = "person_id", "procedure_concept_id", "procedure_date") |>
        dplyr::collect() |>
        dplyr::mutate(event_date = .data$procedure_date) |>
        map_to_windows() |>
        dplyr::group_by(.data$subject_id, .data$window) |>
        dplyr::summarise(procedure_count = dplyr::n(), .groups = "drop")
    } else {
      tibble::tibble(subject_id = integer(), window = character(), procedure_count = integer())
    }

    meas_sum <- if ("measurement" %in% names(cdm)) {
      cdm$measurement |>
        dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
        dplyr::select("measurement_id", subject_id = "person_id", "measurement_concept_id", "measurement_date") |>
        dplyr::collect() |>
        dplyr::mutate(event_date = .data$measurement_date) |>
        map_to_windows() |>
        dplyr::group_by(.data$subject_id, .data$window) |>
        dplyr::summarise(measurement_count = dplyr::n(), .groups = "drop")
    } else {
      tibble::tibble(subject_id = integer(), window = character(), measurement_count = integer())
    }

    scaffold |>
      dplyr::left_join(proc_sum, by = c("subject_id", "window")) |>
      dplyr::left_join(meas_sum, by = c("subject_id", "window")) |>
      dplyr::mutate(
        procedure_count = dplyr::coalesce(.data$procedure_count, 0L),
        measurement_count = dplyr::coalesce(.data$measurement_count, 0L)
      )
  } else {
    scaffold |> dplyr::mutate(procedure_count = 0L, measurement_count = 0L)
  }

  # 7. Domain: Post-Acute Care
  post_acute_df <- if (post_acute && "visit_occurrence" %in% names(cdm) && nrow(cohort_pts) > 0) {
    post_visits <- visit_raw |>
      dplyr::filter(.data$visit_concept_id %in% c(42898160L, 32036L, 8546L)) |>
      dplyr::mutate(
        event_date = .data$visit_start_date,
        end_date = dplyr::coalesce(.data$visit_end_date, .data$visit_start_date),
        los_days = pmax(0, as.numeric(difftime(.data$end_date, .data$visit_start_date, units = "days")))
      )

    post_windowed <- map_to_windows(post_visits)
    post_sum <- post_windowed |>
      dplyr::group_by(.data$subject_id, .data$window) |>
      dplyr::summarise(
        post_acute_stays = dplyr::n(),
        post_acute_los_days = sum(.data$los_days, na.rm = TRUE),
        .groups = "drop"
      )

    scaffold |>
      dplyr::left_join(post_sum, by = c("subject_id", "window")) |>
      dplyr::mutate(
        post_acute_stays = dplyr::coalesce(.data$post_acute_stays, 0L),
        post_acute_los_days = dplyr::coalesce(.data$post_acute_los_days, 0)
      )
  } else {
    scaffold |> dplyr::mutate(post_acute_stays = 0L, post_acute_los_days = 0)
  }

  # 8. Financial Linkage
  if (!"cost" %in% names(cdm)) {
    warning("Missing 'cost' table in CDM. Skipping cost extraction.")
    costs <- tibble::tibble(
      subject_id = integer(),
      total_paid = numeric(),
      total_charge = numeric(),
      health_state = character(),
      cost_domain = character()
    )
    windowed_costs_sum <- tibble::tibble(
      subject_id = integer(),
      window = character(),
      total_cost = numeric()
    )
  } else {
    cost_raw <- cdm$cost |> dplyr::collect()
    linked_list <- list()

    # Condition costs
    if ("condition_occurrence" %in% names(cdm)) {
      cond_raw <- cdm$condition_occurrence |>
        dplyr::select("condition_occurrence_id", subject_id = "person_id", event_date = "condition_start_date") |>
        dplyr::collect()
      cond_costs <- cost_raw |>
        dplyr::filter(.data$cost_domain_id == "Condition") |>
        dplyr::inner_join(cond_raw, by = c("cost_event_id" = "condition_occurrence_id")) |>
        dplyr::mutate(cost_domain = "Condition")
      linked_list <- c(linked_list, list(cond_costs))
    }

    # Visit costs
    if ("visit_occurrence" %in% names(cdm)) {
      vis_map <- cdm$visit_occurrence |>
        dplyr::select("visit_occurrence_id", subject_id = "person_id", event_date = "visit_start_date") |>
        dplyr::collect()
      vis_costs <- cost_raw |>
        dplyr::filter(.data$cost_domain_id == "Visit") |>
        dplyr::inner_join(vis_map, by = c("cost_event_id" = "visit_occurrence_id")) |>
        dplyr::mutate(cost_domain = "Visit")
      linked_list <- c(linked_list, list(vis_costs))
    }

    # Drug costs
    if ("drug_exposure" %in% names(cdm)) {
      drug_map <- cdm$drug_exposure |>
        dplyr::select("drug_exposure_id", subject_id = "person_id", event_date = "drug_exposure_start_date") |>
        dplyr::collect()
      drug_costs <- cost_raw |>
        dplyr::filter(.data$cost_domain_id == "Drug") |>
        dplyr::inner_join(drug_map, by = c("cost_event_id" = "drug_exposure_id")) |>
        dplyr::mutate(cost_domain = "Drug")
      linked_list <- c(linked_list, list(drug_costs))
    }

    # Procedure costs
    if ("procedure_occurrence" %in% names(cdm)) {
      proc_map <- cdm$procedure_occurrence |>
        dplyr::select("procedure_occurrence_id", subject_id = "person_id", event_date = "procedure_date") |>
        dplyr::collect()
      proc_costs <- cost_raw |>
        dplyr::filter(.data$cost_domain_id == "Procedure") |>
        dplyr::inner_join(proc_map, by = c("cost_event_id" = "procedure_occurrence_id")) |>
        dplyr::mutate(cost_domain = "Procedure")
      linked_list <- c(linked_list, list(proc_costs))
    }

    # Measurement costs
    if ("measurement" %in% names(cdm)) {
      meas_map <- cdm$measurement |>
        dplyr::select("measurement_id", subject_id = "person_id", event_date = "measurement_date") |>
        dplyr::collect()
      meas_costs <- cost_raw |>
        dplyr::filter(.data$cost_domain_id == "Measurement") |>
        dplyr::inner_join(meas_map, by = c("cost_event_id" = "measurement_id")) |>
        dplyr::mutate(cost_domain = "Measurement")
      linked_list <- c(linked_list, list(meas_costs))
    }

    all_linked <- if (length(linked_list) > 0) {
      dplyr::bind_rows(linked_list)
    } else {
      cost_raw |>
        dplyr::mutate(subject_id = integer(), event_date = as.Date(character()), cost_domain = character()) |>
        dplyr::filter(FALSE)
    }

    # Restrict to study cohort patients
    cohort_sub_ids <- cohort_pts$subject_id
    cohort_linked <- all_linked |>
      dplyr::filter(.data$subject_id %in% cohort_sub_ids)

    if (nrow(cohort_linked) > 0) {
      cohort_linked <- cohort_linked |>
        dplyr::inner_join(cohort_pts, by = "subject_id") |>
        dplyr::mutate(
          health_state = ifelse(!is.na(.data$outcome_date) & .data$event_date >= .data$outcome_date, "State_Outcome", "State_Baseline"),
          window = ifelse(
            .data$event_date >= .data$baseline_start & .data$event_date <= .data$baseline_end,
            "baseline",
            ifelse(.data$event_date >= .data$followup_start & .data$event_date <= .data$followup_end, "followup", NA_character_)
          )
        )

      costs <- cohort_linked |>
        dplyr::select("subject_id", "total_paid", "total_charge", "health_state", "cost_domain")

      cost_val_col <- if (cost_field %in% colnames(cohort_linked)) cost_field else "total_paid"
      windowed_costs_sum <- cohort_linked |>
        dplyr::filter(!is.na(.data$window)) |>
        dplyr::group_by(.data$subject_id, .data$window) |>
        dplyr::summarise(
          total_cost = sum(.data[[cost_val_col]], na.rm = TRUE),
          .groups = "drop"
        )
    } else {
      costs <- tibble::tibble(
        subject_id = integer(),
        total_paid = numeric(),
        total_charge = numeric(),
        health_state = character(),
        cost_domain = character()
      )
      windowed_costs_sum <- tibble::tibble(
        subject_id = integer(),
        window = character(),
        total_cost = numeric()
      )
    }
  }

  # 9. Assemble wide patient_summary table
  patient_summary <- scaffold |>
    dplyr::left_join(inpatient_df, by = c("subject_id", "window")) |>
    dplyr::left_join(outpatient_df, by = c("subject_id", "window")) |>
    dplyr::left_join(pharma_df, by = c("subject_id", "window")) |>
    dplyr::left_join(proc_diag_df, by = c("subject_id", "window")) |>
    dplyr::left_join(post_acute_df, by = c("subject_id", "window")) |>
    dplyr::left_join(windowed_costs_sum, by = c("subject_id", "window")) |>
    dplyr::mutate(total_cost = dplyr::coalesce(.data$total_cost, 0))

  res <- c(study, list(
    costs = costs,
    hcru = list(
      inpatient = inpatient_df,
      outpatient = outpatient_df,
      pharmacotherapy = pharma_df,
      procedures_diagnostics = proc_diag_df,
      post_acute = post_acute_df,
      patient_summary = patient_summary
    )
  ))

  new_hermes_hcru(res)
}

#' @rdname extract_hcru
#' @param baselineWindow Relative days from cohort start date defining baseline (default `c(-365, -1)`).
#' @param followupWindow Relative days from cohort start date defining follow-up (default `c(0, 365)`).
#' @param costField Column name in `cost` table to aggregate (default `"total_paid"`).
#' @param visitDomains Visit categories to extract from `visit_occurrence`.
#' @param postAcute Logical, whether to extract post-acute/SNF/hospice care (default `TRUE`).
#' @param calculateReadmissions Logical, whether to compute 30-day and 90-day readmissions (default `FALSE`).
#' @param countBy Character scalar, either `"days"` or `"records"` (default `"days"`).
#' @param count_by Backward compatible snake_case parameter.
#' @export
extractHcru <- function(
  study,
  baselineWindow = c(-365, -1),
  followupWindow = c(0, 365),
  costField = "total_paid",
  visitDomains = c("inpatient", "outpatient", "emergency", "specialist"),
  pharmacotherapy = TRUE,
  diagnostics = TRUE,
  postAcute = TRUE,
  calculateReadmissions = FALSE,
  persistence = FALSE,
  countBy = c("days", "records"),
  count_by = NULL
) {
  cb <- if (!is.null(count_by)) count_by else countBy
  extract_hcru(
    study = study,
    baseline_window = baselineWindow,
    followup_window = followupWindow,
    cost_field = costField,
    visit_domains = visitDomains,
    pharmacotherapy = pharmacotherapy,
    diagnostics = diagnostics,
    post_acute = postAcute,
    calculate_readmissions = calculateReadmissions,
    persistence = persistence,
    count_by = cb
  )
}
