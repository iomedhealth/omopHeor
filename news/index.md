# Changelog

## omopHeor 0.7.1

### New Features & Enhancements

- **Inpatient Overlapping & Contiguous Stay Collapsing**:
  - [`CohortUtilisation::addInpatients()`](https://rdrr.io/pkg/CohortUtilisation/man/addInpatients.html):
    Integrated interval collapsing (`cummax` + `gap <= 1 day`) when
    `collapseOverlapping = TRUE` (default), merging intra-hospital
    department transfers and contiguous admissions into discrete
    hospitalization episodes without double-counting LOS days or
    generating false readmissions.
  - [`CohortUtilisation::computeHospitalizationCohorts()`](https://rdrr.io/pkg/CohortUtilisation/man/compute_hospitalization_cohorts.html):
    Added lifecycle guidance pointing users to
    [`addInpatients()`](https://rdrr.io/pkg/CohortUtilisation/man/addInpatients.html)
    for in-database HCRU characterization.

------------------------------------------------------------------------

## omopHeor 0.7.0

### New Features & Enhancements

- **Same-Day & Overlapping Visit Deduplication for HCRU**:
  - [`CohortUtilisation::addOutpatientVisits()`](https://rdrr.io/pkg/CohortUtilisation/man/addOutpatientVisits.html):
    Added `countBy = c("days", "records")` (default: `"days"`) and
    `collapseOverlapping = TRUE` to count distinct calendar visit dates
    and eliminate administrative duplicate record overestimation.
  - [`CohortUtilisation::addEmergencyCare()`](https://rdrr.io/pkg/CohortUtilisation/man/addEmergencyCare.html):
    Collapses same-day emergency encounters and overlapping care spans
    by default into distinct emergency presentations.
  - [`CohortUtilisation::addVisits()`](https://rdrr.io/pkg/CohortUtilisation/man/addVisits.html):
    Propagates `countBy` and `collapseOverlapping` across Inpatient,
    Outpatient, and Emergency care settings in a single call.
  - [`CohortEconomics::extract_hcru()`](https://rdrr.io/pkg/CohortEconomics/man/extract_hcru.html):
    Harmonized to calculate distinct visit dates in
    `study$hcru$patient_summary` and `study$hcru$outpatient` while
    keeping `study$costs` and `total_cost` 100% exhaustive at the
    financial event level.
  - Specialty-stratified deduplication: Outpatient visits calculate
    distinct dates per specialty independently while maintaining
    distinct global outpatient visit day totals.

------------------------------------------------------------------------

## omopHeor 0.6.0

### CRAN Readiness & Metapackage Renaming

- **Metapackage Renamed to `omopHeor`**:
  - Renamed umbrella metapackage from `hermes` to `omopHeor` to
    eliminate namespace collision with existing Bioconductor package
    (`hermes` for RNA-Seq QC).
  - Dynamic startup hook updated to display `omopHeor` version and
    attached packages upon
    [`library(omopHeor)`](https://iomedhealth.github.io/omopHeor/).
  - Verified 100% namespace availability across CRAN and Bioconductor.
- **CRAN Policy & Package Footprint Compliance**:
  - **`CohortCosts` Size Reduction**: Removed 46.2 MB of static catalog
    files from `inst/extdata/` to keep package archive \< 50 KB (well
    within CRAN’s \< 5 MB limit).
  - **Dependency Sanitization**: Purged `Remotes:` and GitHub-only
    packages (`Cohort2Trajectory`, `TrajectoryMarkovAnalysis`) across
    all `DESCRIPTION` files.
  - **Acronym Expansion**: Expanded all domain acronyms on first mention
    in all `DESCRIPTION` files (OMOP, CDM, HCRU, HEOR, CEA) and wrapped
    software package names in single quotes.
  - **Import Standardization**: Fixed `dbplyr`, `dplyr`, and `rlang`
    imports to eliminate unused namespace NOTEs on `R CMD check`.
  - **Canonical URLs**: Updated repository and website links to
    canonical HTTPS without 301 redirects (`https://www.iomed.health/`,
    `https://github.com/iomedhealth/hermes/issues`).

------------------------------------------------------------------------
