# Research & Technical Design Decisions: Configurable Episode Gap Threshold (`gapDays`)

## Overview

This document details the architectural decisions, collapsing mathematics, validation rules, and interface specifications for exposing the configurable `gapDays` parameter across `CohortUtilisation` and `CohortEconomics`.

---

## Decision 1: Parameter Naming, Defaults, and Alias Strategy

### Context
DARWIN EU / `omopgenerics` functions use `lowerCamelCase` for arguments (e.g. `gapDays`), while older or sister functions in the ecosystem may use `collapseGap`, `gap_days`, or `collapse_gap`.

### Decision
1. In `CohortUtilisation`:
   - Primary argument: `gapDays = 1L`.
   - Optional alias parameter: `collapseGap = NULL`.
   - If both are provided, `gapDays` takes precedence, with fallback to `collapseGap`.
2. In `CohortEconomics::extract_hcru()`:
   - Primary argument: `gap_days = 1L` (matching existing snake_case convention in `CohortEconomics` such as `count_by`, `baseline_window`).
   - Optional alias parameter: `gapDays = NULL`.
3. Default value is strictly `1L` across all entry points, preserving exact backward-compatible behavior.

### Rationale
- Adheres to DARWIN EU standards (`lowerCamelCase` in `CohortUtilisation`, `snake_case` in `CohortEconomics`).
- Enables zero-breakage upgrades for existing scripts while giving users flexible naming choices.

### Alternatives Considered
- *Single name only without aliases*: Rejected because `computeInfusionCohorts` and earlier specs used `collapseGap`, and users frequently switch between camelCase and snake_case.

---

## Decision 2: Mathematical Logic for Interval Collapsing

### Context
Given a series of hospitalization records for a patient ordered by `visit_start_date` and `visit_end_date`:
Let $S_i$ be the admission date (`visit_start_date`) of record $i$, and $E_i$ be the discharge date (`visit_end_date` or `visit_start_date` if NA).
The cumulative maximum discharge date for previous records is $M_{i-1} = \max_{j < i} E_j$.

### Decision
A record $i$ begins a **new episode** if and only if:
$$\text{is\_new\_episode}_i = \begin{cases} 
1 & \text{if } i = 1 \\
1 & \text{if } S_i > M_{i-1} + \text{gapDays} \\
0 & \text{if } S_i \le M_{i-1} + \text{gapDays}
\end{cases}$$

Episodes are assigned via cumulative sum: $\text{episode\_id}_i = \sum_{k=1}^i \text{is\_new\_episode}_k$.

### Concrete Examples
1. **Strict Overlap Only (`gapDays = 0L`)**:
   - Stay 1: `2020-02-01` to `2020-02-05` ($M_1 = \text{2020-02-05}$).
   - Stay 2: `2020-02-05` to `2020-02-10` ($S_2 = \text{2020-02-05} \le M_1 + 0$) $\rightarrow$ **Merged** (same-day transition).
   - Stay 3: `2020-02-06` to `2020-02-10` ($S_3 = \text{2020-02-06} > M_1 + 0$) $\rightarrow$ **New Episode** (next calendar day).
2. **Standard 1-Day Transfer (`gapDays = 1L`)** (Default):
   - Stay 1: `2020-02-01` to `2020-02-05` ($M_1 = \text{2020-02-05}$).
   - Stay 2: `2020-02-06` to `2020-02-10` ($S_2 = \text{2020-02-06} \le M_1 + 1$) $\rightarrow$ **Merged** (overnight transfer within 24h / 1 day).
   - Stay 3: `2020-02-07` to `2020-02-10` ($S_3 = \text{2020-02-07} > M_1 + 1$) $\rightarrow$ **New Episode** (2-day gap).
3. **Multi-Day Washout (`gapDays = N`)**:
   - Stays with gap $S_i - M_{i-1} \le N$ are merged into a single episode spanning $[\min S, \max E]$.

### Rationale
- Uses standard vectorizable and dbplyr-compatible SQL window primitives (`cummax`, `lag`, `cumsum`).
- Provides uniform, mathematically sound behavior from DuckDB to PostgreSQL, SQL Server, and Snowflake.

---

## Decision 3: Interaction with `collapseOverlapping` and `countBy`

### Decision
1. When `collapseOverlapping = TRUE` (or `countBy = "days"`):
   - Interval collapsing is executed using the configured `gapDays`.
   - `inpatient_admissions` counts the number of distinct collapsed episodes.
   - `inpatient_los_days` is $\sum (\text{episode\_end} - \text{episode\_start})$ across collapsed episodes.
   - Readmissions are evaluated between distinct collapsed episodes.
2. When `collapseOverlapping = FALSE` (or `countBy = "records"`):
   - `gapDays` is ignored.
   - Every raw database row is treated as an independent record.

### Rationale
- Prevents ambiguity between record-level counting and interval-collapsed episode counting.

---

## Decision 4: Validation Strategy (`validateGapDays`)

### Decision
Create a centralized internal validator in `packages/CohortUtilisation/R/utilities.R`:
```r
validateGapDays <- function(gapDays = 1L, collapseGap = NULL, call = parent.frame()) {
  val <- if (!is.null(collapseGap)) collapseGap else gapDays
  if (is.null(val) || !is.numeric(val) || length(val) != 1 || is.na(val)) {
    cli::cli_abort("Argument 'gapDays' must be a single non-negative integer.", call = call)
  }
  int_val <- as.integer(val)
  if (int_val < 0 || int_val != val) {
    cli::cli_abort("Argument 'gapDays' must be a single non-negative integer (>= 0).", call = call)
  }
  int_val
}
```

### Rationale
- Immediate defensive checks fail fast with clear, actionable error messages before executing any database queries.

---

## Decision 5: Readmission Calculation on Collapsed Episodes

### Decision
After collapsing stays into discrete episodes ($k = 1, \dots, K$ for a given subject):
- Inter-episode gap: $\text{gap}_k = \text{start}_k - \text{end}_{k-1}$.
- By definition of distinct episodes, $\text{gap}_k > \text{gapDays}$.
- If $0 \le \text{gap}_k \le 30$, flag as 30-day readmission (`readm_30 = 1L`).
- If $0 \le \text{gap}_k \le 90$, flag as 90-day readmission (`readm_90 = 1L`).

### Rationale
- Guarantees transfers within the `gapDays` window are never misclassified as readmissions.
