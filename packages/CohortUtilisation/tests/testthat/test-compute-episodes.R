test_that("computeHospitalizationCohorts collapses stays and flags readmissions", {
  cdm <- hermes_test_cdm()

  cdm$hosp <- computeHospitalizationCohorts(
    cdm = cdm,
    name = "hosp",
    visitConceptIds = c(9201L, 8717L, 581379L),
    icuConceptIds = 32037L,
    readmissionWindow = 30L
  )

  expect_true(inherits(cdm$hosp, "cohort_table"))
  hosp_df <- cdm$hosp |> dplyr::collect()

  # Cohort 1 is hospitalization, Cohort 2 is readmission
  expect_true(all(c(1L, 2L) %in% unique(hosp_df$cohort_definition_id)))

  # Patient 1 has 2 inpatient episodes (2010-02-01 to 2010-02-05, and 2010-02-20 to 2010-02-23)
  p1_hosp <- hosp_df |> dplyr::filter(.data$subject_id == 1L, .data$cohort_definition_id == 1L)
  expect_equal(nrow(p1_hosp), 2)

  # Readmission within 30d should be flagged
  p1_readm <- hosp_df |> dplyr::filter(.data$subject_id == 1L, .data$cohort_definition_id == 2L)
  expect_equal(nrow(p1_readm), 1)

  # With gapDays = 20L, Patient 1's two stays (gap = 15 days) merge into 1 continuous hospitalization
  cdm$hosp_gap20 <- computeHospitalizationCohorts(
    cdm = cdm,
    name = "hosp_gap20",
    visitConceptIds = c(9201L, 8717L, 581379L),
    icuConceptIds = 32037L,
    gapDays = 20L
  )
  hosp_gap20_df <- cdm$hosp_gap20 |> dplyr::collect()
  p1_hosp_gap20 <- hosp_gap20_df |> dplyr::filter(.data$subject_id == 1L, .data$cohort_definition_id == 1L)
  expect_equal(nrow(p1_hosp_gap20), 1)
  expect_equal(p1_hosp_gap20$cohort_start_date, as.Date("2010-02-01"))
  expect_equal(p1_hosp_gap20$cohort_end_date, as.Date("2010-02-23"))
})

test_that("computeInfusionCohorts creates infusion episodes", {
  cdm <- hermes_test_cdm()

  cdm$infusions <- computeInfusionCohorts(
    cdm = cdm,
    name = "infusions",
    routeConceptIds = c(4171047L)
  )

  expect_true(inherits(cdm$infusions, "cohort_table"))
  inf_df <- cdm$infusions |> dplyr::collect()

  # Patient 1 has 1 infusion on 2010-03-01
  expect_gte(nrow(inf_df), 1)
  expect_equal(unique(inf_df$cohort_definition_id), 1L)
  expect_equal(inf_df$subject_id[1], 1L)
})
