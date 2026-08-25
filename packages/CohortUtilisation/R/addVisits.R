#' Add Multi-Setting Visit Utilization Metrics to a Cohort
#'
#' @description
#' Enriches an OMOP cohort table with Healthcare Resource Utilization (HCRU) metrics
#' across Inpatient, Outpatient, and Emergency care settings in a single unified execution,
#' with full support for provider specialty stratification across domains.
#'
#' @param x A cohort table or cdm_table.
#' @param indexDate Date variable in `x` anchoring the observation window. Default: `"cohort_start_date"`.
#' @param censorDate Optional date variable in `x` to censor observation.
#' @param window A named or unnamed list of 2-element numeric vectors. Default: `list(c(-365, -1), c(0, 365))`.
#' @param settings Character vector of care settings to extract. Allowed values: `"inpatient"`, `"outpatient"`, `"emergency"`. Default: `c("inpatient", "outpatient", "emergency")`.
#' @param stratifySpecialty Logical; whether to partition visits by specialty. Default: `TRUE`.
#' @param gpSpecialtyConceptIds OMOP provider specialty concept IDs for General Practice. Default: `c(38004446L)`.
#' @param icuSpecialtyConceptIds OMOP provider specialty concept IDs for ICU stays. Default: `c(38004500L)`.
#' @param emergencySpecialtyConceptIds OMOP provider specialty concept IDs for Emergency Medicine. Default: `c(38004510L)`.
#' @param specialties Optional named list of integer vectors of OMOP specialty concept IDs for granular specialty breakdown. Default: `NULL`.
#' @param inpatientVisitConceptIds OMOP visit concept IDs for inpatient stays. Default: `c(9201L, 8717L, 581379L)`.
#' @param outpatientVisitConceptIds OMOP visit concept IDs for outpatient care. Default: `c(9202L, 581477L)`.
#' @param emergencyVisitConceptIds OMOP visit concept IDs for emergency care. Default: `c(9203L, 262L, 581478L)`.
#' @param icuConceptIds OMOP visit concept IDs for ICU stays. Default: `32037L`.
#' @param readmissions Logical; whether to compute 30-day and 90-day readmissions for inpatient stays. Default: `FALSE`.
#' @param gapDays Integer scalar >= 0. Maximum gap in days between contiguous stays to collapse into a single episode. Default: `1L`.
#' @param collapseGap Optional alias for `gapDays`. Default: `NULL`.
#' @param countBy Character scalar specifying count granularity: `"days"` to count distinct visit start dates, or `"records"` to count raw database rows. Default: `"days"`.
#' @param collapseOverlapping Logical; whether to collapse same-day and overlapping visits. If `FALSE`, forces `countBy = "records"`. Default: `TRUE`.
#' @param name Name of the new table in the write schema. If NULL, a temporary table is returned.
#'
#' @return The cohort table `x` with added multi-setting visit metric columns.
#' @export
addVisits <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  settings = c("inpatient", "outpatient", "emergency"),
  stratifySpecialty = TRUE,
  gpSpecialtyConceptIds = c(38004446L),
  icuSpecialtyConceptIds = c(38004500L),
  emergencySpecialtyConceptIds = c(38004510L),
  specialties = NULL,
  inpatientVisitConceptIds = c(9201L, 8717L, 581379L),
  outpatientVisitConceptIds = c(9202L, 581477L),
  emergencyVisitConceptIds = c(9203L, 262L, 581478L),
  icuConceptIds = 32037L,
  readmissions = FALSE,
  gapDays = 1L,
  collapseGap = NULL,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  name = NULL
) {
  # ponytail: modular composition of addInpatients, addOutpatientVisits, and addEmergencyCare
  if (!inherits(x, "cdm_table") && !inherits(x, "cohort_table") && !inherits(x, "tbl_dbi")) {
    cli::cli_abort("Argument 'x' must be a cdm_table or cohort_table.")
  }

  valid_settings <- c("inpatient", "outpatient", "emergency")
  if (!is.character(settings) || length(settings) == 0 || !all(settings %in% valid_settings)) {
    cli::cli_abort("Argument 'settings' must be a subset of c('inpatient', 'outpatient', 'emergency').")
  }

  indexDate <- validateIndexDate(indexDate, x)
  censorDate <- validateCensorDate(censorDate, x)
  clean_window <- validateWindow(window)
  name <- validateName(name)
  specialties <- validateSpecialties(specialties)
  gapDays <- validateGapDays(gapDays = gapDays, collapseGap = collapseGap)
  countBy <- validateCountBy(countBy = countBy, collapseOverlapping = collapseOverlapping)

  res <- x

  # 1. Inpatient Setting
  if ("inpatient" %in% settings) {
    res <- addInpatients(
      x = res,
      indexDate = indexDate,
      censorDate = censorDate,
      window = clean_window,
      visitConceptIds = inpatientVisitConceptIds,
      icuConceptIds = icuConceptIds,
      icuSpecialtyConceptIds = icuSpecialtyConceptIds,
      stratifySpecialty = stratifySpecialty,
      specialties = specialties,
      readmissions = readmissions,
      gapDays = gapDays,
      countBy = countBy,
      collapseOverlapping = collapseOverlapping
    )
  }

  # 2. Outpatient Setting
  if ("outpatient" %in% settings) {
    include_em <- !("emergency" %in% settings)
    res <- addOutpatientVisits(
      x = res,
      indexDate = indexDate,
      censorDate = censorDate,
      window = clean_window,
      stratifySpecialty = stratifySpecialty,
      gpSpecialtyConceptIds = gpSpecialtyConceptIds,
      specialties = specialties,
      includeEmergency = include_em,
      countBy = countBy,
      collapseOverlapping = collapseOverlapping
    )
  }

  # 3. Emergency Setting
  if ("emergency" %in% settings) {
    res <- addEmergencyCare(
      x = res,
      indexDate = indexDate,
      censorDate = censorDate,
      window = clean_window,
      emergencyVisitConceptIds = emergencyVisitConceptIds,
      emergencySpecialtyConceptIds = emergencySpecialtyConceptIds,
      stratifySpecialty = stratifySpecialty,
      specialties = specialties,
      countBy = countBy,
      collapseOverlapping = collapseOverlapping
    )
  }

  if (!is.null(name)) {
    cdm <- omopgenerics::cdmReference(res)
    cdm <- omopgenerics::insertTable(cdm = cdm, name = name, table = res |> dplyr::collect(), overwrite = TRUE)
    if (inherits(x, "cohort_table")) {
      cdm[[name]] <- omopgenerics::newCohortTable(
        cdm[[name]],
        cohortSetRef = attr(x, "cohort_set"),
        cohortAttritionRef = attr(x, "cohort_attrition"),
        .softValidation = TRUE
      )
    }
    return(cdm[[name]])
  }

  res
}
