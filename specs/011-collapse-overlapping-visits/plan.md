# Implementation Plan: Collapse Overlapping and Same-Day Visits in HCRU Enrichers

**Branch**: `011-collapse-overlapping-visits` | **Date**: 2026-08-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-collapse-overlapping-visits/spec.md`

## Summary

Implement same-day visit deduplication and overlapping encounter collapsing in `CohortUtilisation` (`addOutpatientVisits`, `addEmergencyCare`, `addVisits`) and `CohortEconomics` (`extract_hcru`). Introduce a configurable `countBy = c("days", "records")` / `collapseOverlapping = TRUE` parameter (defaulting to `"days"` / `TRUE`) to count distinct calendar visit dates/episodes while preserving exhaustive financial line item extraction in `CohortCosts::addCosts`.

---

## Technical Context

**Language/Version**: R >= 4.1.0 (base pipe `|>`, assignment `<-`, lowerCamelCase functions).

**Primary Dependencies**: `CohortUtilisation`, `CohortCosts`, `CohortEconomics`, `CDMConnector` (>= 1.4.0), `omopgenerics` (>= 0.3.0), `dplyr` (>= 1.1.0), `dbplyr` (>= 2.4.0).

**Storage**: In-memory DuckDB for unit tests and synthetic benchmarking; OMOP CDM v5.3 / v5.4 relational backends.

**Testing**: `testthat` (edition 3) across all subpackages and root metapackage.

**Target Platform**: Linux, macOS, Windows (CRAN compliant).

**Project Type**: Monorepo R package ecosystem (`omopHeor`).

**Performance Goals**: < 250ms for distinct day aggregations on 100k visit records in DuckDB.

**Constraints**: `R CMD check --as-cran` with 0 errors and 0 warnings; exact preservation of existing output column names (`{setting}_visits_{window_name}`).

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **I. Zero Wheel-Reinvention**: Leverages standard `omopgenerics` cohort structures and `dplyr`/`dbplyr` database primitives.
- [x] **II. Standardized OMOP CDM & COST Integration**: Never alters OMOP CDM tables; queries `visit_occurrence` and `provider` read-only; preserves 100% exhaustive cost mapping in `CohortCosts`.
- [x] **III. Pipeable S3 Architecture**: Uses base R pipe `|>`, assignment `<-`, lowerCamelCase exported function names (`countBy`, `collapseOverlapping`), snake_case database columns.
- [x] **IV. Test-First & Coverage**: Unit tests added for same-day deduplication, multi-specialty encounters, and record-level fallback.
- [x] **V. 6-Stage Analytical Pipeline Alignment**: Directly enhances Stage 2 (Descriptive Baseline & HCRU Characterization) without disrupting Stage 3-6 downstream inputs.

---

## Project Structure

### Documentation (this feature)

```text
specs/011-collapse-overlapping-visits/
├── spec.md              # Feature specification
├── plan.md              # Implementation plan
├── research.md          # Technical research and design decisions
├── data-model.md        # Entities, schemas, and aggregation rules
├── quickstart.md        # Runnable verification guide
├── contracts/           # API contracts for enrichers
│   └── visit-collapsing-api.md
├── checklists/          # Validation checklists
│   └── requirements.md
└── tasks.md             # Task breakdown (created by /speckit.tasks)
```

### Source Code

```text
packages/CohortUtilisation/
├── R/
│   ├── addOutpatientVisits.R     # Add countBy / collapseOverlapping logic
│   ├── addEmergencyCare.R        # Add countBy / collapseOverlapping logic
│   ├── addVisits.R               # Forward countBy / collapseOverlapping
│   └── utilities.R               # Validation helper for countBy parameter
└── tests/testthat/
    ├── test-add-outpatient.R     # Tests for distinct day vs record counts
    ├── test-add-emergency.R      # Tests for same-day emergency deduplication
    └── test-add-visits.R         # Tests for multi-setting propagation

packages/CohortEconomics/
├── R/
│   └── hcru.R                    # Align extract_hcru() with distinct dates
└── tests/testthat/
    └── test-stage2-hcru.R        # Verify distinct date HCRU extraction

R/
└── mockHERMES.R                  # Add multi-visit fixtures to mockOmopHeor
```

**Structure Decision**: Enhancements are contained within existing modular packages (`CohortUtilisation`, `CohortEconomics`, `omopHeor`), requiring 0 new external dependencies.

---

## Complexity Tracking

> **No violations. Fully compliant with project constitution.**
