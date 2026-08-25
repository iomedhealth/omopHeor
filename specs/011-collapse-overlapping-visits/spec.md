# Feature Specification: Collapse Overlapping and Same-Day Visits in HCRU Enrichers

**Feature Branch**: `011-collapse-overlapping-visits`

**Created**: 2026-08-25

**Status**: Draft

**Input**: User description: "collapseOverlapping proposal for outpatient and emergency visits"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Same-Day Outpatient Visit Deduplication (Priority: P1)

As an HEOR/RWE researcher analyzing healthcare resource utilization (HCRU) in OMOP CDM cohorts, I want `addOutpatientVisits()` to count distinct visit dates by default rather than raw administrative database records, so that a patient receiving multiple administrative line items or sub-consultations on the same date is accurately counted as having 1 outpatient visit.

**Why this priority**: In electronic health record (EHR) and claims databases converted to OMOP CDM, a single hospital outpatient visit frequently generates multiple `visit_occurrence` records on the same day (e.g. triage, vitals, nursing assessment, physician consultation). Counting raw rows severely inflates patient visit averages and distorts baseline characterization and HCRU tables.

**Independent Test**: Given a synthetic cohort where a patient has 3 outpatient `visit_occurrence` records on `2020-05-10` and 1 on `2020-06-15` within a 1-year follow-up window, running `addOutpatientVisits()` with default settings produces `gp_visits_followup = 2` (distinct dates) rather than `4`.

**Acceptance Scenarios**:

1. **Given** a cohort subject with multiple outpatient visit records sharing the same start date within an observation window, **When** `addOutpatientVisits()` is executed, **Then** only 1 visit is counted for that date in general practice (`gp_visits_*`), specialist (`specialist_visits_*`), other (`other_outpatient_visits_*`), and emergency metrics.
2. **Given** a cohort subject with outpatient visits occurring on distinct calendar dates, **When** `addOutpatientVisits()` is executed, **Then** all distinct dates are accurately counted.
3. **Given** a cohort subject with zero outpatient visits in the window, **When** `addOutpatientVisits()` is executed, **Then** the output metrics are 0 (zero-filled).

---

### User Story 2 - Same-Day and Overlapping Emergency Visit Deduplication (Priority: P1)

As an HEOR/RWE researcher evaluating acute care utilization, I want `addEmergencyCare()` to collapse same-day and contiguous emergency encounters into distinct emergency presentations, so that emergency visit counts reflect actual hospital emergency department episodes rather than multiple administrative triage and observation records.

**Why this priority**: Emergency department encounters frequently generate multiple visit entries (e.g., emergency room visit record and emergency physician provider record, or multi-day observation). Counting raw records overestimates emergency department utilization frequency.

**Independent Test**: Given a synthetic cohort where a patient has 2 emergency visit records on the same day and a 2-day emergency stay spanning `2020-03-01` to `2020-03-02`, running `addEmergencyCare()` computes 2 distinct emergency episodes instead of 4 raw records.

**Acceptance Scenarios**:

1. **Given** a patient with multiple emergency visit records on the same date, **When** `addEmergencyCare()` is executed with default settings, **Then** `emergency_visits_*` counts 1 visit for that date.
2. **Given** a patient with emergency visit records spanning contiguous days, **When** `addEmergencyCare()` is executed, **Then** overlapping spans are collapsed into a single emergency care episode.
3. **Given** a patient with multiple distinct emergency attendances across different weeks or months, **When** `addEmergencyCare()` is executed, **Then** each distinct presentation date is counted.

---

### User Story 3 - Specialty-Stratified Outpatient Deduplication (Priority: P2)

As a clinical investigator examining multidisciplinary outpatient care, I want specialty-specific outpatient visit metrics (`specialist_visits_*`, `{specialty}_visits_*`) to count distinct dates *per specialty*, while global outpatient metrics reflect total unique visit days.

**Why this priority**: If a patient visits both a Cardiologist and a Pulmonologist on the same calendar day, clinically they had 1 Cardiology consultation and 1 Pulmonology consultation, but spent only 1 day at the hospital for outpatient care overall. Both views must remain logically and epidemiologically sound.

**Independent Test**: Given a patient with 1 Cardiology visit and 1 Oncology visit on `2020-04-10`, running `addOutpatientVisits(stratifySpecialty = TRUE, specialties = list(cardiology = ..., oncology = ...))` yields `cardiology_visits_followup = 1`, `oncology_visits_followup = 1`, and `specialist_visits_followup = 1` (or 2 if specialty-stratified, with distinct day consistency).

**Acceptance Scenarios**:

1. **Given** a patient visiting two different specialties on the same day, **When** `addOutpatientVisits()` is run with `specialties`, **Then** each specialty metric increments by 1 for that date.
2. **Given** a patient visiting the same specialty multiple times on the same date, **When** `addOutpatientVisits()` is run, **Then** that specialty metric increments by only 1 for that date.

---

### User Story 4 - Multi-Setting Harmonization in `addVisits` and `extract_hcru` (Priority: P2)

As a health economist executing the end-to-end 6-stage HEOR pipeline, I want `addVisits()` and `CohortEconomics::extract_hcru()` to adopt distinct visit day counting by default across Inpatient, Outpatient, and Emergency settings, while preserving complete event-level granularity in `CohortCosts::addCosts()`.

**Why this priority**: Ensures total consistency across the modular packages (`CohortUtilisation`, `CohortCosts`, `CohortEconomics`, and metapackage `omopHeor`). HCRU characterization uses unique visits, while costing extracts 100% of event-level expenditures.

**Independent Test**: Running `extract_hcru()` on a study cohort returns `hcru$patient_summary` where `emergency_visits`, `gp_visits`, and `specialist_visits` match distinct visit day counts, while `costs` and `total_cost` retain all linked financial line items from the OMOP `cost` table.

**Acceptance Scenarios**:

1. **Given** an `omopheor_study` with multi-setting encounters, **When** `extract_hcru()` is executed, **Then** HCRU visit counts match distinct visit days while medical cost sums remain exhaustive.
2. **Given** a cohort analyzed with `addVisits()`, **When** executed with default settings, **Then** all settings (inpatient, outpatient, emergency) apply consistent distinct episode/day counting.

---

### User Story 5 - Configurable Count Granularity (`countBy` Parameter) (Priority: P3)

As an advanced health services researcher, I want an optional parameter (e.g. `countBy = c("days", "records")` or `collapseOverlapping = TRUE/FALSE`) so that I can deliberately choose between counting distinct visit days/episodes or raw record-level entries when conducting micro-activity or data quality audits.

**Why this priority**: While distinct visit days is the recommended standard for HCRU, certain database audit studies or micro-costing validations require inspecting raw database record counts.

**Independent Test**: Running `addOutpatientVisits(..., countBy = "records")` returns the uncollapsed row count, while `countBy = "days"` (default) returns the deduplicated visit day count.

**Acceptance Scenarios**:

1. **Given** `countBy = "days"` (default), **When** enrichers run, **Then** same-day entries are collapsed.
2. **Given** `countBy = "records"`, **When** enrichers run, **Then** raw row counts are returned without deduplication.

---

### Edge Cases

- **Same-day multi-provider visits**: A patient attends 2 general practice consultations with different provider IDs on the same date. When `countBy = "days"`, `gp_visits_*` increments by 1.
- **Overlapping date spans in Outpatient/Emergency**: A visit record with `visit_start_date = 2020-01-01` and `visit_end_date = 2020-01-03` overlapping with another record on `2020-01-02` to `2020-01-04`. Collapsing consolidates the span to `2020-01-01` to `2020-01-04`.
- **Visits crossing window boundaries**: A visit starts before the observation window and ends inside it, or starts inside and ends after. The visit is attributed based on `visit_start_date` within `[win_start, win_end]`.
- **Missing or null `visit_end_date`**: Treated as a single-day visit where `visit_end_date = visit_start_date`.
- **Zero-utilization patients**: Patients in the cohort with no records in `visit_occurrence` receive 0 in all generated metric columns.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `addOutpatientVisits()` MUST support deduplicating same-day outpatient visits by default (`collapseOverlapping = TRUE` or `countBy = "days"`), counting distinct calendar dates for `gp_visits_*`, `specialist_visits_*`, and `other_outpatient_visits_*`.
- **FR-002**: `addEmergencyCare()` MUST support deduplicating same-day emergency visits and overlapping emergency stays by default, counting distinct presentation dates/episodes for `emergency_visits_*`.
- **FR-003**: `addVisits()` MUST propagate the distinct visit day counting behavior across all selected settings (`inpatient`, `outpatient`, `emergency`).
- **FR-004**: Specialty stratification in `addOutpatientVisits()` and `addEmergencyCare()` MUST compute distinct visit dates per specialty group when `stratifySpecialty = TRUE` or `specialties` is provided.
- **FR-005**: All visit enrichers MUST provide a parameter (`countBy` with choices `c("days", "records")` or `collapseOverlapping = TRUE/FALSE`) allowing users to choose between deduplicated visit days (default) and raw database record counts.
- **FR-006**: Column naming conventions (`{setting}_visits_{window_name}`, `{specialty}_visits_{window_name}`) MUST remain fully backward compatible with existing downstream reporting tools (`summariseUtilization()`, `tableUtilization()`, `plotUtilization()`).
- **FR-007**: `CohortEconomics::extract_hcru()` MUST align with `CohortUtilisation` visit deduplication, reporting distinct visit days in `study$hcru$patient_summary` and `study$hcru$outpatient`.
- **FR-008**: `CohortCosts::addCosts()` MUST remain strictly event-level and exhaustive, ensuring that financial aggregation captures all cost records linked to visits regardless of visit date deduplication.
- **FR-009**: All existing unit tests across `CohortUtilisation`, `CohortCosts`, `CohortEconomics`, and `omopHeor` MUST continue to pass, with new dedicated unit tests verifying same-day visit collapsing across all enrichers.

### Key Entities

- **`Visit Occurrence`**: OMOP CDM table containing encounter records, with attributes `person_id`, `visit_concept_id`, `visit_start_date`, `visit_end_date`, and `provider_id`.
- **`Unique Visit Day / Episode`**: A distinct calendar date or collapsed continuous period during which a patient had contact with a specific healthcare setting or medical specialty.
- **`Enriched Cohort Table`**: An `omopgenerics` cohort table augmented with integer metric columns representing distinct visit counts per observation window.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of same-day duplicate visit records within a given setting/specialty are deduplicated to 1 visit count when default parameters are used.
- **SC-002**: Zero regression in performance: executing visit enrichment on cohorts of 10,000+ patients executes in under 2 seconds on DuckDB.
- **SC-003**: 100% test pass rate across `CohortUtilisation`, `CohortCosts`, `CohortEconomics`, and `omopHeor` test suites.
- **SC-004**: `R CMD check --no-manual --as-cran` passes with 0 Errors and 0 Warnings across all packages in the monorepo.
- **SC-005**: All documentation and vignettes render cleanly, demonstrating both unique visit day counts and exhaustive cost calculations.

---

## Assumptions

- For outpatient and emergency care, the standard unit of HCRU measurement is the distinct calendar day (`visit_start_date`) or continuous care span, which prevents administrative artifact inflation.
- Micro-costing in `CohortCosts::addCosts()` operates directly on OMOP `COST` records linked by `cost_event_id` and is independent of visit deduplication in `CohortUtilisation`.
- When a patient visits multiple distinct medical specialties on the same day, counting 1 visit per specialty and 1 visit day overall reflects standard clinical and health economics practice.

