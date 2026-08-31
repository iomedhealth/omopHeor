# ponytail: minimal cea wrappers

#' Run Cost-Effectiveness Analysis (Stage 6: Decision Analysis)
#'
#' @description
#' `run_cea()` calculates the core metrics of a Cost-Effectiveness Analysis based
#' on the outputs of the economic simulation.
#'
#' It wraps the `BCEA` (Bayesian Cost-Effectiveness Analysis) package to process the
#' matrix of simulated costs and effects (QALYs). The resulting object can be used
#' to compute the Incremental Cost-Effectiveness Ratio (ICER) and Net Monetary
#' Benefit (NMB), and to generate standard HEOR plots.
#'
#' @param sim_obj An `omopheor_sim` (`hermes_sim`) object output by `simulate_economics()`.
#'
#' @return An `omopheor_cea` (`hermes_cea`) object containing the full BCEA results.
#'
#' @export
run_cea <- function(sim_obj) {
  # ==============================================================================
  # Cost-Effectiveness Analysis (Stage 6: Decision Analysis)
  # ==============================================================================
  #
  #  Cost-Effectiveness Plane & Decision Matrix:
  #
  #                    Incremental Cost (\Delta C)
  #                                ^
  #            Quadrant II         |        Quadrant I
  #            (Dominated)         |    (Trade-off: ICER < \lambda)
  #            Higher Cost,        |    Higher Cost,
  #            Fewer QALYs         |    More QALYs
  #                                |
  #        <-----------------------+-----------------------> Incremental QALYs (\Delta E)
  #                                |
  #            Quadrant III        |        Quadrant IV
  #    (Trade-off: Savings)        |        (Dominant)
  #            Lower Cost,         |        Lower Cost,
  #            Fewer QALYs         |        More QALYs
  #                                v
  #
  #  Metrics Derived:
  #    - ICER = \Delta C / \Delta E
  #    - Net Monetary Benefit (NMB) = \lambda * \Delta E - \Delta C
  #    - CEAC Curve: P(NMB > 0 | \lambda = WTP)
  # ==============================================================================

  # Validate simulation object input
  hermes_sim <- sim_obj
  if (is.null(hermes_sim$hesim_ce)) {
    stop("sim_obj must contain a hesim_ce object")
  }

  # Step 1: Reshape simulated PSA sample costs and QALYs into matrix format (sample x strategy)
  c_mat <- unclass(stats::xtabs(costs ~ sample + strategy_id, data = hermes_sim$hesim_ce$costs))
  e_mat <- unclass(stats::xtabs(qalys ~ sample + strategy_id, data = hermes_sim$hesim_ce$qalys))

  # Step 2: Clean up call attributes to prevent BCEA formatting warnings
  attr(c_mat, "call") <- NULL
  attr(e_mat, "call") <- NULL

  # Step 3: Run Bayesian Cost-Effectiveness Analysis via BCEA engine
  bcea_res <- BCEA::bcea(e = e_mat, c = c_mat)

  out <- hermes_sim
  out$cea_results <- bcea_res

  # Step 4: Return enriched hermes_cea object
  new_omopheor_cea(out)
}

#' Plot Cost-Effectiveness Acceptability Curve (CEAC)
#'
#' @description
#' Generates a CEAC plot based on the CEA results. The CEAC shows the probability
#' that an intervention is cost-effective across a range of Willingness-to-Pay (WTP)
#' thresholds. It is a standard way to represent parametric uncertainty in HEOR.
#'
#' \figure{ceac.png}
#'
#' @param study An `omopheor_cea` (`hermes_cea`) object.
#'
#' @return A `ggplot2` object representing the CEAC.
#'
#' @export
plot_ceac <- function(study) BCEA::ceac.plot(study$cea_results)

#' Plot Cost-Effectiveness Plane
#'
#' @description
#' Generates a Cost-Effectiveness Plane scatter plot. The plot shows the difference
#' in effects (Incremental QALYs) on the x-axis and the difference in costs
#' (Incremental Costs) on the y-axis for each PSA sample.
#'
#' \figure{ceplane.png}
#'
#' @param study An `omopheor_cea` (`hermes_cea`) object.
#'
#' @return A `ggplot2` object representing the CE plane.
#'
#' @export
plot_plane <- function(study) BCEA::ceplane.plot(study$cea_results)

#' Summary Table
#'
#' @description
#' Returns a statistical summary table of the CEA results, detailing incremental costs,
#' incremental QALYs, and the ICER.
#'
#' **Example Output:**
#' ```
#' Cost-effectiveness analysis summary
#'
#' Reference intervention: Strategy 1
#' Comparator intervention: Strategy 2
#'
#' Optimal decision: Strategy 2
#'
#'                  Strategy 1  Strategy 2
#' Expected Costs   15000       18000
#' Expected QALYs   12.5        13.1
#'
#' ICER: 5000 / QALY
#' ```
#'
#' @param study An `omopheor_cea` (`hermes_cea`) object
#' @export
table_summary <- function(study) summary(study$cea_results)
