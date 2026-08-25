# Implementation Plan: Collapse Overlapping Inpatient Stays in `addInpatients`

**Branch**: `012-collapse-overlapping-inpatients` | **Date**: 2026-08-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/012-collapse-overlapping-inpatients/spec.md`

## Summary

Integrate the interval collapsing algorithm (`cummax` + `gap <= 1 day`) into `CohortUtilisation::addInpatients()` and `CohortEconomics::extract_hcru()` when `collapseOverlapping = TRUE` (default), unifying admission counts, non-overlapping length of stay, and true post-discharge readmissions across the 6-stage HEOR pipeline, while emitting a lifecycle deprecation note in `computeHospitalizationCohorts()`.

---

## Technical Context

**Language/Version**: R >= 4.1.0 (base pipe `|>`, assignment `<-`, lowerCamelCase functions).

**Primary Dependencies**: `CohortUtilisation`, `CohortCosts`, `CohortEconomics`, `CDMConnector` (>= 1.4.0), `omopgenerics` (>= 0.3.0), `dplyr` (>= 1.1.0), `dbplyr` (>= 2.4.0).

**Storage**: In-memory DuckDB and SQL OMOP CDM relational schemas.

**Testing**: `testthat` (edition 3).

**Target Platform**: Linux, macOS, Windows (CRAN compliant).

**Project Type**: Monorepo R package ecosystem (`omopHeor`).

**Performance Goals**: < 200ms for interval collapsing across 50,000 inpatient records in DuckDB.

**Constraints**: Strict backward compatibility in column names (`inpatient_admissions_{win}`, `inpatient_los_days_{win}`, `readmissions_30d_{win}`).

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **I. Zero Wheel-Reinvention**: Leverages standard `omopgenerics` cohort structures and `dplyr`/`dbplyr` database primitives.
- [x] **II. Standardized OMOP CDM & COST Integration**: Never alters OMOP CDM tables; queries `visit_occurrence` and `provider` read-only; preserves 100% exhaustive cost mapping in `CohortCosts`.
- [x] **III. Pipeable S3 Architecture**: Uses base R pipe `|>`, assignment `<-`, lowerCamelCase exported function names (`countBy`, `collapseOverlapping`), snake_case database columns.
- [x] **IV. Test-First & Coverage**: Unit tests added for overlapping stays, contiguous stays, and readmission calculation.
- [x] **V. 6-Stage Analytical Pipeline Alignment**: Directly strengthens Stage 2 (Descriptive Baseline & HCRU Characterization).

---

## Project Structure

### Documentation (this feature)

```text
specs/012-collapse-overlapping-inpatients/
├── spec.md              # Feature specification
├── plan.md              # Implementation plan
├── research.md          # Technical research and design decisions
├── data-model.md        # Entities, schemas, and aggregation rules
├── quickstart.md        # Runnable verification guide
├── contracts/           # API contracts for enrichers
│   └── inpatient-collapsing-api.md
├── checklists/          # Validation checklists
│   └── requirements.md
└── tasks.md             # Task breakdown (created by /speckit.tasks)
```

### Source Code

```text
packages/CohortUtilisation/
├── R/
│   ├── addInpatients.R           # Implement episode collapsing logic
│   ├── hospitalizations.R       # Add lifecycle deprecation notice
│   └── addVisits.R               # Forward collapseOverlapping
└── tests/testthat/
    └── test-add-inpatients.R     # Tests for overlapping & contiguous stays

packages/CohortEconomics/
├── R/
│   └── hcru.R                    # Align inpatient collapsing in extract_hcru()
└── tests/testthat/
    └── test-stage2-hcru.R        # Tests for collapsed admissions & LOS
```

---

## Complexity Tracking

> **No violations. Fully compliant with project constitution.**
