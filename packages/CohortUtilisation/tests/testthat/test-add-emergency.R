test_that("addEmergencyCare validates input arguments correctly", {
  cdm <- hermesTestCdm()
  cohort <- cdm$target_cohort

  expect_error(addEmergencyCare(list()), "Argument 'x' must be a cdm_table or cohort_table")
  expect_error(addEmergencyCare(cohort, indexDate = "not_a_col"), "indexDate 'not_a_col' must be a column in x")
  expect_error(addEmergencyCare(cohort, window = list(c(10, 0))), "Window interval \\[10, 0\\] is invalid")
  expect_error(addEmergencyCare(cohort, specialties = "not_a_list"), "must be a named list")
})

test_that("addEmergencyCare detects emergency encounters via visit concept IDs and provider specialties", {
  cdm <- hermesTestCdm()

  # Person 1 has:
  # - Visit 4 (concept 9203L, provider 1) in baseline (2009-10-01)
  # Person 2 has:
  # - Visit 9 (concept 9202L, provider 3 with specialty 38004510L Emergency Medicine) in followup (2010-06-01)

  cohortEnriched <- cdm$target_cohort |>
    addEmergencyCare(
      window = list(baseline = c(-365, -1), followup = c(0, 365))
    ) |>
    dplyr::collect()

  expect_true(is.data.frame(cohortEnriched))
  expect_equal(nrow(cohortEnriched), nrow(cdm$target_cohort |> dplyr::collect()))

  cols <- colnames(cohortEnriched)
  expect_true(all(c("emergency_visits_baseline", "emergency_visits_followup") %in% cols))

  # Patient 1 has 1 ER visit in baseline, 0 in followup
  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$emergency_visits_baseline, 1)
  expect_equal(p1$emergency_visits_followup, 0)

  # Patient 2 has 0 in baseline, 1 in followup (detected via provider specialty 38004510L!)
  p2 <- cohortEnriched |> dplyr::filter(.data$subject_id == 2L)
  expect_equal(p2$emergency_visits_baseline, 0)
  expect_equal(p2$emergency_visits_followup, 1)
})

test_that("addEmergencyCare stratifies by granular specialty", {
  cdm <- hermesTestCdm()

  cohortEnriched <- cdm$target_cohort |>
    addEmergencyCare(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      stratifySpecialty = TRUE,
      specialties = list(
        general_practice = 38004446L,
        emergency_medicine = 38004510L
      )
    ) |>
    dplyr::collect()

  cols <- colnames(cohortEnriched)
  expect_true(all(c(
    "emergency_visits_baseline", "emergency_visits_followup",
    "general_practice_emergency_visits_baseline", "general_practice_emergency_visits_followup",
    "emergency_medicine_emergency_visits_baseline", "emergency_medicine_emergency_visits_followup"
  ) %in% cols))

  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$general_practice_emergency_visits_baseline, 1)
  expect_equal(p1$emergency_medicine_emergency_visits_baseline, 0)

  p2 <- cohortEnriched |> dplyr::filter(.data$subject_id == 2L)
  expect_equal(p2$general_practice_emergency_visits_followup, 0)
  expect_equal(p2$emergency_medicine_emergency_visits_followup, 1)
})

test_that("addEmergency and addEmergencyVisits aliases work identically", {
  cdm <- hermesTestCdm()

  res1 <- cdm$target_cohort |>
    addEmergencyCare(window = list(followup = c(0, 365))) |>
    dplyr::collect()

  res2 <- cdm$target_cohort |>
    addEmergency(window = list(followup = c(0, 365))) |>
    dplyr::collect()

  res3 <- cdm$target_cohort |>
    addEmergencyVisits(window = list(followup = c(0, 365))) |>
    dplyr::collect()

  expect_equal(res1, res2)
  expect_equal(res1, res3)
})

test_that("addEmergencyCare supports infinite and NA windows", {
  cdm <- hermesTestCdm()

  # 1. Unnamed c(0, Inf) -> emergency_visits_0_to_inf
  resInf <- cdm$target_cohort |>
    addEmergencyCare(window = c(0, Inf)) |>
    dplyr::collect()

  expect_true("emergency_visits_0_to_inf" %in% colnames(resInf))
  p2 <- resInf |> dplyr::filter(.data$subject_id == 2L)
  expect_equal(p2$emergency_visits_0_to_inf, 1)

  # 2. NA normalization: c(0, NA) -> identical to c(0, Inf)
  resNa <- cdm$target_cohort |>
    addEmergencyCare(window = list(c(0, NA))) |>
    dplyr::collect()

  expect_equal(resInf, resNa)
})

test_that("addEmergencyCare deduplicates same-day emergency visits with countBy = 'days' vs 'records'", {
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
    provider_id = c(1L, 2L),
    specialty_concept_id = c(38004510L, 38004510L)
  )
  # Person 1 has 3 emergency visit records on the same day: 2010-04-10, and 1 on 2010-08-20
  visit_occurrence <- tibble::tibble(
    visit_occurrence_id = 1:4,
    person_id = rep(1L, 4),
    visit_concept_id = rep(9203L, 4),
    visit_start_date = as.Date(c(
      "2010-04-10", "2010-04-10", "2010-04-10", # 3 same-day ED records
      "2010-08-20"                             # 1 distinct ED record
    )),
    visit_end_date = as.Date(c(
      "2010-04-10", "2010-04-10", "2010-04-10",
      "2010-08-20"
    )),
    visit_type_concept_id = rep(44818517L, 4),
    provider_id = c(1L, 2L, 1L, 1L)
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

  # 1. Default: countBy = "days"
  res_days <- cdm$target_cohort |>
    addEmergencyCare(window = list(followup = c(0, 365))) |>
    dplyr::collect()

  # Should deduplicate 3 same-day records to 1 + 1 on 2010-08-20 = 2
  expect_equal(res_days$emergency_visits_followup, 2)

  # 2. countBy = "records"
  res_records <- cdm$target_cohort |>
    addEmergencyCare(window = list(followup = c(0, 365)), countBy = "records") |>
    dplyr::collect()

  expect_equal(res_records$emergency_visits_followup, 4)

  # 3. collapseOverlapping = FALSE
  res_nocollapse <- cdm$target_cohort |>
    addEmergencyCare(window = list(followup = c(0, 365)), collapseOverlapping = FALSE) |>
    dplyr::collect()

  expect_equal(res_nocollapse$emergency_visits_followup, 4)

  # 4. Error on invalid countBy
  expect_error(
    addEmergencyCare(cdm$target_cohort, countBy = "wrong"),
    "Argument 'countBy' must be either 'days' or 'records'"
  )
})

