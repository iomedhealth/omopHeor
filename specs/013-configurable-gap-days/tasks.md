# Tasks: Configurable Episode Gap Threshold (`gapDays`) in Inpatient & Visit Utilization

**Branch**: `013-configurable-gap-days` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

---

## Tasks

### Phase 1: Setup

- [X] T001 Initialize task tracking and verify baseline test suite passes across `CohortUtilisation` and `CohortEconomics`

---

### Phase 2: Foundational

- [X] T002 Implement `validateGapDays()` helper in `packages/CohortUtilisation/R/utilities.R` with alias resolution (`gapDays`, `collapseGap`) and non-negative integer validation

---

### Phase 3: User Story 1 - Flexible Inpatient Episode Collapsing via `gapDays` (Priority: P1)

**Story Goal**: Expose `gapDays = 1L` in `CohortUtilisation::addInpatients()` so users can configure the maximum discharge-to-admission gap for merging contiguous hospital stays into discrete episodes when `collapseOverlapping = TRUE`.  
**Independent Test**: Given two hospital stays separated by 1 calendar day, `addInpatients(gapDays = 1L)` merges them into 1 episode (1 admission, 9 LOS days), while `addInpatients(gapDays = 0L)` leaves them as 2 distinct episodes (2 admissions, 8 LOS days).

- [X] T003 [P] [US1] Add `gapDays = 1L` and `collapseGap = NULL` arguments to `CohortUtilisation::addInpatients()` in `packages/CohortUtilisation/R/addInpatients.R` and update Roxygen documentation
- [X] T004 [US1] Update interval collapsing logic in `packages/CohortUtilisation/R/addInpatients.R` to evaluate `.data$visit_start_date > lag(.data$max_end_num) + gapDays`
- [X] T005 [P] [US1] Add unit tests in `packages/CohortUtilisation/tests/testthat/test-add-inpatients.R` verifying `gapDays = 0L`, `gapDays = 1L` (default), `gapDays = 3L`, and `collapseOverlapping = FALSE`

---

### Phase 4: User Story 2 - Propagation Across Multi-Setting & Economic Pipelines (Priority: P1)

**Story Goal**: Propagate `gapDays` through `CohortUtilisation::addVisits()` and `CohortEconomics::extract_hcru()` to guarantee consistent hospitalization episode definitions across the 6-stage HEOR pipeline.  
**Independent Test**: Running `addVisits(settings = "inpatient", gapDays = 0L)` and `extract_hcru(gap_days = 0L)` on the same dataset yields matching discrete admission counts and length of stay calculations.

- [X] T006 [P] [US2] Update `CohortUtilisation::addVisits()` in `packages/CohortUtilisation/R/addVisits.R` to accept `gapDays` / `collapseGap` and forward them to `addInpatients()`
- [X] T007 [P] [US2] Update `CohortEconomics::extract_hcru()` in `packages/CohortEconomics/R/hcru.R` to accept `gap_days = 1L` / `gapDays = NULL` and incorporate them into the inpatient windowing & collapsing logic
- [X] T008 [P] [US2] Add unit tests for `addVisits()` in `packages/CohortUtilisation/tests/testthat/test-add-visits.R` verifying `gapDays` forwarding to the inpatient domain
- [X] T009 [P] [US2] Add unit tests for `extract_hcru()` in `packages/CohortEconomics/tests/testthat/test-stage2-hcru.R` verifying `gap_days` behavior across baseline and followup windows

---

### Phase 5: User Story 3 - Granular ICU Episode & Hospitalization Cohort Construction (Priority: P2)

**Story Goal**: Expose `gapDays` / `collapseGap` in `CohortUtilisation::addIcuStays()` and `computeHospitalizationCohorts()` / `compute_hospitalization_cohorts()`.  
**Independent Test**: Running `addIcuStays(gapDays = 0L)` on contiguous ICU stays separated by 1 day yields 2 ICU admissions, whereas `gapDays = 1L` yields 1 ICU admission.

- [X] T010 [P] [US3] Update `CohortUtilisation::addIcuStays()` in `packages/CohortUtilisation/R/addInpatients.R` to accept and forward `gapDays` / `collapseGap`
- [X] T011 [P] [US3] Update `computeHospitalizationCohorts()` and `compute_hospitalization_cohorts()` in `packages/CohortUtilisation/R/hospitalizations.R` to accept `gapDays` / `collapseGap` / `collapse_gap`
- [X] T012 [P] [US3] Add unit tests in `packages/CohortUtilisation/tests/testthat/test-compute-episodes.R` for `computeHospitalizationCohorts(gapDays = ...)`

---

### Phase 6: User Story 4 - Robust Input Validation & Alias Handling (Priority: P2)

**Story Goal**: Ensure defensive argument checks for `gapDays` (rejecting negative, non-integer, NA, or invalid types) with clear error reporting and smooth alias resolution.  
**Independent Test**: Calling `addInpatients(gapDays = -1L)` or `addInpatients(gapDays = "invalid")` raises an informative error.

- [X] T013 [P] [US4] Add comprehensive input validation tests in `packages/CohortUtilisation/tests/testthat/test-add-inpatients.R` for invalid `gapDays` values and alias resolution
- [X] T014 [P] [US4] Add input validation tests in `packages/CohortEconomics/tests/testthat/test-stage2-hcru.R` for invalid `gap_days` values

---

### Phase 7: Polish & Cross-Cutting Concerns

- [X] T015 Run `devtools::document()` across `packages/CohortUtilisation`, `packages/CohortEconomics`, and root `omopHeor` to regenerate Rd documentation and NAMESPACE files
- [X] T016 Run full test suites with `devtools::test()` across all packages and verify `R CMD check` passes cleanly

---

## Dependencies & Execution Order

```
[Phase 1: Setup (T001)]
        │
        ▼
[Phase 2: Foundational (T002: validateGapDays)]
        │
        ├─────────────────────────────────────────┐
        ▼                                         ▼
[Phase 3: US1 Inpatient Collapsing (T003-T005)]  [Phase 5: US3 ICU & Cohorts (T010-T012)]
        │                                         │
        ▼                                         ▼
[Phase 4: US2 Wrappers & Economics (T006-T009)]   │
        │                                         │
        ├─────────────────────────────────────────┘
        ▼
[Phase 6: US4 Input Validation Tests (T013-T014)]
        │
        ▼
[Phase 7: Polish & R CMD Check (T015-T016)]
```

---

## Parallel Execution Opportunities

- **US1 & US3**: `test-add-inpatients.R` (T005) and `hospitalizations.R` (T011) can be developed in parallel once T002 is complete.
- **US2**: `CohortUtilisation/R/addVisits.R` (T006) and `CohortEconomics/R/hcru.R` (T007) are in separate packages and can be implemented in parallel.
- **Tests**: T008, T009, T012, T013, and T014 can be run in parallel test suites.

---

## Implementation Strategy

1. **MVP (Phase 1 to Phase 3)**: Expose `gapDays` in `CohortUtilisation::addInpatients()` with `validateGapDays()` and unit tests for `gapDays = 0L`, `1L`, `3L`.
2. **Incremental Delivery (Phase 4 to Phase 6)**: Propagate through `addVisits()`, `extract_hcru()`, `addIcuStays()`, and `computeHospitalizationCohorts()`.
3. **Verification (Phase 7)**: Regenerate roxygen documentation and run `R CMD check`.
