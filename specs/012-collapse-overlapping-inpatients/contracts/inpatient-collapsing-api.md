# API Contracts: Collapse Overlapping Inpatient Stays in `addInpatients`

**Feature Branch**: `012-collapse-overlapping-inpatients`  
**Date**: 2026-08-25  
**Spec**: [spec.md](../spec.md)

---

## 1. `CohortUtilisation::addInpatients`

```r
addInpatients <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  visitConceptIds = c(9201L, 8717L, 581379L),
  icuConceptIds = 32037L,
  icuSpecialtyConceptIds = c(38004500L),
  stratifySpecialty = FALSE,
  specialties = NULL,
  readmissions = FALSE,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "{domain}_{metric}_{window_name}",
  name = NULL
)
```

### Parameter Contract:
- `countBy`: Character scalar; either `"days"` (merge overlapping/contiguous stays into episodes) or `"records"` (count raw rows). Default: `"days"`.
- `collapseOverlapping`: Logical scalar; if `TRUE` (default), merges overlapping records and contiguous hospitalizations separated by $\le 1$ day into single episodes. If `FALSE`, forces uncollapsed row-level counting.
- Aliases `addHospitalizations()` and `addInpatient()` inherit identical parameters.

---

## 2. `CohortUtilisation::addIcuStays`

```r
addIcuStays <- function(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  icuConceptIds = 32037L,
  icuSpecialtyConceptIds = c(38004500L),
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "{domain}_{metric}_{window_name}",
  name = NULL
)
```

---

## 3. `CohortUtilisation::computeHospitalizationCohorts`

```r
computeHospitalizationCohorts <- function(
  cdm,
  name,
  visitConceptIds = c(9201L, 262L, 581379L),
  icuConceptIds = 32037L,
  readmissionWindow = 30L,
  readmission_window = NULL
)
```

### Contract & Lifecycle Note:
- Emits lifecycle note: `"computeHospitalizationCohorts() is maintained for creating standalone cohort tables. For in-database HCRU characterization, use CohortUtilisation::addInpatients()."`
- Retains 100% existing output schema and returns `cohort_table` with `hospitalization` (1) and `readmission` (2) definitions.
