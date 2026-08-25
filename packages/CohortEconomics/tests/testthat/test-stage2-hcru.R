test_that("baseline demographics and comorbidity generation", {
  study <- hermes_test_study()
  hcru <- summarise_baseline(study)

  expect_true(inherits(hcru, "hermes_hcru"))
  expect_true(!is.null(hcru$baseline_summary))
  expect_true(inherits(hcru$baseline_summary, "summarised_result"))
})

test_that("T005 [US1] extract_hcru validates arguments correctly", {
  study <- hermes_test_study()
  expect_error(extract_hcru(list()), "Argument 'study' must be an omopheor_study")
  expect_error(extract_hcru(study, baseline_window = c(0, -100)), "Argument 'baseline_window' must be a numeric vector of length 2 with start <= end")
  expect_error(extract_hcru(study, followup_window = c(100, 50)), "Argument 'followup_window' must be a numeric vector of length 2 with start <= end")
  expect_error(extract_hcru(study, cost_field = 123), "Argument 'cost_field' must be a single string")
})

test_that("T005 [US1] extract_hcru filters to cohort members and tags temporal windows and health states", {
  study <- hermes_test_study()

  hcru_out <- extract_hcru(
    study = study,
    baseline_window = c(-365, -1),
    followup_window = c(0, 365),
    cost_field = "total_paid"
  )

  expect_true(inherits(hcru_out, "hermes_hcru"))
  expect_true(inherits(hcru_out, "hermes_study"))
  expect_true(!is.null(hcru_out$costs))
  expect_true(is.data.frame(hcru_out$costs))
  expect_true(all(c("subject_id", "total_paid", "total_charge", "health_state", "cost_domain") %in% colnames(hcru_out$costs)))

  # All extracted costs belong to cohort subjects (1, 2, 3)
  expect_true(all(hcru_out$costs$subject_id %in% c(1L, 2L, 3L)))

  # Patient 1 has outcome on 2010-06-01. Events on or after 2010-06-01 should be tagged State_Outcome
  post_outcome_costs <- hcru_out$costs |> dplyr::filter(subject_id == 1L, health_state == "State_Outcome")
  expect_gte(nrow(post_outcome_costs), 1)

  # Check patient_summary presence and structure
  expect_true(!is.null(hcru_out$hcru$patient_summary))
  expect_true(is.data.frame(hcru_out$hcru$patient_summary))
  expect_true(all(c("subject_id", "window", "total_cost") %in% colnames(hcru_out$hcru$patient_summary)))

  # Scaffolding: all 3 cohort patients must exist across both baseline and followup windows (3 * 2 = 6 rows)
  expect_equal(nrow(hcru_out$hcru$patient_summary), 6)
  expect_setequal(unique(hcru_out$hcru$patient_summary$subject_id), c(1L, 2L, 3L))
})

test_that("T005 [US1] extract_hcru handles missing cost table gracefully", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  person <- tibble::tibble(person_id = 1L, gender_concept_id = 0L, year_of_birth = 1980L, race_concept_id = 0L, ethnicity_concept_id = 0L)
  observation_period <- tibble::tibble(observation_period_id = 1L, person_id = 1L, observation_period_start_date = as.Date("2000-01-01"), observation_period_end_date = as.Date("2020-12-31"), period_type_concept_id = 0L)
  target <- tibble::tibble(cohort_definition_id = 1L, subject_id = 1L, cohort_start_date = as.Date("2010-01-01"), cohort_end_date = as.Date("2010-12-31"))

  DBI::dbWriteTable(con, "person", person)
  DBI::dbWriteTable(con, "observation_period", observation_period)

  cdm <- CDMConnector::cdmFromCon(con, cdmSchema = "main", writeSchema = "main")
  cdm <- omopgenerics::insertTable(cdm, name = "target_cohort", table = target)
  cdm$target_cohort <- omopgenerics::newCohortTable(cdm$target_cohort)
  cdm <- omopgenerics::insertTable(cdm, name = "comparator_cohort", table = target)
  cdm$comparator_cohort <- omopgenerics::newCohortTable(cdm$comparator_cohort)
  cdm <- omopgenerics::insertTable(cdm, name = "outcome_cohort", table = target)
  cdm$outcome_cohort <- omopgenerics::newCohortTable(cdm$outcome_cohort)

  study <- init(cdm, "target_cohort", "comparator_cohort", "outcome_cohort")

  expect_warning(
    hcru_out <- extract_hcru(study),
    "Missing 'cost' table in CDM. Skipping cost extraction."
  )

  expect_true(is.data.frame(hcru_out$costs))
  expect_equal(nrow(hcru_out$costs), 0)
  expect_true(all(c("subject_id", "total_paid", "total_charge", "health_state", "cost_domain") %in% colnames(hcru_out$costs)))
})

test_that("T010 [US2] extract_hcru extracts inpatient LOS, ICU, readmissions, and outpatient specialty", {
  study <- hermes_test_study()

  hcru_out <- extract_hcru(
    study = study,
    calculate_readmissions = TRUE
  )

  # Check inpatient table
  expect_true(!is.null(hcru_out$hcru$inpatient))
  expect_true(is.data.frame(hcru_out$hcru$inpatient))
  expect_true(all(c("subject_id", "window", "inpatient_admissions", "inpatient_los_days", "icu_admissions", "icu_los_days", "readmissions_30d", "readmissions_90d") %in% colnames(hcru_out$hcru$inpatient)))

  # Patient 1 has 2 inpatient visits (LOS 4 + 3 = 7 days), 1 ICU visit (LOS 2 days), and 1 30d readmission in followup
  p1_followup_inp <- hcru_out$hcru$inpatient |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_followup_inp$inpatient_admissions, 2)
  expect_equal(p1_followup_inp$inpatient_los_days, 7)
  expect_equal(p1_followup_inp$icu_admissions, 1)
  expect_equal(p1_followup_inp$icu_los_days, 2)
  expect_equal(p1_followup_inp$readmissions_30d, 1)

  # Patient 3 has zero inpatient visits
  p3_inp <- hcru_out$hcru$inpatient |> dplyr::filter(subject_id == 3L)
  expect_equal(sum(p3_inp$inpatient_admissions), 0)
  expect_equal(sum(p3_inp$inpatient_los_days), 0)

  # Check outpatient table
  expect_true(!is.null(hcru_out$hcru$outpatient))
  expect_true(is.data.frame(hcru_out$hcru$outpatient))
  expect_true(all(c("subject_id", "window", "emergency_visits", "gp_visits", "specialist_visits", "other_outpatient_visits") %in% colnames(hcru_out$hcru$outpatient)))

  # Patient 1 in baseline has 1 ED visit (2009-10-01)
  p1_base_out <- hcru_out$hcru$outpatient |> dplyr::filter(subject_id == 1L, window == "baseline")
  expect_equal(p1_base_out$emergency_visits, 1)
  expect_equal(p1_base_out$gp_visits, 0)

  # Patient 1 in followup has 1 GP visit and 1 Specialist visit
  p1_foll_out <- hcru_out$hcru$outpatient |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_foll_out$gp_visits, 1)
  expect_equal(p1_foll_out$specialist_visits, 1)
})

test_that("T014 [US3] extract_hcru extracts pharmacotherapy, diagnostics, and post-acute stays", {
  study <- hermes_test_study()

  hcru_out <- extract_hcru(
    study = study,
    pharmacotherapy = TRUE,
    diagnostics = TRUE,
    post_acute = TRUE,
    persistence = TRUE
  )

  # Check pharmacotherapy table
  expect_true(!is.null(hcru_out$hcru$pharmacotherapy))
  expect_true(is.data.frame(hcru_out$hcru$pharmacotherapy))
  expect_true(all(c("subject_id", "window", "prescription_fills", "total_days_supply", "pdc") %in% colnames(hcru_out$hcru$pharmacotherapy)))

  # Patient 1 has 1 drug in baseline (2009-08-01, 30 days) and 2 drugs in followup (2010-01-15, 30 days + 2010-03-01, 1 day)
  p1_pharma_base <- hcru_out$hcru$pharmacotherapy |> dplyr::filter(subject_id == 1L, window == "baseline")
  expect_equal(p1_pharma_base$prescription_fills, 1)
  expect_equal(p1_pharma_base$total_days_supply, 30)

  p1_pharma_foll <- hcru_out$hcru$pharmacotherapy |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_pharma_foll$prescription_fills, 2)
  expect_equal(p1_pharma_foll$total_days_supply, 31)
  expect_true(!is.na(p1_pharma_foll$pdc))

  # Check procedures & diagnostics table
  expect_true(!is.null(hcru_out$hcru$procedures_diagnostics))
  expect_true(is.data.frame(hcru_out$hcru$procedures_diagnostics))
  expect_true(all(c("subject_id", "window", "procedure_count", "measurement_count") %in% colnames(hcru_out$hcru$procedures_diagnostics)))

  p1_diag_base <- hcru_out$hcru$procedures_diagnostics |> dplyr::filter(subject_id == 1L, window == "baseline")
  expect_equal(p1_diag_base$procedure_count, 1)
  expect_equal(p1_diag_base$measurement_count, 1)

  p1_diag_foll <- hcru_out$hcru$procedures_diagnostics |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_diag_foll$procedure_count, 1)
  expect_equal(p1_diag_foll$measurement_count, 1)

  # Check post-acute table
  expect_true(!is.null(hcru_out$hcru$post_acute))
  expect_true(is.data.frame(hcru_out$hcru$post_acute))
  expect_true(all(c("subject_id", "window", "post_acute_stays", "post_acute_los_days") %in% colnames(hcru_out$hcru$post_acute)))

  # Patient 1 has 1 SNF visit in followup (LOS = 9 days)
  p1_post_foll <- hcru_out$hcru$post_acute |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_post_foll$post_acute_stays, 1)
  expect_equal(p1_post_foll$post_acute_los_days, 9)

  # Patient 3 has zero post-acute stays
  p3_post <- hcru_out$hcru$post_acute |> dplyr::filter(subject_id == 3L)
  expect_equal(sum(p3_post$post_acute_stays), 0)
  expect_equal(sum(p3_post$post_acute_los_days), 0)

  # Check patient_summary combined columns
  summary_cols <- colnames(hcru_out$hcru$patient_summary)
  expect_true(all(c(
    "subject_id", "window",
    "inpatient_admissions", "inpatient_los_days", "icu_admissions", "icu_los_days",
    "emergency_visits", "gp_visits", "specialist_visits",
    "prescription_fills", "total_days_supply",
    "procedure_count", "measurement_count",
    "post_acute_stays", "post_acute_los_days",
    "total_cost"
  ) %in% summary_cols))
})

test_that("extract_hcru deduplicates same-day visits with count_by = 'days' vs 'records'", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  person <- tibble::tibble(
    person_id = c(1L, 2L),
    gender_concept_id = c(8507L, 8532L),
    year_of_birth = c(1980L, 1975L),
    race_concept_id = c(0L, 0L),
    ethnicity_concept_id = c(0L, 0L)
  )
  observation_period <- tibble::tibble(
    observation_period_id = c(1L, 2L),
    person_id = c(1L, 2L),
    observation_period_start_date = as.Date(c("2000-01-01", "2000-01-01")),
    observation_period_end_date = as.Date(c("2025-12-31", "2025-12-31")),
    period_type_concept_id = c(0L, 0L)
  )
  provider <- tibble::tibble(
    provider_id = 1L,
    specialty_concept_id = 38004446L # GP
  )
  # Person 1 has 3 GP visits on 2010-03-01
  visit_occurrence <- tibble::tibble(
    visit_occurrence_id = 1:3,
    person_id = rep(1L, 3),
    visit_concept_id = rep(9202L, 3),
    visit_start_date = rep(as.Date("2010-03-01"), 3),
    visit_end_date = rep(as.Date("2010-03-01"), 3),
    visit_type_concept_id = rep(44818517L, 3),
    provider_id = rep(1L, 3)
  )
  cost <- tibble::tibble(
    cost_id = 1:3,
    cost_event_id = 1:3,
    cost_domain_id = rep("Visit", 3),
    cost_type_concept_id = rep(32814L, 3),
    total_paid = c(100.0, 50.0, 75.0), # Total cost: 225.0
    total_charge = c(120.0, 60.0, 90.0)
  )

  DBI::dbWriteTable(con, "person", person)
  DBI::dbWriteTable(con, "observation_period", observation_period)
  DBI::dbWriteTable(con, "provider", provider)
  DBI::dbWriteTable(con, "visit_occurrence", visit_occurrence)
  DBI::dbWriteTable(con, "cost", cost)

  cdm <- CDMConnector::cdmFromCon(con, cdmSchema = "main", writeSchema = "main")

  target <- tibble::tibble(
    cohort_definition_id = 1L,
    subject_id = 1L,
    cohort_start_date = as.Date("2010-01-01"),
    cohort_end_date = as.Date("2010-12-31")
  )
  comparator <- tibble::tibble(
    cohort_definition_id = 1L,
    subject_id = 2L,
    cohort_start_date = as.Date("2010-01-01"),
    cohort_end_date = as.Date("2010-12-31")
  )
  cdm <- omopgenerics::insertTable(cdm, name = "target_cohort", table = target)
  cdm$target_cohort <- omopgenerics::newCohortTable(cdm$target_cohort)
  cdm <- omopgenerics::insertTable(cdm, name = "comparator_cohort", table = comparator)
  cdm$comparator_cohort <- omopgenerics::newCohortTable(cdm$comparator_cohort)
  cdm <- omopgenerics::insertTable(cdm, name = "outcome_cohort", table = target)
  cdm$outcome_cohort <- omopgenerics::newCohortTable(cdm$outcome_cohort)

  study <- init(cdm, "target_cohort", "comparator_cohort", "outcome_cohort")

  # 1. Default: count_by = "days"
  hcru_days <- extract_hcru(study, count_by = "days")
  p1_foll_days <- hcru_days$hcru$patient_summary |> dplyr::filter(subject_id == 1L, window == "followup")

  expect_equal(p1_foll_days$gp_visits, 1) # 1 unique visit day
  expect_equal(p1_foll_days$total_cost, 225.0) # All 3 cost records summed exhaustively

  # 2. count_by = "records"
  hcru_records <- extract_hcru(study, count_by = "records")
  p1_foll_rec <- hcru_records$hcru$patient_summary |> dplyr::filter(subject_id == 1L, window == "followup")

  expect_equal(p1_foll_rec$gp_visits, 3) # 3 raw database records
  expect_equal(p1_foll_rec$total_cost, 225.0)
})

test_that("extract_hcru collapses inpatient episodes using configurable gap_days", {
  study <- hermes_test_study()

  # Default: gap_days = 1L. Patient 1 visits on Feb 1-5 and Feb 20-23 (gap = 15 days) remain 2 admissions
  hcru_gap1 <- extract_hcru(study, gap_days = 1L, calculate_readmissions = TRUE)
  p1_inp_gap1 <- hcru_gap1$hcru$inpatient |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_inp_gap1$inpatient_admissions, 2)
  expect_equal(p1_inp_gap1$inpatient_los_days, 7)
  expect_equal(p1_inp_gap1$readmissions_30d, 1)

  # With gap_days = 20L: Patient 1 visits (gap = 15 days <= 20) are merged into 1 continuous episode (Feb 1 to Feb 23: 22 days)
  hcru_gap20 <- extract_hcru(study, gap_days = 20L, calculate_readmissions = TRUE)
  p1_inp_gap20 <- hcru_gap20$hcru$inpatient |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_inp_gap20$inpatient_admissions, 1)
  expect_equal(p1_inp_gap20$inpatient_los_days, 22)
  expect_equal(p1_inp_gap20$readmissions_30d, 0)

  # camelCase alias gapDays works identically in extractHcru
  hcru_alias <- extractHcru(study, gapDays = 20L, calculateReadmissions = TRUE)
  p1_inp_alias <- hcru_alias$hcru$inpatient |> dplyr::filter(subject_id == 1L, window == "followup")
  expect_equal(p1_inp_alias$inpatient_admissions, 1)
  expect_equal(p1_inp_alias$inpatient_los_days, 22)

  # Validation tests for invalid gap_days
  expect_error(extract_hcru(study, gap_days = -1L), "Argument 'gap_days' must be a single non-negative integer")
  expect_error(extract_hcru(study, gap_days = "invalid"), "Argument 'gap_days' must be a single non-negative integer")
  expect_error(extract_hcru(study, gap_days = 2.5), "Argument 'gap_days' must be a single non-negative integer")
})


