# Implementation Plan: Configurable Episode Gap Threshold (`gapDays`) in Inpatient & Visit Utilization

**Branch**: `013-configurable-gap-days` | **Date**: 2026-08-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-configurable-gap-days/spec.md`

---

## Summary

Expose a user-configurable `gapDays = 1L` parameter (with backward-compatible aliases `collapseGap`, `gap_days`, and `collapse_gap`) across `CohortUtilisation::addInpatients()`, `CohortUtilisation::addIcuStays()`, `CohortUtilisation::addVisits()`, `CohortUtilisation::computeHospitalizationCohorts()`, and `CohortEconomics::extract_hcru()`. When `collapseOverlapping = TRUE` (or `countBy = "days"`), hospital stays separated by an admission-to-previous-discharge gap $\le \text{gapDays}$ are merged into unified episodes; when `collapseOverlapping = FALSE`, `gapDays` is ignored and raw rows are counted.

---

## Technical Context

**Language/Version**: R >= 4.1.0 (base pipe `|>`, assignment `<-`, lowerCamelCase functions).

**Primary Dependencies**: `CohortUtilisation`, `CohortCosts`, `CohortEconomics`, `CDMConnector` (>= 1.4.0), `omopgenerics` (>= 0.3.0), `dplyr` (>= 1.1.0), `dbplyr` (>= 2.4.0), `cli` (>= 3.6.0).

**Storage**: In-memory DuckDB and SQL OMOP CDM relational schemas.

**Testing**: `testthat` (edition 3).

**Target Platform**: Linux, macOS, Windows (CRAN compliant).

**Project Type**: Monorepo R package ecosystem (`omopHeor`).

**Performance Goals**: < 150ms for interval collapsing across 50,000 inpatient records in DuckDB.

**Constraints**: Strict backward compatibility for default behaviors (`gapDays = 1L`), column names, and alias support.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **I. Zero Wheel-Reinvention**: Leverages standard `omopgenerics` cohort structures and `dplyr`/`dbplyr` windowing primitives.
- [x] **II. Standardized OMOP CDM & COST Integration**: Operates strictly read-only on OMOP `visit_occurrence` and `provider` tables; maintains exhaustive financial record integrity in `CohortCosts`.
- [x] **III. Pipeable S3 Architecture**: Uses base R pipe `|>`, assignment `<-`, lowerCamelCase arguments (`gapDays`, `collapseGap`), snake_case database columns.
- [x] **IV. Test-First & Coverage**: Unit tests added in `CohortUtilisation` (`test-add-inpatients.R`, `test-add-visits.R`) and `CohortEconomics` (`test-stage2-hcru.R`).
- [x] **V. 6-Stage Analytical Pipeline Alignment**: Directly enhances Stage 2 (Descriptive Baseline & HCRU Characterization) and Stage 4 (State-Cost Extraction).

---

## Project Structure

### Documentation (this feature)

```text
specs/013-configurable-gap-days/
├── spec.md              # Feature specification
├── plan.md              # Implementation plan
├── research.md          # Technical research and design decisions
├── data-model.md        # Entities, schemas, and aggregation rules
├── quickstart.md        # Runnable verification guide
├── contracts/           # API contracts for enrichers and pipeline functions
│   └── configurable-gap-api.md
├── checklists/          # Validation checklists
│   └── requirements.md
└── tasks.md             # Task breakdown (created by /speckit.tasks)
```

### Source Code

```text
packages/CohortUtilisation/
├── R/
│   ├── utilities.R               # Add validateGapDays() validator
│   ├── addInpatients.R           # Add gapDays parameter to addInpatients() & addIcuStays()
│   ├── addVisits.R               # Forward gapDays to addInpatients()
│   └── hospitalizations.R       # Add gapDays/collapseGap to computeHospitalizationCohorts()
├── man/                          # Updated documentation
└── tests/testthat/
    ├── test-add-inpatients.R     # Tests for gapDays = 0L, 1L, NL, and validation
    ├── test-add-visits.R         # Tests for gapDays propagation in addVisits()
    └── test-compute-episodes.R   # Tests for gapDays in computeHospitalizationCohorts()

packages/CohortEconomics/
├── R/
│   └── hcru.R                    # Add gap_days / gapDays to extract_hcru()
├── man/                          # Updated documentation
└── tests/testthat/
    └── test-stage2-hcru.R        # Tests for gap_days in extract_hcru()
```

---

## Complexity Tracking

> **No violations. Fully compliant with project constitution.**
