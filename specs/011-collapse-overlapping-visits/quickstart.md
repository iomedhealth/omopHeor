# Quickstart & Verification Guide: Collapse Overlapping and Same-Day Visits in HCRU Enrichers

**Feature Branch**: `011-collapse-overlapping-visits`  
**Date**: 2026-08-25  
**Spec**: [spec.md](./spec.md)

---

## 1. Prerequisites & Installation

Ensure local monorepo packages are loaded or installed:

```r
library(omopHeor)
library(CohortUtilisation)
library(dplyr)
```

---

## 2. Test Scenario 1: Same-Day Outpatient Visit Deduplication

### Setup Mock Data with Same-Day Entries
```r
cdm <- mockOmopHeor(numberIndividuals = 1)

# Inject 3 outpatient visits on 2010-03-01 and 1 on 2010-04-01 for person 1
# Person 1 index date: 2010-01-01
```

### Run Default Enricher (`countBy = "days"`)
```r
res_days <- addOutpatientVisits(
  x = cdm$target_cohort,
  window = list(followup = c(0, 365)),
  countBy = "days"
) |> dplyr::collect()

# Expected:
# gp_visits_followup == 2 (2 distinct dates: 2010-03-01 and 2010-04-01)
```

### Run Record-Level Enricher (`countBy = "records"`)
```r
res_records <- addOutpatientVisits(
  x = cdm$target_cohort,
  window = list(followup = c(0, 365)),
  countBy = "records"
) |> dplyr::collect()

# Expected:
# gp_visits_followup == 4 (all 4 raw database records)
```

---

## 3. Test Scenario 2: Same-Day Emergency Visits

```r
res_er_days <- addEmergencyCare(
  x = cdm$target_cohort,
  window = list(followup = c(0, 365)),
  countBy = "days"
) |> dplyr::collect()

res_er_records <- addEmergencyCare(
  x = cdm$target_cohort,
  window = list(followup = c(0, 365)),
  countBy = "records"
) |> dplyr::collect()
```

---

## 4. Test Scenario 3: Full Test Suite Execution

Run package tests:
```bash
Rscript -e "devtools::test('packages/CohortUtilisation')"
Rscript -e "devtools::test('packages/CohortEconomics')"
Rscript -e "devtools::test('.')"
```
