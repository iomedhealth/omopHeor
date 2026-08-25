# omopHeor 0.7.1

## New Features & Enhancements

* **Inpatient Overlapping & Contiguous Stay Collapsing**:
  * `CohortUtilisation::addInpatients()`: Integrated interval collapsing (`cummax` + `gap <= 1 day`) when `collapseOverlapping = TRUE` (default), merging intra-hospital department transfers and contiguous admissions into discrete hospitalization episodes without double-counting LOS days or generating false readmissions.
  * `CohortUtilisation::computeHospitalizationCohorts()`: Added lifecycle guidance pointing users to `addInpatients()` for in-database HCRU characterization.

---

# omopHeor 0.7.0

## New Features & Enhancements

* **Same-Day & Overlapping Visit Deduplication for HCRU**:
  * `CohortUtilisation::addOutpatientVisits()`: Added `countBy = c("days", "records")` (default: `"days"`) and `collapseOverlapping = TRUE` to count distinct calendar visit dates and eliminate administrative duplicate record overestimation.
  * `CohortUtilisation::addEmergencyCare()`: Collapses same-day emergency encounters and overlapping care spans by default into distinct emergency presentations.
  * `CohortUtilisation::addVisits()`: Propagates `countBy` and `collapseOverlapping` across Inpatient, Outpatient, and Emergency care settings in a single call.
  * `CohortEconomics::extract_hcru()`: Harmonized to calculate distinct visit dates in `study$hcru$patient_summary` and `study$hcru$outpatient` while keeping `study$costs` and `total_cost` 100% exhaustive at the financial event level.
  * Specialty-stratified deduplication: Outpatient visits calculate distinct dates per specialty independently while maintaining distinct global outpatient visit day totals.

---

# omopHeor 0.6.0

## CRAN Readiness & Metapackage Renaming

* **Metapackage Renamed to `omopHeor`**:
  * Renamed umbrella metapackage from `hermes` to `omopHeor` to eliminate namespace collision with existing Bioconductor package (`hermes` for RNA-Seq QC).
  * Dynamic startup hook updated to display `omopHeor` version and attached packages upon `library(omopHeor)`.
  * Verified 100% namespace availability across CRAN and Bioconductor.

* **CRAN Policy & Package Footprint Compliance**:
  * **`CohortCosts` Size Reduction**: Removed 46.2 MB of static catalog files from `inst/extdata/` to keep package archive < 50 KB (well within CRAN's < 5 MB limit).
  * **Dependency Sanitization**: Purged `Remotes:` and GitHub-only packages (`Cohort2Trajectory`, `TrajectoryMarkovAnalysis`) across all `DESCRIPTION` files.
  * **Acronym Expansion**: Expanded all domain acronyms on first mention in all `DESCRIPTION` files (OMOP, CDM, HCRU, HEOR, CEA) and wrapped software package names in single quotes.
  * **Import Standardization**: Fixed `dbplyr`, `dplyr`, and `rlang` imports to eliminate unused namespace NOTEs on `R CMD check`.
  * **Canonical URLs**: Updated repository and website links to canonical HTTPS without 301 redirects (`https://www.iomed.health/`, `https://github.com/iomedhealth/hermes/issues`).

---

# HERMES 0.5.0

## Major Architecture & Modularization Update

* **Monorepo Architecture with 3 Standalone DARWIN EU Domain Packages**:
  * **`CohortUtilisation` (`packages/CohortUtilisation`)**: Lightweight, standalone package for Healthcare Resource Utilization (HCRU) extraction (`addInpatients`, `addEmergencyCare`, `addOutpatientVisits`, `addVisits`, `addPrescriptions`, `addProcedures`, `computeHospitalizationCohorts`, `computeInfusionCohorts`, `summariseUtilization`, `tableUtilization`, `plotUtilization`) with 0 heavy simulation dependencies.
  * **`CohortCosts` (`packages/CohortCosts`)**: Dedicated direct medical costs and health economics costing package (`addCosts`, `summariseCosts`, `tableCosts`, `plotCosts`, Spanish unit cost tariffs & health price indices).
  * **`CohortEconomics` (`packages/CohortEconomics`)**: Comprehensive health economics modeling package for causal propensity scores, longitudinal health-state trajectories, Markov microsimulations, and Cost-Effectiveness Analysis (CEA) (`init`, `fit_ps`, `compile_trajectories`, `simulate_economics`, `run_cea`).

* **`hermes` Umbrella Metapackage**:
  * Root `hermes` metapackage allows single-command installation (`pak::pkg_install("iomedhealth/hermes")`).
  * Dynamic `.onAttach()` hook displays a tidyverse-style startup banner and attaches all three domain namespaces.
  * Re-exports all analytical verbs for frictionless scripting.
  * Unified `_pkgdown.yml` documentation website catalog.

---

# HERMES 0.4.0

## Bug Fixes & Improvements

* **Open-Ended & Infinite Window Normalization**:
  * `validateWindow()` now seamlessly normalizes `Inf`, `-Inf`, and `NA` boundaries (`c(0, Inf)`, `c(0, NA)`, `c(-Inf, 0)`, `c(-Inf, Inf)`).
  * Enforced 100% lowercase `snake_case` column suffixes (`0_to_inf`, `minf_to_0`, `minf_to_inf`), preventing SQL database case-folding mismatch errors during table registration with `CDMConnector` and `omopgenerics`.
  * Safe date arithmetic and censoring evaluation across all 7 domain enrichers (`addInpatients`, `addEmergencyCare`, `addOutpatientVisits`, `addPrescriptions`, `addProcedures`, `addCosts`, `addVisits`).

* **Interactive Reports**:
  * Updated `reports/duckdb_hcru_report.Rmd` and generated `reports/duckdb_hcru_report.html` validating real-world multi-window and infinite follow-up performance against DuckDB OMOP CDM database.

---

# HERMES 0.3.0

## New Features & Enhancements

* **Renamed Inpatient Enricher (`addInpatients`)**:
  * `addInpatients()` is now the primary DARWIN EU-standard function for inpatient and ICU cohort enrichment, replacing `addHospitalizations()`.
  * `addHospitalizations()` and `addInpatient()` are preserved as fully functional backward-compatible exported aliases.
  * Added `stratifySpecialty = TRUE` and `specialties` parameter to compute specialty-specific inpatient admissions (`{specialty}_inpatient_admissions_*`).

* **Dedicated Emergency Care Enricher (`addEmergencyCare`)**:
  * Added `addEmergencyCare()` (with aliases `addEmergency()` and `addEmergencyVisits()`).
  * Uses dual-criteria detection capturing emergency encounters via OMOP emergency visit concepts (`9203`, `262`, `581478`) **and** Emergency Medicine provider specialty concepts (`38004510`).
  * Supports granular specialty stratification (`{specialty}_emergency_visits_*`).

* **Composite Multi-Setting Enricher (`addVisits`)**:
  * Added `addVisits()` to orchestrate Inpatient, Outpatient, and Emergency care enrichment in a single execution.
  * Supports selective setting filtering (`settings = c("inpatient", "outpatient", "emergency")`) and unified specialty mapping.

---

# HERMES 0.2.0

## Initial Modular HCRU & CEA Release

* Layer 1: Care Episode Constructors (`computeHospitalizationCohorts()`, `computeInfusionCohorts()`).
* Layer 2: In-database cohort enrichers (`addOutpatientVisits()`, `addPrescriptions()`, `addProcedures()`, `addCosts()`).
* Layer 3: Analytical summarisation and reporting (`summariseUtilization()`, `summariseCosts()`, `tableUtilization()`, `tableCosts()`, `plotUtilization()`, `plotCosts()`).
* End-to-end 6-stage analytical pipeline support (Cohorts, Baseline/HCRU, PS Adjustment, Trajectories, Simulation, CEA).
