# Data Model: Collapse Overlapping and Same-Day Visits in HCRU Enrichers

**Feature Branch**: `011-collapse-overlapping-visits`  
**Date**: 2026-08-25  
**Spec**: [spec.md](./spec.md)

---

## 1. Input Entities

### 1.1 Study Cohort Table (`x`)
Standard OMOP CDM cohort table (`cohort_table` S3 class conforming to `omopgenerics`):

| Column Name | Type | Description |
| :--- | :--- | :--- |
| `cohort_definition_id` | Integer | Unique identifier for cohort definition (e.g. 1 = Target, 2 = Comparator). |
| `subject_id` | Integer | Unique patient identifier (`person_id`). |
| `cohort_start_date` | Date | Cohort entry date / index date. |
| `cohort_end_date` | Date | Cohort exit date / censoring date. |

### 1.2 CDM Tables Queried

#### `visit_occurrence`
| Column Name | Type | Description |
| :--- | :--- | :--- |
| `visit_occurrence_id` | Integer | Unique visit identifier. |
| `person_id` | Integer | Patient identifier linked to `subject_id`. |
| `visit_concept_id` | Integer | Standard OMOP concept ID classifying visit domain (e.g., 9201 = Inpatient, 9202 = Outpatient, 9203 = Emergency, 32037 = ICU, 581477 = Office Visit, 581478 = ED Encounter). |
| `visit_start_date` | Date | Date the visit encounter began. |
| `visit_end_date` | Date | Date the visit encounter ended. |
| `provider_id` | Integer | Reference to healthcare provider associated with the visit. |

#### `provider`
| Column Name | Type | Description |
| :--- | :--- | :--- |
| `provider_id` | Integer | Unique provider identifier. |
| `specialty_concept_id` | Integer | OMOP concept ID for medical specialty (e.g., 38004446 = General Practice, 38004510 = Emergency Medicine, 38004453 = Cardiology). |

---

## 2. Output Schema & Metric Definitions

### 2.1 Enriched Cohort Table Schema

Output table preserves all original cohort columns and appends the following windowed metric columns:

| Column Name | Type | Count Mode (`countBy = "days"`) | Count Mode (`countBy = "records"`) |
| :--- | :--- | :--- | :--- |
| `gp_visits_{window}` | Integer | Count of distinct `visit_start_date` values for General Practice visits in window. | Total row count of GP visit records in window. |
| `specialist_visits_{window}` | Integer | Count of distinct `visit_start_date` values for non-GP specialist visits in window. | Total row count of specialist visit records in window. |
| `other_outpatient_visits_{window}` | Integer | Count of distinct `visit_start_date` values for uncategorized outpatient visits. | Total row count of other outpatient records. |
| `{specialty}_visits_{window}` | Integer | Count of distinct `visit_start_date` values for specified specialty in window. | Total row count for specified specialty in window. |
| `emergency_visits_{window}` | Integer | Count of distinct `visit_start_date` values (or collapsed episodes) for emergency care in window. | Total row count of emergency visit records in window. |
| `{specialty}_emergency_visits_{window}` | Integer | Count of distinct emergency visit dates for specified emergency specialty. | Total row count for specified emergency specialty. |

---

## 3. Transformation & Deduplication Rules

1. **Window Filtering**:
   An event is eligible for window $W = [w_{start}, w_{end}]$ anchored at $T_{index} = \text{cohort\_start\_date}$ if:
   $$\text{visit\_start\_date} \ge T_{index} + w_{start} \quad \text{AND} \quad \text{visit\_start\_date} \le \min(T_{index} + w_{end}, T_{censor})$$

2. **Deduplication Grouping (`countBy = "days"`)**:
   - For domain $D$ (e.g. GP, Specialist, Emergency):
     $$\text{Metric}_{subject, W, D} = \left| \{ \text{visit\_start\_date} \mid \text{event} \in D \land \text{event} \in W \} \right|$$
   - Zero-filling: If a patient has no events in window $W$, $\text{Metric}_{subject, W, D} = 0$.

3. **Specialty Independence**:
   - If a subject has a visit on `2020-05-01` with `specialty = Cardiology` and another visit on `2020-05-01` with `specialty = Oncology`:
     - $\text{cardiology\_visits} \leftarrow \text{cardiology\_visits} + 1$
     - $\text{oncology\_visits} \leftarrow \text{oncology\_visits} + 1$
     - $\text{specialist\_visits} \leftarrow \text{specialist\_visits} + 1$ (distinct date across all specialist visits)
