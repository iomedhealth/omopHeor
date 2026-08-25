# Quickstart Guide: Collapse Overlapping Inpatient Stays in `addInpatients`

**Feature Branch**: `012-collapse-overlapping-inpatients`  
**Date**: 2026-08-25  
**Spec**: [spec.md](./spec.md)

---

## 1. Test Scenario 1: Overlapping Inpatient Stays Collapsing

```r
library(omopHeor)
library(dplyr)

cdm <- mockOmopHeor(numberIndividuals = 1)

# Subject 1 has 2 overlapping stays:
# Stay 1: 2010-02-01 to 2010-02-05 (4 days)
# Stay 2: 2010-02-04 to 2010-02-10 (6 days)
# Combined interval: 2010-02-01 to 2010-02-10 (9 days total)

# 1. Collapsed mode (Default)
res_collapsed <- cdm$target_cohort |>
  addInpatients(
    window = list(followup = c(0, 365)),
    collapseOverlapping = TRUE
  ) |>
  dplyr::collect()

# Expected:
# inpatient_admissions_followup == 1
# inpatient_los_days_followup == 9
# inpatient_mean_los_days_followup == 9

# 2. Uncollapsed mode
res_raw <- cdm$target_cohort |>
  addInpatients(
    window = list(followup = c(0, 365)),
    collapseOverlapping = FALSE
  ) |>
  dplyr::collect()

# Expected:
# inpatient_admissions_followup == 2
# inpatient_los_days_followup == 10
# inpatient_mean_los_days_followup == 5
```

---

## 2. Test Scenario 2: Transfer vs. True Readmission

```r
# Stay 1: 2010-01-01 to 2010-01-05
# Stay 2 (Transfer): 2010-01-05 to 2010-01-10 (same episode!)
# Stay 3 (True readmission): 2010-01-25 to 2010-01-28

res_readm <- cdm$target_cohort |>
  addInpatients(
    window = list(followup = c(0, 365)),
    readmissions = TRUE,
    collapseOverlapping = TRUE
  ) |>
  dplyr::collect()

# Expected:
# inpatient_admissions_followup == 2 (Episode 1: Jan 1-10, Episode 2: Jan 25-28)
# readmissions_30d_followup == 1 (Only the return on Jan 25th)
```
