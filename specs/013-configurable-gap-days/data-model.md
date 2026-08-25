# Data Model: Configurable Episode Gap Threshold (`gapDays`)

## Entities and Schema Definitions

### 1. Inbound Records: OMOP `visit_occurrence`

The raw patient stay events queried from the database:

| Field Name | Type | Description |
|---|---|---|
| `visit_occurrence_id` | Integer | Unique visit identifier |
| `person_id` | Integer | OMOP person identifier |
| `visit_concept_id` | Integer | Standard concept ID for visit type (e.g. 9201, 8717, 32037) |
| `visit_start_date` | Date | Admission date ($S_i$) |
| `visit_end_date` | Date | Discharge date ($E_i$, coalesced to $S_i$ if NA) |
| `provider_id` | Integer | Optional provider reference |

---

### 2. Intermediate Entity: Collapsed Inpatient Episode

Constructed during database windowing / grouping when `collapseOverlapping = TRUE`:

| Field Name | Type | Description |
|---|---|---|
| `subject_id` | Integer | Patient identifier |
| `episode_id` | Integer | Sequential identifier for collapsed episode (1, 2, ...) |
| `ep_start` | Date | Episode start date ($\min(S_i)$ across member stays) |
| `ep_end` | Date | Episode discharge date ($\max(E_i)$ across member stays) |
| `ep_los` | Numeric | Total non-overlapping length of stay in days: $\max(0, \text{difftime}(\text{ep\_end}, \text{ep\_start}))$ |
| `has_inp` | Logical | `TRUE` if episode contains at least one non-ICU inpatient stay |
| `icu_adm_cnt` | Integer | Count of ICU sub-stays embedded in this episode |
| `icu_los_cnt` | Numeric | Total ICU days embedded in this episode |
| `prev_ep_end` | Date | Discharge date of previous collapsed episode |
| `ep_gap` | Numeric | Days between previous discharge and current admission: $\text{ep\_start} - \text{prev\_ep\_end}$ |
| `readm_30` | Integer | `1L` if $0 \le \text{ep\_gap} \le 30$, else `0L` |
| `readm_90` | Integer | `1L` if $0 \le \text{ep\_gap} \le 90$, else `0L` |

---

### 3. Outbound Cohort Columns: Enriched Cohort Table

Final metric columns added to the patient cohort table:

| Column Name Pattern | Type | Description |
|---|---|---|
| `inpatient_admissions_{window}` | Integer | Count of discrete collapsed inpatient episodes in window |
| `inpatient_los_days_{window}` | Numeric | Sum of non-overlapping LOS across collapsed inpatient episodes |
| `inpatient_mean_los_{window}` | Numeric | Mean LOS per admission ($\text{los\_days} / \text{admissions}$) |
| `readmissions_30d_{window}` | Integer | Count of 30-day readmissions between collapsed episodes |
| `readmissions_90d_{window}` | Integer | Count of 90-day readmissions between collapsed episodes |
| `icu_admissions_{window}` | Integer | Count of ICU admissions |
| `icu_los_days_{window}` | Numeric | Total ICU days in window |
| `icu_mean_los_{window}` | Numeric | Mean ICU LOS per ICU admission |

---

## State Transitions & Collapsing Logic

| Scenario | Stay 1 ($S_1 \to E_1$) | Stay 2 ($S_2 \to E_2$) | Gap ($S_2 - E_1$) | `gapDays` | Resulting Episodes |
|---|---|---|---|---|---|
| **Strict Overlap** | 2020-02-01 $\to$ 2020-02-05 | 2020-02-03 $\to$ 2020-02-08 | -2 days | Any ($\ge 0$) | 1 episode: 2020-02-01 $\to$ 2020-02-08 (7 days) |
| **Same-Day Touch** | 2020-02-01 $\to$ 2020-02-05 | 2020-02-05 $\to$ 2020-02-10 | 0 days | `0L` | 1 episode: 2020-02-01 $\to$ 2020-02-10 (9 days) |
| **Next-Day Transfer** | 2020-02-01 $\to$ 2020-02-05 | 2020-02-06 $\to$ 2020-02-10 | 1 day | `0L` | 2 episodes: [Feb 1-5, LOS 4] & [Feb 6-10, LOS 4] |
| **Next-Day Transfer** | 2020-02-01 $\to$ 2020-02-05 | 2020-02-06 $\to$ 2020-02-10 | 1 day | `1L` (Default) | 1 episode: 2020-02-01 $\to$ 2020-02-10 (9 days) |
| **Multi-Day Gap** | 2020-02-01 $\to$ 2020-02-05 | 2020-02-08 $\to$ 2020-02-12 | 3 days | `1L` | 2 episodes: [Feb 1-5, LOS 4] & [Feb 8-12, LOS 4] |
| **Multi-Day Gap** | 2020-02-01 $\to$ 2020-02-05 | 2020-02-08 $\to$ 2020-02-12 | 3 days | `3L` | 1 episode: 2020-02-01 $\to$ 2020-02-12 (11 days) |
| **Uncollapsed Mode** | 2020-02-01 $\to$ 2020-02-05 | 2020-02-03 $\to$ 2020-02-08 | -2 days | `collapseOverlapping = FALSE` | 2 records: [Feb 1-5, LOS 4] & [Feb 3-8, LOS 5] |
