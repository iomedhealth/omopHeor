# Feature Specification: Configurable Episode Gap Threshold (`gapDays`) in Inpatient & Visit Utilization

**Feature Branch**: `013-configurable-gap-days`

**Created**: 2026-08-25

**Status**: Draft

**Input**: User description: "Add a configurable `gapDays` (or `collapseGap`) parameter to `addInpatients()`, `addVisits()`, and related episode collapsing functions. Currently in `CohortUtilisation::addInpatients()`, when `collapseOverlapping = TRUE`, the interval collapsing algorithm uses a hardcoded 1-day threshold (`visit_start_date > lag(max_end_so_far) + 1L`) to merge contiguous hospital stays. We want to expose this threshold as a user-configurable parameter across all relevant functions: 1. Add `gapDays = 1L` (or `collapseGap = 1L`) as an argument in `CohortUtilisation::addInpatients()`, `CohortUtilisation::addIcuStays()`, `CohortUtilisation::addVisits()`, and `CohortUtilisation::computeHospitalizationCohorts()`. 2. Behavior: `gapDays = 0L`: Collapses only strictly overlapping stays (`visit_start_date <= prev_end_date`); `gapDays = 1L` (Default): Collapses overlapping stays plus contiguous stays within 24 hours / 1 calendar day; `gapDays = N`: Merges stays where the gap between previous discharge and next admission is `<= N` days; When `collapseOverlapping = FALSE`: `gapDays` is ignored and raw rows are counted. 3. Propagate `gapDays` through `CohortUtilisation::addVisits()` and `CohortEconomics::extract_hcru()`. 4. Add input validation (`gapDays` must be an integer >= 0) and unit tests in `test-add-inpatients.R` and `test-add-visits.R`."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Flexible Inpatient Episode Collapsing via `gapDays` (Priority: P1)

As an HEOR and RWE researcher analyzing hospital utilization, I want to configure the allowable gap threshold between consecutive inpatient stays (`gapDays`, defaulting to `1L`), so that I can tailor episode definition rules to study protocols (e.g. strict overlap only with `gapDays = 0L`, next-day transfer collapsing with `gapDays = 1L`, or multi-day washouts with `gapDays = N`).

**Why this priority**: Different clinical study protocols and health systems require distinct criteria for merging hospital stays. Hardcoded collapsing rules restrict analytical flexibility and prevent exact protocol replication in comparative effectiveness studies.

**Independent Test**: Given a subject with two hospital stays (Stay 1: `2020-02-01` to `2020-02-05`; Stay 2: `2020-02-06` to `2020-02-10` [gap = 1 day]):
- Running `addInpatients(gapDays = 1L)` merges them into 1 episode (`inpatient_admissions = 1`, `inpatient_los_days = 9`).
- Running `addInpatients(gapDays = 0L)` treats them as 2 distinct episodes (`inpatient_admissions = 2`, `inpatient_los_days = 8`).

**Acceptance Scenarios**:

1. **Given** two stays separated by 1 calendar day (Discharge `2020-02-05`, Next Admission `2020-02-06`), **When** `gapDays = 1L` (default), **Then** both stays are collapsed into a single episode spanning `2020-02-01` to `2020-02-10`.
2. **Given** two stays separated by 1 calendar day, **When** `gapDays = 0L`, **Then** stays are treated as two independent hospitalizations and not merged.
3. **Given** two stays separated by 3 calendar days (Discharge `2020-02-05`, Next Admission `2020-02-08`), **When** `gapDays = 3L`, **Then** both stays are merged into one continuous episode spanning `2020-02-01` to `2020-02-10`.
4. **Given** two stays separated by 3 calendar days, **When** `gapDays = 1L`, **Then** stays remain separate episodes.
5. **Given** multiple overlapping or contiguous stays, **When** `collapseOverlapping = FALSE`, **Then** `gapDays` is ignored and each raw record is counted independently.

---

### User Story 2 - Propagation Across Multi-Setting and Economic Pipelines (Priority: P1)

As a health economics researcher executing the full 6-stage pipeline, I want `gapDays` to be seamlessly passed through `CohortUtilisation::addVisits()` and `CohortEconomics::extract_hcru()`, ensuring uniform episode definitions across all descriptive, causal, and economic stages.

**Why this priority**: Inconsistent gap definitions across multi-setting wrappers (`addVisits`) or downstream stage wrappers (`extract_hcru`) would lead to conflicting admission counts and length of stay calculations between descriptive HCRU tables and decision models.

**Independent Test**: Running `addVisits(settings = "inpatient", gapDays = 0L)` and `extract_hcru(gap_days = 0L)` on the same cohort dataset produces matching admission counts and LOS metrics for contiguous next-day stays.

**Acceptance Scenarios**:

1. **Given** a cohort evaluated with `addVisits(gapDays = 0L)`, **When** inpatient visits occur on consecutive days without overlap, **Then** `inpatient_admissions_*` reflects uncollapsed discrete episodes.
2. **Given** an economic study analyzed via `extract_hcru(gap_days = 0L)` or `extract_hcru(gapDays = 0L)`, **When** inpatient HCRU is summarized, **Then** admissions and LOS match the specified gap threshold.
3. **Given** default parameters in `addVisits()` and `extract_hcru()`, **When** executed, **Then** `gapDays = 1L` is used by default for backward compatibility.

---

### User Story 3 - Granular ICU Episode and Hospitalization Cohort Construction (Priority: P2)

As a clinical investigator studying intensive care unit stays or building standalone hospitalization cohort tables, I want `addIcuStays()` and `computeHospitalizationCohorts()` to support the configurable `gapDays` parameter (with `collapseGap` alias support), ensuring consistency across all cohort construction and characterization utilities.

**Why this priority**: ICU transfers and step-down units frequently experience brief bed gaps that researchers may wish to collapse or separate according to clinical trial or observational study definitions.

**Independent Test**: Given two consecutive ICU stays separated by 1 day, running `addIcuStays(gapDays = 0L)` reports 2 ICU admissions, whereas `addIcuStays(gapDays = 1L)` reports 1 ICU admission.

**Acceptance Scenarios**:

1. **Given** ICU stays separated by 1 day, **When** `addIcuStays(gapDays = 1L)` is called, **Then** ICU stays are collapsed into 1 ICU episode.
2. **Given** ICU stays separated by 1 day, **When** `addIcuStays(gapDays = 0L)` is called, **Then** ICU stays are counted as 2 distinct ICU episodes.
3. **Given** a call to `computeHospitalizationCohorts(gapDays = 2L)` or `compute_hospitalization_cohorts(collapse_gap = 2L)`, **When** executed, **Then** the resulting hospitalization and readmission cohort table reflects the 2-day gap collapsing threshold.

---

### User Story 4 - Robust Input Validation & Alias Handling (Priority: P2)

As a software engineer and package consumer, I want clear, informative validation errors when invalid `gapDays` arguments are supplied (e.g. negative integers, non-numeric values, or NA), and smooth alias resolution for `collapseGap` / `collapse_gap` / `gap_days`.

**Why this priority**: Robust validation prevents silent database query errors, malformed SQL expressions, and confusing downstream calculation anomalies.

**Independent Test**: Calling `addInpatients(gapDays = -1L)` or `addInpatients(gapDays = "one")` throws a clear validation error indicating `gapDays` must be a non-negative integer.

**Acceptance Scenarios**:

1. **Given** a call with `gapDays = -1L`, **When** executed, **Then** an informative error is raised stating `gapDays` must be an integer >= 0.
2. **Given** a call with `gapDays = NULL` or non-integer numeric (e.g. `1.5`), **When** validated, **Then** an informative error or appropriate type conversion is enforced.
3. **Given** a call supplying `collapseGap = 2L` instead of `gapDays`, **When** executed, **Then** the value 2 is respected and used for interval collapsing.

---

### Edge Cases

- **Zero Gap (`gapDays = 0L`)**: Stays that touch on the same day (Discharge `2020-01-05`, Next Admission `2020-01-05`) or strictly overlap (Admission `2020-01-04`) are merged; stays starting the next calendar day (`2020-01-06`) are not merged.
- **Uncollapsed Mode (`collapseOverlapping = FALSE`)**: `gapDays` is disregarded completely; raw database records are counted.
- **Chained Stays (A $\rightarrow$ B $\rightarrow$ C)**: If Stay A ends on day 5, Stay B starts on day 6 and ends on day 10, and Stay C starts on day 11 and ends on day 15, with `gapDays = 1L`, all three stays collapse into a single episode spanning day 1 to day 15.
- **Non-Inpatient Care Settings**: Outpatient and emergency visit collapsing in `addVisits()` uses same-day / overlapping collapsing, whereas `gapDays` specifically controls inpatient and ICU episode collapsing intervals.
- **Patients with No Stays**: Zero-utilization patients receive 0 across all generated metric columns regardless of `gapDays`.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `addInpatients()` MUST accept a `gapDays` argument (default `1L`) defining the maximum allowed gap in days between previous stay discharge and subsequent admission for episode merging.
- **FR-002**: `addIcuStays()` MUST accept and pass `gapDays` to `addInpatients()`.
- **FR-003**: `addVisits()` MUST accept and propagate `gapDays` to `addInpatients()`.
- **FR-004**: `computeHospitalizationCohorts()` and `compute_hospitalization_cohorts()` MUST accept `gapDays` (and `collapseGap` / `collapse_gap` alias) and use it when identifying episode boundaries.
- **FR-005**: `CohortEconomics::extract_hcru()` MUST accept and propagate `gap_days` / `gapDays` to its inpatient episode collapsing and readmission detection algorithms.
- **FR-006**: When `collapseOverlapping = TRUE` (or `countBy = "days"`):
  - Stays with `visit_start_date <= prev_max_end + gapDays` MUST be merged into a single continuous episode.
  - Stays with `visit_start_date > prev_max_end + gapDays` MUST begin a new episode.
- **FR-007**: When `collapseOverlapping = FALSE` (or `countBy = "records"`), `gapDays` MUST be ignored and raw row counting must be performed.
- **FR-008**: An argument validator MUST verify that `gapDays` is a single integer >= 0, raising an informative error otherwise.
- **FR-009**: Aliases `collapseGap`, `collapse_gap`, and `gap_days` MUST be supported across functions for backward and naming compatibility.

### Key Entities

- **`Inpatient Episode`**: A consolidated period of hospitalization created by merging overlapping and contiguous inpatient stays whose intervening gap is `<= gapDays`.
- **`Gap Days Threshold`**: An integer parameter ($\ge 0$) specifying the maximum number of calendar days between consecutive stays that are merged into one continuous care episode.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of contiguous inpatient stays separated by `<= gapDays` are merged into single episodes when `collapseOverlapping = TRUE`.
- **SC-002**: 100% of contiguous inpatient stays separated by `> gapDays` remain distinct independent episodes.
- **SC-003**: Inpatient admissions and length of stay calculations match exact expectations across `gapDays = 0L`, `gapDays = 1L`, and `gapDays = NL` in automated unit tests.
- **SC-004**: 100% of test suites in `CohortUtilisation` and `CohortEconomics` pass with 0 errors.
- **SC-005**: `R CMD check --no-manual --as-cran` passes across all monorepo packages with 0 Errors and 0 Warnings.

---

## Assumptions

- The default value `gapDays = 1L` preserves existing behavior where same-day and next-day transfers (within 24 hours / 1 calendar day) are collapsed.
- Setting `gapDays = 0L` represents the strictest definition where only overlapping or same-day discharge/admission records are merged.
- Direct financial records in `CohortCosts::addCosts()` remain granular at the transaction level and are not collapsed.
