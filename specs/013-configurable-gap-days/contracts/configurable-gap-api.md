# API Contract: Configurable Episode Gap Threshold (`gapDays`)

This document defines the functional signatures, parameter specifications, error handling, and behavioral contracts across the `CohortUtilisation` and `CohortEconomics` packages.

---

## 1. `CohortUtilisation::addInpatients`

### Signature
```r
addInpatients(
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
  gapDays = 1L,
  collapseGap = NULL,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "{domain}_{metric}_{window_name}",
  name = NULL
)
```

### Parameters
- `gapDays`: Integer scalar >= 0. Maximum gap in days between previous stay discharge date and subsequent admission date to collapse into a single episode. Default: `1L`.
- `collapseGap`: Optional alias for `gapDays`. If provided when `gapDays` is default, `collapseGap` is used.
- `collapseOverlapping`: Logical flag. If `FALSE`, forces `countBy = "records"` and ignores `gapDays`.

### Error Contract
- If `gapDays` is not an integer >= 0 (e.g. negative, NA, non-numeric), throws an informative error:
  `"Argument 'gapDays' must be a single non-negative integer (>= 0)."`

---

## 2. `CohortUtilisation::addIcuStays`

### Signature
```r
addIcuStays(
  x,
  indexDate = "cohort_start_date",
  censorDate = NULL,
  window = list(c(-365, -1), c(0, 365)),
  icuConceptIds = 32037L,
  icuSpecialtyConceptIds = c(38004500L),
  gapDays = 1L,
  collapseGap = NULL,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  nameStyle = "{domain}_{metric}_{window_name}",
  name = NULL
)
```

### Behavior
- Passes `gapDays = gapDays` and `collapseGap = collapseGap` through to `addInpatients()`.

---

## 3. `CohortUtilisation::addVisits`

### Signature
```r
addVisits(
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
  gapDays = 1L,
  collapseGap = NULL,
  countBy = c("days", "records"),
  collapseOverlapping = TRUE,
  name = NULL
)
```

### Behavior
- Passes `gapDays`, `collapseOverlapping`, and `countBy` to `addInpatients()`.

---

## 4. `CohortUtilisation::computeHospitalizationCohorts`

### Signature
```r
computeHospitalizationCohorts(
  cdm,
  name,
  visitConceptIds = c(9201L, 262L, 581379L),
  icuConceptIds = 32037L,
  readmissionWindow = 30L,
  gapDays = 1L,
  collapseGap = NULL,
  readmission_window = NULL
)

compute_hospitalization_cohorts(
  cdm,
  name,
  visit_concept_ids = c(9201L, 262L, 32037L, 581379L),
  readmission_window = 30L,
  collapse_gap = 1L,
  gap_days = NULL
)
```

### Behavior
- Generates collapsed hospitalization cohort table where stays with gap $\le \text{gapDays}$ are merged.

---

## 5. `CohortEconomics::extract_hcru`

### Signature
```r
extract_hcru(
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
  count_by = c("days", "records"),
  gap_days = 1L,
  gapDays = NULL
)
```

### Behavior
- Uses `gap_days` when summarizing inpatient hospitalizations and detecting 30-day/90-day readmissions.
