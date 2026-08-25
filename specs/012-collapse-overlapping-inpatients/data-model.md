# Data Model: Collapse Overlapping Inpatient Stays in `addInpatients`

**Feature Branch**: `012-collapse-overlapping-inpatients`  
**Date**: 2026-08-25  
**Spec**: [spec.md](./spec.md)

---

## 1. Entities & Schema Transformations

### 1.1 Input Records (`visit_occurrence`)
Records filtered by inpatient concepts (`c(9201L, 8717L, 581379L)`) or ICU concepts (`32037L`) with provider specialty mapping.

| Attribute | Type | Description |
| :--- | :--- | :--- |
| `person_id` | Integer | Patient ID linked to cohort `subject_id`. |
| `visit_start_date` | Date | Admission date of individual visit record. |
| `visit_end_date` | Date | Discharge date of individual visit record (imputed with start date if NA). |
| `is_icu` | Logical | TRUE if `visit_concept_id` or provider specialty indicates ICU. |
| `specialty_concept_id` | Integer | Medical specialty of attending physician. |

---

### 1.2 Intermediate Collapsed Episode Entity

| Attribute | Type | Description |
| :--- | :--- | :--- |
| `subject_id` | Integer | Patient identifier. |
| `episode_id` | Integer | Sequential identifier for discrete, non-overlapping hospitalization. |
| `episode_start` | Date | $\min(\text{visit\_start\_date})$ within the collapsed episode. |
| `episode_end` | Date | $\max(\text{visit\_end\_date})$ within the collapsed episode. |
| `episode_los` | Numeric | $\max(0, \text{episode\_end} - \text{episode\_start})$. |
| `has_icu` | Logical | TRUE if any sub-stay in the episode involved ICU care. |
| `icu_los` | Numeric | Cumulative ICU days spent during this episode. |
| `is_spec_{name}` | Logical | TRUE if any sub-stay involved the designated specialty. |
| `readm_30` | Integer | 1 if this episode started within 30 days of prior episode's discharge date. |
| `readm_90` | Integer | 1 if this episode started within 90 days of prior episode's discharge date. |

---

### 1.3 Output Metrics Appended to Study Cohort Table

| Column Name | Type | Definition in Collapsed Mode (`collapseOverlapping = TRUE`) |
| :--- | :--- | :--- |
| `inpatient_admissions_{win}` | Integer | Count of discrete collapsed hospitalization episodes in window. |
| `inpatient_los_days_{win}` | Numeric | Sum of non-overlapping length of stay across collapsed episodes. |
| `inpatient_mean_los_days_{win}` | Numeric | Patient-level mean LOS per collapsed admission ($\frac{\text{inpatient\_los\_days}}{\text{inpatient\_admissions}}$). |
| `icu_admissions_{win}` | Integer | Count of ICU admissions in window. |
| `icu_los_days_{win}` | Numeric | Total days spent in ICU beds in window. |
| `icu_mean_los_days_{win}` | Numeric | Mean days per ICU admission. |
| `readmissions_30d_{win}` | Integer | Count of collapsed episodes starting $\le 30$ days after prior collapsed discharge. |
| `readmissions_90d_{win}` | Integer | Count of collapsed episodes starting $\le 90$ days after prior collapsed discharge. |
| `{specialty}_inpatient_admissions_{win}` | Integer | Count of collapsed episodes involving the specified medical specialty. |
