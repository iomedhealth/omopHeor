test_that("addVisits validates input arguments correctly", {
  cdm <- hermesTestCdm()
  cohort <- cdm$target_cohort

  expect_error(addVisits(list()), "Argument 'x' must be a cdm_table or cohort_table")
  expect_error(addVisits(cohort, indexDate = "not_a_col"), "indexDate 'not_a_col' must be a column in x")
  expect_error(addVisits(cohort, window = list(c(10, 0))), "Window interval \\[10, 0\\] is invalid")
  expect_error(addVisits(cohort, settings = "invalid_setting"), "must be a subset of")
  expect_error(addVisits(cohort, specialties = "not_a_list"), "must be a named list")
})

test_that("addVisits executes multi-setting visit enrichment (inpatient, outpatient, emergency)", {
  cdm <- hermesTestCdm()

  cohortEnriched <- cdm$target_cohort |>
    addVisits(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      settings = c("inpatient", "outpatient", "emergency"),
      readmissions = TRUE
    ) |>
    dplyr::collect()

  expect_true(is.data.frame(cohortEnriched))
  expect_equal(nrow(cohortEnriched), nrow(cdm$target_cohort |> dplyr::collect()))

  cols <- colnames(cohortEnriched)
  expectedCols <- c(
    # Inpatient
    "inpatient_admissions_baseline", "inpatient_los_days_baseline",
    "inpatient_admissions_followup", "inpatient_los_days_followup",
    "icu_admissions_followup", "icu_los_days_followup",
    "readmissions_30d_followup",
    # Outpatient
    "gp_visits_baseline", "gp_visits_followup",
    "specialist_visits_baseline", "specialist_visits_followup",
    "other_outpatient_visits_baseline", "other_outpatient_visits_followup",
    # Emergency
    "emergency_visits_baseline", "emergency_visits_followup"
  )
  expect_true(all(expectedCols %in% cols))

  # Patient 1 checks
  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$inpatient_admissions_followup, 2)
  expect_equal(p1$inpatient_los_days_followup, 7)
  expect_equal(p1$icu_admissions_followup, 1)
  expect_equal(p1$emergency_visits_baseline, 1)
  expect_equal(p1$gp_visits_followup, 1)
  expect_equal(p1$specialist_visits_followup, 1)

  # Patient 2 checks
  p2 <- cohortEnriched |> dplyr::filter(.data$subject_id == 2L)
  expect_equal(p2$inpatient_admissions_followup, 1)
  expect_equal(p2$emergency_visits_followup, 1) # Attended by Emergency Medicine specialist provider 3
})

test_that("addVisits filters by specific settings", {
  cdm <- hermesTestCdm()

  # Only outpatient and emergency
  cohortEnriched <- cdm$target_cohort |>
    addVisits(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      settings = c("outpatient", "emergency")
    ) |>
    dplyr::collect()

  cols <- colnames(cohortEnriched)
  expect_true("gp_visits_followup" %in% cols)
  expect_true("emergency_visits_followup" %in% cols)
  expect_false("inpatient_admissions_followup" %in% cols)
  expect_false("icu_admissions_followup" %in% cols)
})

test_that("addVisits unifies granular specialty stratification across settings", {
  cdm <- hermesTestCdm()

  cohortEnriched <- cdm$target_cohort |>
    addVisits(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      settings = c("inpatient", "outpatient", "emergency"),
      stratifySpecialty = TRUE,
      specialties = list(
        general_practice = 38004446L,
        specialist_x = 38004477L,
        emergency_medicine = 38004510L
      )
    ) |>
    dplyr::collect()

  cols <- colnames(cohortEnriched)
  expect_true(all(c(
    "general_practice_inpatient_admissions_followup",
    "general_practice_visits_followup",
    "specialist_x_visits_followup",
    "emergency_medicine_emergency_visits_followup"
  ) %in% cols))

  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$general_practice_inpatient_admissions_followup, 2)
  expect_equal(p1$specialist_x_visits_followup, 1)

  p2 <- cohortEnriched |> dplyr::filter(.data$subject_id == 2L)
  expect_equal(p2$emergency_medicine_emergency_visits_followup, 1)
})

test_that("addVisits supports infinite and NA window bounds with censorDate", {
  cdm <- hermesTestCdm()

  # 1. Whole follow-up window
  cohortEnriched <- cdm$target_cohort |>
    addVisits(
      window = c(0, Inf),
      settings = c("inpatient", "outpatient", "emergency")
    ) |>
    dplyr::collect()

  cols <- colnames(cohortEnriched)
  expect_true("inpatient_admissions_0_to_inf" %in% cols)
  expect_true("emergency_visits_0_to_inf" %in% cols)
  expect_true("gp_visits_0_to_inf" %in% cols)

  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$inpatient_admissions_0_to_inf, 2)
  expect_equal(p1$emergency_visits_0_to_inf, 0)
  expect_equal(p1$gp_visits_0_to_inf, 1)

  # 2. Named window list with NA and censorDate
  cohortCensored <- cdm$target_cohort |>
    addVisits(
      window = list(baseline = c(-365, -1), all_followup = c(0, NA)),
      censorDate = "cohort_end_date"
    ) |>
    dplyr::collect()

  expect_true("inpatient_admissions_all_followup" %in% colnames(cohortCensored))
  expect_true("emergency_visits_all_followup" %in% colnames(cohortCensored))
})

test_that("addVisits propagates countBy and collapseOverlapping across settings", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  person <- tibble::tibble(
    person_id = 1L,
    gender_concept_id = 8507L,
    year_of_birth = 1980L,
    race_concept_id = 0L,
    ethnicity_concept_id = 0L
  )
  observation_period <- tibble::tibble(
    observation_period_id = 1L,
    person_id = 1L,
    observation_period_start_date = as.Date("2000-01-01"),
    observation_period_end_date = as.Date("2025-12-31"),
    period_type_concept_id = 0L
  )
  provider <- tibble::tibble(
    provider_id = 1L,
    specialty_concept_id = 38004446L # GP
  )
  # Person 1 has 2 GP visits on 2010-03-01, 2 ED visits on 2010-04-01
  visit_occurrence <- tibble::tibble(
    visit_occurrence_id = 1:4,
    person_id = rep(1L, 4),
    visit_concept_id = c(9202L, 9202L, 9203L, 9203L),
    visit_start_date = as.Date(c(
      "2010-03-01", "2010-03-01",
      "2010-04-01", "2010-04-01"
    )),
    visit_end_date = as.Date(c(
      "2010-03-01", "2010-03-01",
      "2010-04-01", "2010-04-01"
    )),
    visit_type_concept_id = rep(44818517L, 4),
    provider_id = rep(1L, 4)
  )

  DBI::dbWriteTable(con, "person", person)
  DBI::dbWriteTable(con, "observation_period", observation_period)
  DBI::dbWriteTable(con, "provider", provider)
  DBI::dbWriteTable(con, "visit_occurrence", visit_occurrence)

  cdm <- CDMConnector::cdmFromCon(con, cdmSchema = "main", writeSchema = "main")

  target <- tibble::tibble(
    cohort_definition_id = 1L,
    subject_id = 1L,
    cohort_start_date = as.Date("2010-01-01"),
    cohort_end_date = as.Date("2010-12-31")
  )
  cdm <- omopgenerics::insertTable(cdm, name = "target_cohort", table = target)
  cdm$target_cohort <- omopgenerics::newCohortTable(cdm$target_cohort)

  # Default: countBy = "days"
  res_days <- cdm$target_cohort |>
    addVisits(
      window = list(followup = c(0, 365)),
      settings = c("outpatient", "emergency")
    ) |>
    dplyr::collect()

  expect_equal(res_days$gp_visits_followup, 1)
  expect_equal(res_days$emergency_visits_followup, 1)

  # countBy = "records"
  res_records <- cdm$target_cohort |>
    addVisits(
      window = list(followup = c(0, 365)),
      settings = c("outpatient", "emergency"),
      countBy = "records"
    ) |>
    dplyr::collect()

  expect_equal(res_records$gp_visits_followup, 2)
  expect_equal(res_records$emergency_visits_followup, 2)
})

test_that("addVisits propagates gapDays to inpatient settings", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  person <- tibble::tibble(
    person_id = 1L,
    gender_concept_id = 8507L,
    year_of_birth = 1980L,
    race_concept_id = 0L,
    ethnicity_concept_id = 0L
  )
  observation_period <- tibble::tibble(
    observation_period_id = 1L,
    person_id = 1L,
    observation_period_start_date = as.Date("2000-01-01"),
    observation_period_end_date = as.Date("2025-12-31"),
    period_type_concept_id = 0L
  )
  provider <- tibble::tibble(
    provider_id = 1L,
    specialty_concept_id = 38004446L
  )
  # Person 1 has 2 contiguous inpatient stays separated by 1 day:
  # Stay 1: 2010-02-01 to 2010-02-05
  # Stay 2: 2010-02-06 to 2010-02-10
  visit_occurrence <- tibble::tibble(
    visit_occurrence_id = 1:2,
    person_id = c(1L, 1L),
    visit_concept_id = c(9201L, 9201L),
    visit_start_date = as.Date(c("2010-02-01", "2010-02-06")),
    visit_end_date = as.Date(c("2010-02-05", "2010-02-10")),
    visit_type_concept_id = c(44818517L, 44818517L),
    provider_id = c(1L, 1L)
  )

  DBI::dbWriteTable(con, "person", person)
  DBI::dbWriteTable(con, "observation_period", observation_period)
  DBI::dbWriteTable(con, "provider", provider)
  DBI::dbWriteTable(con, "visit_occurrence", visit_occurrence)

  cdm <- CDMConnector::cdmFromCon(con, cdmSchema = "main", writeSchema = "main")

  target <- tibble::tibble(
    cohort_definition_id = 1L,
    subject_id = 1L,
    cohort_start_date = as.Date("2010-01-01"),
    cohort_end_date = as.Date("2010-12-31")
  )
  cdm <- omopgenerics::insertTable(cdm, name = "target_cohort", table = target)
  cdm$target_cohort <- omopgenerics::newCohortTable(cdm$target_cohort)

  # Default: gapDays = 1L collapses them into 1 admission and 9 LOS days
  res_gap1 <- cdm$target_cohort |>
    addVisits(
      window = list(followup = c(0, 365)),
      settings = "inpatient",
      gapDays = 1L
    ) |>
    dplyr::collect()

  expect_equal(res_gap1$inpatient_admissions_followup, 1)
  expect_equal(res_gap1$inpatient_los_days_followup, 9)

  # gapDays = 0L: does not collapse 1-day separated stays -> 2 admissions, 8 LOS days
  res_gap0 <- cdm$target_cohort |>
    addVisits(
      window = list(followup = c(0, 365)),
      settings = "inpatient",
      gapDays = 0L
    ) |>
    dplyr::collect()

  expect_equal(res_gap0$inpatient_admissions_followup, 2)
  expect_equal(res_gap0$inpatient_los_days_followup, 8)
})

