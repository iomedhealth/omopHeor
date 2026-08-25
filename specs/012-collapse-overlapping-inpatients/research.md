# Research & Architecture Decisions: Collapse Overlapping Inpatient Stays in `addInpatients`

**Feature Branch**: `012-collapse-overlapping-inpatients`  
**Date**: 2026-08-25  
**Spec**: [spec.md](./spec.md)

---

## 1. Problem Statement

In OMOP Common Data Model databases, acute inpatient episodes frequently span multiple rows in `visit_occurrence` due to:
1. **Departmental / Service Transfers**: A patient transferred from Internal Medicine to Cardiology generates two contiguous or overlapping records.
2. **ICU Step-Up / Step-Down**: Transitions between general wards and ICU beds generate separate records with same-day or overlapping timestamps.
3. **Bed movements and administrative re-categorization**: Multiple records sharing the exact same admission span.

When `addInpatients()` counts rows without interval collapsing:
- Hospital admissions are artificially inflated (e.g. 1 10-day hospitalization with 2 transfers counts as 3 admissions).
- Total length of stay (LOS) is double-counted for overlapping calendar days.
- Departmental transfers are falsely identified as "30-day readmissions".

---

## 2. Technical Architecture & Decisions

### Decision 1: Implement Cumulative Maximum Interval Collapsing in `addInpatients`
* **Decision**: When `collapseOverlapping = TRUE` (the default) or `countBy = "days"`, `addInpatients()` will execute an interval-merging algorithm before computing summary metrics.
* **Algorithm**:
  1. For all qualifying inpatient/ICU records for each patient within the temporal window, sort by `visit_start_date` and `end_dt`.
  2. Compute `max_end_so_far = cummax(as.numeric(end_dt))`.
  3. Identify episode boundary: `is_new_episode = (row_number() == 1L | as.numeric(visit_start_date) > lag(max_end_so_far) + 1)`.
  4. Assign `episode_id = cumsum(is_new_episode)`.
  5. Summarize each episode:
     - `episode_start = min(visit_start_date)`
     - `episode_end = max(end_dt)`
     - `episode_los = max(0, difftime(episode_end, episode_start, units = "days"))`
* **Rationale**: This is the exact algorithm used in `computeHospitalizationCohorts()` and ensures that transfers, same-day bed changes, and contiguous 24-hour readmissions collapse into single clinical episodes.

---

### Decision 2: True Post-Discharge Readmission Calculation
* **Decision**: Readmissions (30-day and 90-day) will be calculated on the sequence of *collapsed episodes*:
  $$\text{gap} = \text{difftime}(\text{episode\_start}_{i}, \text{episode\_end}_{i-1}, \text{units} = \text{"days"})$$
  $$\text{readm\_30} = (\text{gap} \ge 0 \land \text{gap} \le 30)$$
  $$\text{readm\_90} = (\text{gap} \ge 0 \land \text{gap} \le 90)$$
* **Rationale**: Eliminates 100% of false-positive readmissions caused by intra-hospital transfers while capturing genuine emergency post-discharge readmissions.

---

### Decision 3: Preserving ICU & Specialty Accounting Within Collapsed Stays
* **Decision**:
  - `inpatient_admissions_*`: Number of collapsed hospitalization episodes (or general ward episodes when ICU is separated).
  - `inpatient_los_days_*`: Cumulative non-overlapping days across collapsed hospitalization episodes.
  - `inpatient_mean_los_days_*`: Ratio $\frac{\text{inpatient\_los\_days}}{\text{inpatient\_admissions}}$.
  - `icu_admissions_*`: Number of ICU stays/episodes.
  - `icu_los_days_*`: Number of days spent in ICU beds.
  - `{specialty}_inpatient_admissions_*`: Number of hospital episodes involving the designated medical specialty.

---

### Decision 4: Lifecycle Deprecation of `computeHospitalizationCohorts`
* **Decision**: `computeHospitalizationCohorts()` remains fully functional for generating standalone cohort tables, but emits an informational lifecycle note directing users to `addInpatients()` for cohort enrichment and HCRU characterization.
* **Rationale**: Avoids breaking legacy scripts while consolidating user guidance around the DARWIN EU `PatientProfiles` enrichment paradigm.
