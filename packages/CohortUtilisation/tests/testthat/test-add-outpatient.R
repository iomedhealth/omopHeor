test_that("addOutpatientVisits validates input arguments", {
  cdm <- hermes_test_cdm()
  cohort <- cdm$target_cohort

  expect_error(addOutpatientVisits(list()), "Argument 'x' must be a cdm_table or cohort_table")
  expect_error(addOutpatientVisits(cohort, indexDate = "bad_col"), "indexDate 'bad_col' must be a column in x")
  expect_error(addOutpatientVisits(cohort, specialties = "not_a_list"), "must be a named list")
  expect_error(addOutpatientVisits(cohort, specialties = list(123)), "must be a named list")
})

test_that("addOutpatientVisits stratifies GP, Specialist, and Emergency visits", {
  cdm <- hermes_test_cdm()

  cohort_enriched <- cdm$target_cohort |>
    addOutpatientVisits(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      stratifySpecialty = TRUE
    ) |>
    dplyr::collect()

  expect_true(is.data.frame(cohort_enriched))
  expect_equal(nrow(cohort_enriched), nrow(cdm$target_cohort |> dplyr::collect()))

  cols <- colnames(cohort_enriched)
  expect_true(all(c(
    "emergency_visits_baseline", "gp_visits_baseline", "specialist_visits_baseline",
    "emergency_visits_followup", "gp_visits_followup", "specialist_visits_followup"
  ) %in% cols))

  # Patient 1 has 1 ED visit in baseline, 1 GP and 1 Specialist in followup
  p1 <- cohort_enriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$emergency_visits_baseline, 1)
  expect_equal(p1$gp_visits_baseline, 0)
  expect_equal(p1$gp_visits_followup, 1)
  expect_equal(p1$specialist_visits_followup, 1)
})

test_that("addOutpatientVisits computes granular specialty breakdowns", {
  cdm <- hermes_test_cdm()

  # Provider 2 in helper-eunomia has specialty 38004477L
  cohort_enriched <- cdm$target_cohort |>
    addOutpatientVisits(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      stratifySpecialty = TRUE,
      specialties = list(
        oncology = c(38004507L, 38004006L),
        hematology = 38004501L,
        specialty_x = 38004477L
      )
    ) |>
    dplyr::collect()

  cols <- colnames(cohort_enriched)
  expect_true(all(c(
    "oncology_visits_baseline", "oncology_visits_followup",
    "hematology_visits_baseline", "hematology_visits_followup",
    "specialty_x_visits_baseline", "specialty_x_visits_followup"
  ) %in% cols))

  p1 <- cohort_enriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$oncology_visits_followup, 0)
  expect_equal(p1$hematology_visits_followup, 0)
  expect_equal(p1$specialty_x_visits_followup, 1) # Visit 6 with provider 2 (specialty 38004477L)

  p2 <- cohort_enriched |> dplyr::filter(.data$subject_id == 2L)
  expect_equal(p2$oncology_visits_followup, 0)
  expect_equal(p2$specialty_x_visits_followup, 0)
})

test_that("addOutpatientVisits supports infinite and NA window bounds", {
  cdm <- hermesTestCdm()

  resInf <- cdm$target_cohort |>
    addOutpatientVisits(window = c(0, Inf)) |>
    dplyr::collect()

  expect_true("gp_visits_0_to_inf" %in% colnames(resInf))
  expect_true("specialist_visits_0_to_inf" %in% colnames(resInf))
  p1 <- resInf |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$gp_visits_0_to_inf, 1)
  expect_equal(p1$specialist_visits_0_to_inf, 1)

  resNa <- cdm$target_cohort |>
    addOutpatientVisits(window = list(c(0, NA))) |>
    dplyr::collect()

  expect_equal(resInf, resNa)
})

test_that("addOutpatientVisits deduplicates same-day visits with countBy = 'days' vs 'records'", {
  # Synthetic CDM with multiple same-day outpatient visit records for person 1
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
    provider_id = c(1L, 2L, 3L),
    specialty_concept_id = c(38004446L, 38004453L, 38004507L) # GP, Cardiology, Oncology
  )
  # Person 1 has 3 GP visit records on 2010-03-01, and 1 on 2010-04-01 (total 4 records, 2 unique dates)
  # Person 1 also has 1 Cardiology and 1 Oncology record on the same date: 2010-05-01 (total 2 records, 1 unique specialist date)
  visit_occurrence <- tibble::tibble(
    visit_occurrence_id = 1:6,
    person_id = rep(1L, 6),
    visit_concept_id = rep(9202L, 6),
    visit_start_date = as.Date(c(
      "2010-03-01", "2010-03-01", "2010-03-01", # 3 same-day GP records
      "2010-04-01",                             # 1 distinct GP record
      "2010-05-01", "2010-05-01"               # 2 same-day specialist records (Cardio & Onco)
    )),
    visit_end_date = as.Date(c(
      "2010-03-01", "2010-03-01", "2010-03-01",
      "2010-04-01",
      "2010-05-01", "2010-05-01"
    )),
    visit_type_concept_id = rep(44818517L, 6),
    provider_id = c(1L, 1L, 1L, 1L, 2L, 3L)
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
    addOutpatientVisits(
      window = list(followup = c(0, 365)),
      stratifySpecialty = TRUE,
      specialties = list(cardiology = 38004453L, oncology = 38004507L)
    ) |>
    dplyr::collect()

  # Should deduplicate same-day visits
  expect_equal(res_days$gp_visits_followup, 2) # 2 unique dates (2010-03-01, 2010-04-01)
  expect_equal(res_days$specialist_visits_followup, 1) # 1 unique specialist visit date (2010-05-01)
  expect_equal(res_days$cardiology_visits_followup, 1) # 1 unique cardiology visit date
  expect_equal(res_days$oncology_visits_followup, 1) # 1 unique oncology visit date

  # 2. countBy = "records"
  res_records <- cdm$target_cohort |>
    addOutpatientVisits(
      window = list(followup = c(0, 365)),
      stratifySpecialty = TRUE,
      specialties = list(cardiology = 38004453L, oncology = 38004507L),
      countBy = "records"
    ) |>
    dplyr::collect()

  expect_equal(res_records$gp_visits_followup, 4) # 4 raw records
  expect_equal(res_records$specialist_visits_followup, 2) # 2 raw records
  expect_equal(res_records$cardiology_visits_followup, 1)
  expect_equal(res_records$oncology_visits_followup, 1)

  # 3. collapseOverlapping = FALSE
  res_nocollapse <- cdm$target_cohort |>
    addOutpatientVisits(
      window = list(followup = c(0, 365)),
      stratifySpecialty = TRUE,
      collapseOverlapping = FALSE
    ) |>
    dplyr::collect()

  expect_equal(res_nocollapse$gp_visits_followup, 4)
  expect_equal(res_nocollapse$specialist_visits_followup, 2)

  # 4. Error on invalid countBy
  expect_error(
    addOutpatientVisits(cdm$target_cohort, countBy = "invalid"),
    "Argument 'countBy' must be either 'days' or 'records'"
  )
})

