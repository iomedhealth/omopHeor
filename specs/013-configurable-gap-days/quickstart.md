# Quickstart: Testing Configurable Gap Threshold (`gapDays`)

This guide provides runnable R examples to verify the configurable `gapDays` parameter across `CohortUtilisation` and `CohortEconomics`.

---

## 1. Prerequisites

Load the packages and create a mock Eunomia CDM instance:

```r
library(omopHeor)
library(CohortUtilisation)
library(CohortEconomics)
library(dplyr)

# Connect to mock test CDM
cdm <- mockCohortUtilisationCDM()
```

---

## 2. Inpatient Episode Collapsing with `gapDays`

### Scenario A: Strict Overlap Only (`gapDays = 0L`)
```r
# Stays separated by 1 day remain independent episodes
res_gap0 <- cdm$cohort1 |>
  addInpatients(
    window = list(followup = c(0, 365)),
    gapDays = 0L,
    collapseOverlapping = TRUE
  ) |>
  collect()

print(res_gap0 |> select(subject_id, inpatient_admissions_followup, inpatient_los_days_followup))
```

### Scenario B: 1-Day Next-Day Transfer Collapsing (`gapDays = 1L` - Default)
```r
# Stays separated by <= 1 day are merged into 1 continuous episode
res_gap1 <- cdm$cohort1 |>
  addInpatients(
    window = list(followup = c(0, 365)),
    gapDays = 1L,
    collapseOverlapping = TRUE
  ) |>
  collect()

print(res_gap1 |> select(subject_id, inpatient_admissions_followup, inpatient_los_days_followup))
```

### Scenario C: Multi-Setting Extraction via `addVisits`
```r
# Propagation through addVisits
res_visits <- cdm$cohort1 |>
  addVisits(
    window = list(followup = c(0, 365)),
    gapDays = 0L
  ) |>
  collect()
```

---

## 3. Input Validation

Verify that invalid gap values are rejected:

```r
# Negative gapDays throws error
tryCatch(
  cdm$cohort1 |> addInpatients(gapDays = -1L),
  error = function(e) message("Caught expected error: ", e$message)
)
```

---

## 4. Running Package Test Suites

```bash
# Run unit tests in CohortUtilisation
R -e "devtools::test('packages/CohortUtilisation')"

# Run unit tests in CohortEconomics
R -e "devtools::test('packages/CohortEconomics')"
```
