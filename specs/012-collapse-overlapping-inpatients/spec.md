# Feature Specification: Collapse Overlapping and Contiguous Inpatient Stays in `addInpatients`

**Feature Branch**: `012-collapse-overlapping-inpatients`

**Created**: 2026-08-25

**Status**: Draft

**Input**: User description: "the collapse overlapping to be equivalent if collapseOverlapping = TRUE in addInpatients"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Overlapping & Contiguous Inpatient Episode Collapsing (Priority: P1)

As an HEOR/RWE researcher evaluating hospital care utilization, I want `addInpatients()` to merge overlapping hospital stays (such as internal service transfers) and contiguous hospitalizations (discharges and re-entries separated by <= 1 day) into discrete hospitalization episodes when `collapseOverlapping = TRUE` (default), so that hospital admissions and total length of stay (LOS) reflect true hospitalization events without double counting days.

**Why this priority**: In OMOP CDM data, when a hospitalized patient is transferred across departments (e.g. from Emergency/Internal Medicine to Pulmonology, or from Intensive Care to General Ward), separate `visit_occurrence` rows are created with overlapping or contiguous dates. Counting each row independently inflates total admissions and causes double counting of hospital days.

**Independent Test**: Given a cohort patient with two overlapping inpatient records (Stay A: `2020-02-01` to `2020-02-05` [4 days], Stay B: `2020-02-04` to `2020-02-10` [6 days]), running `addInpatients(collapseOverlapping = TRUE)` yields `inpatient_admissions_followup = 1` and `inpatient_los_days_followup = 9` (from `2020-02-01` to `2020-02-10`), whereas uncollapsed mode (`collapseOverlapping = FALSE`) yields 2 admissions and 10 days.

**Acceptance Scenarios**:

1. **Given** overlapping inpatient visits for a subject, **When** `addInpatients(collapseOverlapping = TRUE)` is run, **Then** the stays are merged into 1 hospitalization episode spanning `[min(start), max(end)]` and LOS is calculated on the merged interval.
2. **Given** contiguous inpatient stays separated by <= 1 day (e.g. discharged `2020-03-05`, re-entered `2020-03-06`), **When** `addInpatients(collapseOverlapping = TRUE)` is run, **Then** both stays are merged into a single continuous hospitalization episode.
3. **Given** discrete hospitalizations separated by more than 1 day, **When** `addInpatients()` is run, **Then** each distinct hospitalization episode is counted separately.

---

### User Story 2 - True Readmission Detection on Collapsed Episodes (Priority: P1)

As an HEOR researcher evaluating quality of care and acute readmissions, I want 30-day and 90-day readmissions (`readmissions_30d_*`, `readmissions_90d_*`) to be measured exclusively between distinct, collapsed hospitalization episodes, so that internal service transfers or same-day bed movements are never misclassified as readmissions.

**Why this priority**: When stays are not collapsed, an internal bed transfer or ICU step-down is falsely flagged as a "readmission within 30 days" because the next record starts immediately after the previous ward record. Collapsing episodes first guarantees that readmission metrics represent genuine post-discharge returns to the hospital.

**Independent Test**: Given a patient with a transfer from Ward 1 (`2020-01-01` to `2020-01-05`) to Ward 2 (`2020-01-05` to `2020-01-10`) and a true readmission on `2020-01-25`, running `addInpatients(readmissions = TRUE, collapseOverlapping = TRUE)` yields `readmissions_30d_followup = 1` (the return on Jan 25th) instead of 2.

**Acceptance Scenarios**:

1. **Given** internal ward transfers during an active hospitalization, **When** `readmissions = TRUE` is enabled, **Then** transfers are collapsed into the index stay and generate 0 readmission flags.
2. **Given** a patient discharged from a collapsed episode who returns to the hospital within 30 days, **When** `addInpatients()` is run, **Then** `readmissions_30d_*` increments by 1.

---

### User Story 3 - ICU and Specialty Integration within Collapsed Hospitalizations (Priority: P2)

As a clinical investigator, when evaluating inpatient care complexity, I want ICU stays (`icu_admissions_*`, `icu_los_days_*`) and specialty stratifications (`{specialty}_inpatient_admissions_*`) to remain accurately tracked within or alongside collapsed hospital episodes.

**Why this priority**: A patient hospitalized for 10 days may spend 3 of those days in the ICU. The overall hospitalization is 1 admission and 10 days total LOS, while the ICU metric reflects 1 ICU admission and 3 ICU days.

**Independent Test**: Given a patient with an inpatient stay from `2020-02-01` to `2020-02-10` containing an ICU stay from `2020-02-02` to `2020-02-05`, running `addInpatients()` computes `inpatient_admissions = 1`, `inpatient_los_days = 9`, `icu_admissions = 1`, and `icu_los_days = 3`.

**Acceptance Scenarios**:

1. **Given** an inpatient hospitalization with an embedded ICU component, **When** `addInpatients()` is executed, **Then** total hospitalization metrics reflect the full collapsed episode and ICU metrics reflect the ICU sub-stay duration.

---

### User Story 4 - Multi-Setting & Downstream Harmonization (`addVisits`, `extract_hcru`) (Priority: P2)

As a health economist running the full 6-stage pipeline, I want `addVisits()` and `CohortEconomics::extract_hcru()` to benefit from collapsed inpatient episodes by default, ensuring cross-package consistency.

**Why this priority**: Ensures that whether a user calls `addInpatients()`, `addVisits()`, or `extract_hcru()`, the resulting inpatient admissions and lengths of stay match identical epidemiological definitions.

**Independent Test**: Running `addVisits(settings = "inpatient")` and `extract_hcru()` on the same cohort yields identical collapsed admission and LOS counts.

**Acceptance Scenarios**:

1. **Given** a cohort analyzed with `addVisits()`, **When** `collapseOverlapping = TRUE` (default), **Then** inpatient episodes are collapsed using the unified algorithm.

---

### User Story 5 - Lifecycle Management & Deprecation of `computeHospitalizationCohorts` (Priority: P3)

As a package maintainer, I want `computeHospitalizationCohorts()` to issue a clear lifecycle deprecation notice pointing users to `addInpatients()` for HCRU characterization, while preserving full functionality for backward compatibility and cohort table construction.

**Why this priority**: Consolidates the analytical API around the DARWIN EU `PatientProfiles` enrichment paradigm, reducing user confusion about which hospitalization function to use.

**Independent Test**: Calling `computeHospitalizationCohorts()` issues a deprecation/lifecycle informational note while still returning the valid cohort table.

**Acceptance Scenarios**:

1. **Given** a call to `computeHospitalizationCohorts()`, **When** executed, **Then** it generates the hospitalization and readmission cohort table and signals the migration path to `addInpatients()`.

---

### Edge Cases

- **Single-day stays**: Stays with `visit_end_date == visit_start_date` or `is.na(visit_end_date)` are treated as 0-day (or 1-day depending on convention, with `difftime = 0`) single-day stays.
- **Multiple transfers in sequence**: 3 or more consecutive transfers (A $\rightarrow$ B $\rightarrow$ C) with overlapping dates collapse into a single overarching episode spanning from the start of A to the end of C.
- **Same admission date with different specialties**: Merged into 1 general hospitalization episode while specialty attributes are preserved.
- **Zero-utilization patients**: Patients without inpatient visits receive 0 across all generated inpatient columns.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `addInpatients()` MUST support collapsing overlapping and contiguous (gap <= 1 day) inpatient visit records by default when `collapseOverlapping = TRUE` (or `countBy = "days"`).
- **FR-002**: In collapsed mode, `inpatient_los_days_*` MUST be calculated as the difference between the minimum start date and maximum end date of each collapsed episode, eliminating double-counted overlapping days.
- **FR-003**: In collapsed mode, `inpatient_admissions_*` MUST count the number of discrete collapsed hospitalization episodes.
- **FR-004**: `readmissions_30d_*` and `readmissions_90d_*` in `addInpatients()` MUST be computed from the discharge date of a collapsed episode to the admission date of the subsequent collapsed episode.
- **FR-005**: Setting `collapseOverlapping = FALSE` (or `countBy = "records"`) MUST preserve row-level uncollapsed record counting for auditing purposes.
- **FR-006**: `addVisits()` MUST pass `collapseOverlapping` and `countBy` through to `addInpatients()`.
- **FR-007**: `CohortEconomics::extract_hcru()` MUST incorporate inpatient episode collapsing for `inpatient_admissions` and `inpatient_los_days`.
- **FR-008**: `computeHospitalizationCohorts()` MUST signal a lifecycle notice encouraging `addInpatients()` for HCRU characterization while continuing to generate valid cohort tables.

### Key Entities

- **`Inpatient Episode`**: A consolidated, continuous period of hospitalization formed by merging overlapping and contiguous `visit_occurrence` inpatient records for a given patient.
- **`Readmission Episode`**: An inpatient episode commencing within 30 (or 90) days following the discharge date of a prior collapsed inpatient episode.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of overlapping and contiguous inpatient records for a patient are collapsed into discrete episodes when `collapseOverlapping = TRUE`.
- **SC-002**: Elimination of 100% of false readmissions caused by internal ward transfers.
- **SC-003**: 100% test pass rate across all monorepo test suites (`CohortUtilisation`, `CohortCosts`, `CohortEconomics`, `omopHeor`).
- **SC-004**: `R CMD check --no-manual --as-cran` passes with 0 Errors and 0 Warnings.

---

## Assumptions

- Stays with a discharge date matching the next admission date (gap = 0 days) or separated by 1 calendar day (gap = 1 day) represent continuous hospital episodes (e.g. overnight transfer).
- Direct medical costing in `CohortCosts::addCosts()` remains unaffected and exhaustive at the financial record level.
