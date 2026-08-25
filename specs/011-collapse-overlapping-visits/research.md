# Research & Architecture Decisions: Collapse Overlapping and Same-Day Visits in HCRU Enrichers

**Feature Branch**: `011-collapse-overlapping-visits`  
**Date**: 2026-08-25  
**Spec**: [spec.md](./spec.md)

---

## 1. Technical Context & Problem Statement

In OMOP CDM database implementations (especially hospital EHR-derived databases such as those in Spain, US hospital networks, and European academic medical centers), an outpatient encounter or emergency room presentation often generates multiple rows in `visit_occurrence`. 

For example, when a patient visits an Emergency Department or Outpatient Clinic on `2020-03-01`:
- Row 1: `visit_occurrence_id = 101`, `visit_concept_id = 9203` (Emergency Room Visit), `provider_id = 10` (Triage nurse)
- Row 2: `visit_occurrence_id = 102`, `visit_concept_id = 9203` (Emergency Room Visit), `provider_id = 25` (Attending physician)
- Row 3: `visit_occurrence_id = 103`, `visit_concept_id = 9203` (Observation bed), `provider_id = NULL`

If an enricher counts rows directly (`sum(ifelse(...))` or `n()`), the patient is reported as having **3 emergency visits** in that year instead of **1 distinct emergency department presentation**. This severely distorts baseline HCRU summary tables, overestimates healthcare utilization, and misrepresents patient burden.

---

## 2. Architectural Decisions & Alternatives

### Decision 1: Default to Counting Distinct Visit Days (`countBy = "days"`)
* **Decision**: All visit enrichers (`addOutpatientVisits()`, `addEmergencyCare()`, `addVisits()`) will introduce a parameter `countBy = c("days", "records")` (or `collapseOverlapping = TRUE`) with `"days"` / `TRUE` as the default.
* **Rationale**:
  1. Conforms to clinical epidemiology and HEOR standard practice (e.g. ISPOR HCRU guidelines, DARWIN EU conventions).
  2. Preserves database portability across DuckDB, Postgres, SQL Server, and BigQuery using `dplyr::n_distinct()` / SQL `COUNT(DISTINCT visit_start_date)` or distinct filtering.
  3. Seamlessly backwards compatible: output column names remain `{setting}_visits_{window}`.
* **Alternatives Considered**:
  - *Full episode clustering for outpatient visits (analogous to `compute_hospitalization_cohorts`)*: Rejected as default for outpatient visits because outpatient visits are primarily single-day discrete events. Deduplicating by `visit_start_date` achieves the exact outcome with $O(N)$ efficiency.
  - *Deprecating row counts entirely*: Rejected because researchers performing data quality audits or micro-activity studies occasionally need raw record counts. Providing `countBy = "records"` satisfies both needs.

---

### Decision 2: Specialty Stratification Deduplication Logic
* **Decision**: 
  - For specialty-specific counts (`{specialty}_visits_*`): Count distinct visit start dates *within that specialty*.
  - For global specialist outpatient visits (`specialist_visits_*`): Count distinct visit start dates across all non-GP specialist visits.
  - For general outpatient visits (`gp_visits_*`): Count distinct visit start dates for GP visits.
* **Rationale**: If a patient visits both Cardiology and Endocrinology on the same date, they completed 1 Cardiology consultation and 1 Endocrinology consultation (so `cardiology_visits = 1`, `endocrinology_visits = 1`), but attended the hospital on 1 distinct outpatient specialist day (`specialist_visits = 1`).
* **Alternatives Considered**:
  - *Requiring specialty sum to equal total specialist visits*: Mathematically invalid when multidisciplinary same-day visits occur. Counting distinct dates per domain independently preserves clinical validity.

---

### Decision 3: Separation of HCRU Visit Counting and Direct Medical Cost Extraction
* **Decision**: `CohortCosts::addCosts()` remains strictly event-level and exhaustive, summing all `total_paid` / `total_charge` lines linked to `cost_event_id`. `CohortEconomics::extract_hcru()` uses distinct visit days for HCRU tables (`hcru$inpatient`, `hcru$outpatient`, `hcru$patient_summary`) and exhaustive sums for `costs` and `total_cost`.
* **Rationale**: Costing and resource counting answer two different HEOR questions:
  - *HCRU*: "How many times did the patient contact the healthcare system?" $\rightarrow$ **Distinct Visit Days / Episodes**.
  - *Costing*: "What was the total monetary expenditure of all care delivered?" $\rightarrow$ **Exhaustive Financial Record Sum**.

---

## 3. SQL & `dbplyr` Query Patterns

### Pattern A: Distinct Visit Day Aggregation in `CohortUtilisation`
```r
# Deduplicated aggregation per subject and window
win_summary <- win_events |>
  dplyr::group_by(.data$subject_id) |>
  dplyr::summarise(
    ed_cnt = if (countBy == "days") {
      dplyr::n_distinct(.data$visit_start_date[.data$is_ed], na.rm = TRUE)
    } else {
      sum(ifelse(.data$is_ed, 1L, 0L), na.rm = TRUE)
    },
    gp_cnt = if (countBy == "days") {
      dplyr::n_distinct(.data$visit_start_date[.data$is_gp], na.rm = TRUE)
    } else {
      sum(ifelse(.data$is_gp, 1L, 0L), na.rm = TRUE)
    },
    spec_cnt = if (countBy == "days") {
      dplyr::n_distinct(.data$visit_start_date[.data$is_spec], na.rm = TRUE)
    } else {
      sum(ifelse(.data$is_spec, 1L, 0L), na.rm = TRUE)
    },
    ...
  )
```

In DuckDB / memory tibble processing:
```r
# For each subject and setting, filter where condition is TRUE, then compute n_distinct(visit_start_date)
```

---

## 4. Dependencies & Constraints

- **R Version**: R >= 4.1.0 (base pipe `|>`, assignment `<-`).
- **Packages**: `CohortUtilisation`, `CohortCosts`, `CohortEconomics`, `omopgenerics`, `dplyr`, `dbplyr`.
- **Target Performance**: Distinct day aggregation over 100,000 visit records in < 250ms on DuckDB.
