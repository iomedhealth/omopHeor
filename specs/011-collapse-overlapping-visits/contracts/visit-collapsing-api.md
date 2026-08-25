# API Contracts: Collapse Overlapping and Same-Day Visits in HCRU Enrichers

**Feature Branch**: `011-collapse-overlapping-visits`  
**Date**: 2026-08-25  
**Spec**: [spec.md](../spec.md)

---

## 1. `CohortUtilisation::addOutpatientVisits`

```r
addOutpatientVisits <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  stratifySpecialty = TRUE,
  gpSpecialtyConceptIds = c(38004446L),
  specialties = NULL,
  includeEmergency = TRUE,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "{setting}_visits_{window_name}",
  name = NULL
)
```

### Parameter Contract:
- `countBy`: Character scalar; either `"days"` (deduplicate visits occurring on the same start date) or `"records"` (count raw `visit_occurrence` rows). Default: `"days"`.
- `collapseOverlapping`: Logical scalar; if `FALSE`, overrides `countBy` to `"records"`. If `TRUE`, `countBy` defaults to `"days"`. Default: `TRUE`.
- All other parameters (`x`, `indexDate`, `censorDate`, `window`, `stratifySpecialty`, `gpSpecialtyConceptIds`, `specialties`, `includeEmergency`, `nameStyle`, `name`) remain unchanged.

---

## 2. `CohortUtilisation::addEmergencyCare`

```r
addEmergencyCare <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  emergencyVisitConceptIds = c(9203L, 262L, 581478L),
  emergencySpecialtyConceptIds = c(38004510L),
  stratifySpecialty = FALSE,
  specialties = NULL,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "emergency_visits_{window_name}",
  name = NULL
)
```

### Parameter Contract:
- `countBy`: Character scalar; either `"days"` (deduplicate same-day emergency visits/spans) or `"records"`. Default: `"days"`.
- `collapseOverlapping`: Logical scalar; default: `TRUE`.
- Aliases `addEmergency()` and `addEmergencyVisits()` inherit exact same contract.

---

## 3. `CohortUtilisation::addVisits`

```r
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
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  name = NULL
)
```

### Parameter Contract:
- `countBy` and `collapseOverlapping` are forwarded directly to `addOutpatientVisits()` and `addEmergencyCare()`.

---

## 4. `CohortEconomics::extract_hcru`

```r
extract_hcru <- function(
  study,
  baseline_window = c(-365, -1),
  followup_window = c(0, 365),
  cost_field = "total_paid",
  visit_domains = c("inpatient", "outpatient", "emergency", "specialist"),
  pharmacotherapy = TRUE,
  diagnostics = TRUE,
  post_acute = TRUE,
  calculate_readmissions = FALSE,
  persistence = FALSE,
  count_by = c("days", "records")
)
```

### Parameter Contract:
- `count_by` (and alias `countBy` in `extractHcru`): Default `"days"`. Computes distinct `event_date` per patient, setting, and window.
