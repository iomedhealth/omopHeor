test_that("addInpatients validates input arguments correctly", {
  cdm <- hermesTestCdm()
  cohort <- cdm$target_cohort

  expect_error(addInpatients(list()), "Argument 'x' must be a cdm_table or cohort_table")
  expect_error(addInpatients(cohort, indexDate = "not_a_col"), "indexDate 'not_a_col' must be a column in x")
  expect_error(addInpatients(cohort, window = list(c(10, 0))), "Window interval \\[10, 0\\] is invalid")
  expect_error(addInpatients(cohort, specialties = "not_a_list"), "must be a named list")
  expect_error(addInpatients(cohort, specialties = list(123)), "must be a named list")
})

test_that("addInpatients computes admissions, LOS, ICU stays, and readmissions", {
  cdm <- hermesTestCdm()

  cohortEnriched <- cdm$target_cohort |>
    addInpatients(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      readmissions = TRUE
    ) |>
    dplyr::collect()

  expect_true(is.data.frame(cohortEnriched))
  expect_equal(nrow(cohortEnriched), nrow(cdm$target_cohort |> dplyr::collect()))

  cols <- colnames(cohortEnriched)
  expect_true(all(c(
    "inpatient_admissions_baseline", "inpatient_los_days_baseline", "inpatient_mean_los_days_baseline",
    "inpatient_admissions_followup", "inpatient_los_days_followup", "inpatient_mean_los_days_followup",
    "icu_admissions_followup", "icu_los_days_followup", "icu_mean_los_days_followup",
    "readmissions_30d_followup"
  ) %in% cols))

  # Patient 1 has 2 inpatient admissions (4 + 3 = 7 days LOS, mean 3.5), 1 ICU (2 days, mean 2), 1 30d readmission in followup
  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$inpatient_admissions_followup, 2)
  expect_equal(p1$inpatient_los_days_followup, 7)
  expect_equal(p1$inpatient_mean_los_days_followup, 3.5)
  expect_equal(p1$icu_admissions_followup, 1)
  expect_equal(p1$icu_los_days_followup, 2)
  expect_equal(p1$icu_mean_los_days_followup, 2)
  expect_equal(p1$readmissions_30d_followup, 1)
})

test_that("addInpatients detects ICU stays via provider icuSpecialtyConceptIds", {
  cdm <- hermesTestCdm()

  # Update provider table so provider 1 has specialty 38004500 (Critical care intensivist)
  provDf <- cdm$provider |> dplyr::collect()
  provDf$specialty_concept_id[provDf$provider_id == 1L] <- 38004500L
  cdm <- omopgenerics::insertTable(cdm, name = "provider", table = provDf, overwrite = TRUE)

  cohortEnriched <- cdm$target_cohort |>
    addInpatients(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      icuSpecialtyConceptIds = c(38004500L),
      readmissions = FALSE
    ) |>
    dplyr::collect()

  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$inpatient_admissions_followup, 0)
  expect_equal(p1$inpatient_los_days_followup, 0)
  expect_equal(p1$icu_admissions_followup, 3)
  expect_equal(p1$icu_los_days_followup, 9)
})

test_that("addInpatients computes granular specialty breakdowns", {
  cdm <- hermesTestCdm()

  # Provider 1 has specialty 38004446L (General Practice)
  cohortEnriched <- cdm$target_cohort |>
    addInpatients(
      window = list(baseline = c(-365, -1), followup = c(0, 365)),
      stratifySpecialty = TRUE,
      specialties = list(
        general_practice = 38004446L,
        cardiology = 38004453L
      )
    ) |>
    dplyr::collect()

  cols <- colnames(cohortEnriched)
  expect_true(all(c(
    "general_practice_inpatient_admissions_baseline",
    "general_practice_inpatient_admissions_followup",
    "cardiology_inpatient_admissions_baseline",
    "cardiology_inpatient_admissions_followup"
  ) %in% cols))

  # Patient 1 has 2 general inpatient admissions with provider 1 (specialty 38004446L) in followup
  p1 <- cohortEnriched |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$general_practice_inpatient_admissions_followup, 2)
  expect_equal(p1$cardiology_inpatient_admissions_followup, 0)

  # Patient 2 has 1 inpatient admission with provider 1 in followup
  p2 <- cohortEnriched |> dplyr::filter(.data$subject_id == 2L)
  expect_equal(p2$general_practice_inpatient_admissions_followup, 1)
  expect_equal(p2$cardiology_inpatient_admissions_followup, 0)
})

test_that("addHospitalizations and addInpatient backward-compatibility aliases work identically", {
  cdm <- hermesTestCdm()

  res1 <- cdm$target_cohort |>
    addInpatients(window = list(followup = c(0, 365))) |>
    dplyr::collect()

  res2 <- cdm$target_cohort |>
    addHospitalizations(window = list(followup = c(0, 365))) |>
    dplyr::collect()

  res3 <- cdm$target_cohort |>
    addInpatient(window = list(followup = c(0, 365))) |>
    dplyr::collect()

  expect_equal(res1, res2)
  expect_equal(res1, res3)
})

test_that("addInpatients supports infinite and NA window bounds without case mismatch", {
  cdm <- hermesTestCdm()

  # 1. Unnamed c(0, Inf) -> columns *_0_to_inf
  resInf <- cdm$target_cohort |>
    addInpatients(window = c(0, Inf)) |>
    dplyr::collect()

  expect_true("inpatient_admissions_0_to_inf" %in% colnames(resInf))
  expect_true("inpatient_los_days_0_to_inf" %in% colnames(resInf))
  p1 <- resInf |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1$inpatient_admissions_0_to_inf, 2)

  # 2. NA normalization: c(0, NA) -> identical to c(0, Inf)
  resNa <- cdm$target_cohort |>
    addInpatients(window = list(c(0, NA))) |>
    dplyr::collect()

  expect_equal(resInf, resNa)

  # 3. Named window: list(all_followup = c(0, Inf))
  resNamed <- cdm$target_cohort |>
    addInpatients(window = list(all_followup = c(0, Inf))) |>
    dplyr::collect()

  expect_true("inpatient_admissions_all_followup" %in% colnames(resNamed))
  p1Named <- resNamed |> dplyr::filter(.data$subject_id == 1L)
  expect_equal(p1Named$inpatient_admissions_all_followup, 2)

  # 4. Bilateral infinite window: c(-Inf, Inf) -> *_minf_to_inf
  resBilateral <- cdm$target_cohort |>
    addInpatients(window = c(-Inf, Inf)) |>
    dplyr::collect()

  expect_true("inpatient_admissions_minf_to_inf" %in% colnames(resBilateral))
})

test_that("addInpatients collapses overlapping stays and contiguous hospitalizations", {
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

  # Person 1 has:
  # Episode 1: Stay A (2010-02-01 to 2010-02-05) + Stay B (2010-02-04 to 2010-02-10) -> Overlapping! Collapses to 2010-02-01 to 2010-02-10 (9 days)
  # Episode 2: Stay C (2010-02-25 to 2010-02-28) -> Discharge of Ep 1 was 2010-02-10. Gap is 15 days -> Readmission <= 30d!
  # Contiguous to Episode 2: Stay D (2010-03-01 to 2010-03-05) -> Gap between Feb 28 and Mar 01 is 1 day -> Contiguous! Merges with Ep 2 to 2010-02-25 to 2010-03-05 (8 days)
  visit_occurrence <- tibble::tibble(
    visit_occurrence_id = 1:4,
    person_id = rep(1L, 4),
    visit_concept_id = rep(9201L, 4),
    visit_start_date = as.Date(c(
      "2010-02-01", "2010-02-04",
      "2010-02-25", "2010-03-01"
    )),
    visit_end_date = as.Date(c(
      "2010-02-05", "2010-02-10",
      "2010-02-28", "2010-03-05"
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

  # 1. Collapsed mode (Default: gapDays = 1L)
  res_collapsed <- cdm$target_cohort |>
    addInpatients(
      window = list(followup = c(0, 365)),
      readmissions = TRUE,
      collapseOverlapping = TRUE
    ) |>
    dplyr::collect()

  # 4 raw records collapse into 2 distinct episodes:
  # Ep 1: Feb 1-10 (9 days)
  # Ep 2: Feb 25 - Mar 5 (8 days)
  # Total admissions = 2, total LOS = 17, mean LOS = 8.5, readmissions 30d = 1
  expect_equal(res_collapsed$inpatient_admissions_followup, 2)
  expect_equal(res_collapsed$inpatient_los_days_followup, 17)
  expect_equal(res_collapsed$inpatient_mean_los_days_followup, 8.5)
  expect_equal(res_collapsed$readmissions_30d_followup, 1)

  # 1b. gapDays = 0L: Stay C (Feb 25-28) and Stay D (Mar 1-5, gap = 1 day) do NOT merge
  res_gap0 <- cdm$target_cohort |>
    addInpatients(
      window = list(followup = c(0, 365)),
      readmissions = TRUE,
      gapDays = 0L,
      collapseOverlapping = TRUE
    ) |>
    dplyr::collect()

  # 3 distinct episodes: Feb 1-10 (9d), Feb 25-28 (3d), Mar 1-5 (4d)
  # Total admissions = 3, total LOS = 16, readmissions 30d = 2 (Feb 25 is 15d from Feb 10; Mar 1 is 1d from Feb 28)
  expect_equal(res_gap0$inpatient_admissions_followup, 3)
  expect_equal(res_gap0$inpatient_los_days_followup, 16)
  expect_equal(res_gap0$readmissions_30d_followup, 2)

  # 1c. collapseGap alias works identically
  res_alias <- cdm$target_cohort |>
    addInpatients(
      window = list(followup = c(0, 365)),
      readmissions = TRUE,
      collapseGap = 0L,
      collapseOverlapping = TRUE
    ) |>
    dplyr::collect()

  expect_equal(res_alias$inpatient_admissions_followup, 3)
  expect_equal(res_alias$inpatient_los_days_followup, 16)

  # 2. Uncollapsed mode: collapseOverlapping = FALSE
  res_uncollapsed <- cdm$target_cohort |>
    addInpatients(
      window = list(followup = c(0, 365)),
      readmissions = TRUE,
      collapseOverlapping = FALSE
    ) |>
    dplyr::collect()

  # 4 raw records, total LOS = (5-1) + (10-4) + (28-25) + (5-1) = 4 + 6 + 3 + 4 = 17, mean = 4.25
  expect_equal(res_uncollapsed$inpatient_admissions_followup, 4)
  expect_equal(res_uncollapsed$inpatient_mean_los_days_followup, 4.25)

  # 3. Invalid countBy error
  expect_error(
    addInpatients(cdm$target_cohort, countBy = "invalid"),
    "Argument 'countBy' must be either 'days' or 'records'"
  )

  # 4. Invalid gapDays error
  expect_error(
    addInpatients(cdm$target_cohort, gapDays = -1L),
    "Argument 'gapDays' must be a single non-negative integer"
  )
  expect_error(
    addInpatients(cdm$target_cohort, gapDays = "two"),
    "Argument 'gapDays' must be a single non-negative integer"
  )
  expect_error(
    addInpatients(cdm$target_cohort, gapDays = 1.5),
    "Argument 'gapDays' must be a single non-negative integer"
  )

  # 5. addIcuStays with gapDays
  res_icu <- cdm$target_cohort |>
    addIcuStays(
      window = list(followup = c(0, 365)),
      gapDays = 1L
    ) |>
    dplyr::collect()

  expect_true(all(c("icu_admissions_followup", "icu_los_days_followup") %in% colnames(res_icu)))
  expect_false(any(grepl("^inpatient_", colnames(res_icu))))
})

