#' Add Direct Medical Costs to a Cohort
#'
#' @param x A cohort table or cdm_table.
#' @param indexDate Date variable in `x` anchoring the observation window. Default: `"cohort_start_date"`.
#' @param censorDate Optional date variable in `x` to censor observation.
#' @param window A named or unnamed list of 2-element numeric vectors. Default: `list(c(-365, -1), c(0, 365))`.
#' @param costField Column name in `cost` table to aggregate. Default: `"total_paid"`.
#' @param domains Clinical domains to extract. Default: `c("Inpatient", "Outpatient", "Drug", "Procedure")`.
#' @param nameStyle Column naming pattern. Default: `"cost_{domain}_{window_name}"`.
#' @param name Name of the new table in the write schema. If NULL, a temporary table is returned.
#'
#' @return The cohort table `x` with added direct medical cost columns.
#' @export
addCosts <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  costField = "total_paid",
  domains = c("Inpatient", "Outpatient", "Drug", "Procedure"),
  nameStyle = "cost_{domain}_{window_name}",
  name = NULL
) {
  # ==============================================================================
  # Polymorphic OMOP COST Table Linkage Architecture
  # ==============================================================================
  #
  #                       +---------------------------------------+
  #                       |            OMOP COST Table            |
  #                       |  (cost_event_id, cost_domain_id, ...) |
  #                       +-------------------+-------------------+
  #                                           |
  #              +----------------------------+----------------------------+
  #              |                            |                            |
  #              v                            v                            v
  #    cost_domain_id = 'Visit'     cost_domain_id = 'Drug'     cost_domain_id = 'Procedure'
  #              |                            |                            |
  #              v                            v                            v
  #    visit_occurrence_id          drug_exposure_id            procedure_occurrence_id
  #    [visit_occurrence]           [drug_exposure]             [procedure_occurrence]
  #              |                            |                            |
  #              +----------------------------+----------------------------+
  #                                           |
  #                                           v
  #                       +---------------------------------------+
  #                       | Temporal Window Matching & Aggregation|
  #                       | [-365, -1] Baseline | [0, 365] Followup|
  #                       +-------------------+-------------------+
  #                                           |
  #                                           v
  #                       +---------------------------------------+
  #                       |  Cost Metrics Attached to Cohort Table|
  #                       |  (cost_inpatient_*, cost_drug_*, etc.)|
  #                       +---------------------------------------+
  # ==============================================================================

  # Validate table references and parameters
  if (!inherits(x, "cdm_table") && !inherits(x, "cohort_table") && !inherits(x, "tbl_dbi")) {
    cli::cli_abort("Argument 'x' must be a cdm_table or cohort_table.")
  }

  cdm <- omopgenerics::cdmReference(x)
  indexDate <- validateIndexDate(indexDate, x)
  censorDate <- validateCensorDate(censorDate, x)
  clean_window <- validateWindow(window)
  name <- validateName(name)
  omopgenerics::assertCharacter(costField, length = 1)

  x_cols <- colnames(x)
  person_col <- if ("person_id" %in% x_cols) "person_id" else "subject_id"

  # Step 1: Collect base study cohort
  cohort_df <- x |> dplyr::collect()
  if (nrow(cohort_df) == 0) {
    return(x)
  }

  cohort_sub_ids <- unique(cohort_df[[person_col]])

  # Step 2: Handle missing or empty OMOP cost table gracefully
  if (!"cost" %in% names(cdm)) {
    cli::cli_warn("Missing 'cost' table in CDM. Populating cost columns with 0.0.")
    cost_events <- tibble::tibble(
      person_id = integer(), event_date = as.Date(character()),
      cost_domain = character(), cost_val = numeric()
    )
  } else {
    cost_raw <- cdm$cost |> dplyr::collect()
    cost_col <- if (costField %in% colnames(cost_raw)) costField else "total_paid"

    if (nrow(cost_raw) == 0) {
      cost_events <- tibble::tibble(
        person_id = integer(), event_date = as.Date(character()),
        cost_domain = character(), cost_val = numeric()
      )
    } else {
      cost_raw <- cost_raw |> dplyr::select(-dplyr::any_of("person_id"))
      linked_list <- list()

      # Step 3a: Link Condition-related costs
      if ("condition_occurrence" %in% names(cdm)) {
        c_df <- cdm$condition_occurrence |>
          dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
          dplyr::select("condition_occurrence_id", person_id = "person_id", event_date = "condition_start_date") |>
          dplyr::collect()
        c_costs <- cost_raw |>
          dplyr::filter(.data$cost_domain_id == "Condition") |>
          dplyr::inner_join(c_df, by = c("cost_event_id" = "condition_occurrence_id")) |>
          dplyr::mutate(cost_domain = "Condition", cost_val = as.numeric(.data[[cost_col]]))
        linked_list <- c(linked_list, list(c_costs))
      }

      # Step 3b: Link Visit-related costs (Inpatient vs Outpatient partition)
      if ("visit_occurrence" %in% names(cdm)) {
        v_df <- cdm$visit_occurrence |>
          dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
          dplyr::select("visit_occurrence_id", person_id = "person_id", "visit_concept_id", event_date = "visit_start_date") |>
          dplyr::collect()
        v_costs <- cost_raw |>
          dplyr::filter(.data$cost_domain_id == "Visit") |>
          dplyr::inner_join(v_df, by = c("cost_event_id" = "visit_occurrence_id")) |>
          dplyr::mutate(
            cost_domain = as.character(ifelse(.data$visit_concept_id %in% c(9201L, 8717L, 581379L, 32037L), "Inpatient", "Outpatient")),
            cost_val = as.numeric(.data[[cost_col]])
          )
        linked_list <- c(linked_list, list(v_costs))
      }

      # Step 3c: Link Pharmacy / Drug-related costs
      if ("drug_exposure" %in% names(cdm)) {
        d_df <- cdm$drug_exposure |>
          dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
          dplyr::select("drug_exposure_id", person_id = "person_id", event_date = "drug_exposure_start_date") |>
          dplyr::collect()
        d_costs <- cost_raw |>
          dplyr::filter(.data$cost_domain_id == "Drug") |>
          dplyr::inner_join(d_df, by = c("cost_event_id" = "drug_exposure_id")) |>
          dplyr::mutate(cost_domain = "Drug", cost_val = as.numeric(.data[[cost_col]]))
        linked_list <- c(linked_list, list(d_costs))
      }

      # Step 3d: Link Procedure / Diagnostic costs
      if ("procedure_occurrence" %in% names(cdm)) {
        p_df <- cdm$procedure_occurrence |>
          dplyr::filter(.data$person_id %in% cohort_sub_ids) |>
          dplyr::select("procedure_occurrence_id", person_id = "person_id", event_date = "procedure_date") |>
          dplyr::collect()
        p_costs <- cost_raw |>
          dplyr::filter(.data$cost_domain_id == "Procedure") |>
          dplyr::inner_join(p_df, by = c("cost_event_id" = "procedure_occurrence_id")) |>
          dplyr::mutate(cost_domain = "Procedure", cost_val = as.numeric(.data[[cost_col]]))
        linked_list <- c(linked_list, list(p_costs))
      }

      # Step 4: Union all linked cost streams
      cost_events <- if (length(linked_list) > 0) {
        dplyr::bind_rows(linked_list) |>
          dplyr::select("person_id", "event_date", "cost_domain", "cost_val")
      } else {
        tibble::tibble(
          person_id = integer(), event_date = as.Date(character()),
          cost_domain = character(), cost_val = numeric()
        )
      }
    }
  }

  res_list <- list(cohort_df)

  # Step 5: Match cost events to temporal observation windows
  for (win_name in names(clean_window)) {
    win_range <- clean_window[[win_name]]
    w_start <- win_range[1]
    w_end <- win_range[2]

    # Filter cost records occurring within patient-specific observation interval
    win_events <- cohort_df |>
      dplyr::inner_join(cost_events, by = c("subject_id" = "person_id")) |>
      dplyr::mutate(
        win_start_dt = as.Date(.data[[indexDate]] + w_start),
        win_end_dt = as.Date(.data[[indexDate]] + w_end),
        cens_dt = if (!is.null(censorDate)) .data[[censorDate]] else as.Date(NA),
        actual_end_dt = if (!is.null(censorDate)) pmin(.data$win_end_dt, .data$cens_dt, na.rm = TRUE) else .data$win_end_dt
      ) |>
      dplyr::filter(
        .data$event_date >= .data$win_start_dt &
          .data$event_date <= .data$actual_end_dt
      )

    # Step 5b: Sum costs by domain and calculate total direct medical costs
    win_summary <- win_events |>
      dplyr::group_by(.data$subject_id) |>
      dplyr::summarise(
        c_inp = sum(ifelse(.data$cost_domain == "Inpatient", .data$cost_val, 0), na.rm = TRUE),
        c_out = sum(ifelse(.data$cost_domain == "Outpatient", .data$cost_val, 0), na.rm = TRUE),
        c_drug = sum(ifelse(.data$cost_domain == "Drug", .data$cost_val, 0), na.rm = TRUE),
        c_proc = sum(ifelse(.data$cost_domain == "Procedure", .data$cost_val, 0), na.rm = TRUE),
        c_tot = sum(.data$cost_val, na.rm = TRUE),
        .groups = "drop"
      )

    c_inp_name <- paste0("cost_inpatient_", win_name)
    c_out_name <- paste0("cost_outpatient_", win_name)
    c_drug_name <- paste0("cost_drug_", win_name)
    c_proc_name <- paste0("cost_procedure_", win_name)
    c_tot_name <- paste0("cost_total_", win_name)

    names(win_summary)[names(win_summary) == "c_inp"] <- c_inp_name
    names(win_summary)[names(win_summary) == "c_out"] <- c_out_name
    names(win_summary)[names(win_summary) == "c_drug"] <- c_drug_name
    names(win_summary)[names(win_summary) == "c_proc"] <- c_proc_name
    names(win_summary)[names(win_summary) == "c_tot"] <- c_tot_name

    res_list <- c(res_list, list(win_summary))
  }

  # Step 6: Join window summaries and zero-fill cohort patients with no incurred costs
  final_df <- res_list[[1]]
  for (k in 2:length(res_list)) {
    final_df <- final_df |>
      dplyr::left_join(res_list[[k]], by = "subject_id")
  }

  metric_cols <- setdiff(colnames(final_df), x_cols)
  for (col in metric_cols) {
    final_df[[col]] <- dplyr::coalesce(final_df[[col]], 0.0)
  }

  # Step 7: Write back to database and preserve cohort metadata
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
