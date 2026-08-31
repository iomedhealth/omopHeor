#' Simulate Economic Outcomes (Stage 5: Economic Simulation)
#'
#' @description
#' `simulate_economics()` runs a Probabilistic Sensitivity Analysis (PSA) using a
#' Markov state-transition model.
#'
#' CEA rarely relies on single deterministic values due to inherent uncertainty in
#' clinical data. This function runs thousands of simulations (samples). In each sample,
#' it draws transition probabilities, costs, and health utility values from statistical
#' distributions (Dirichlet, Gamma, Beta). It then projects these values over a specified
#' time horizon to estimate the total long-term costs and Quality-Adjusted Life-Years
#' (QALYs) for both the target and comparator strategies.
#'
#' @param traj_obj An `omopheor_trajectories` (`hermes_trajectories`) object containing transition and cost data.
#' @param time_horizon Numeric. The time horizon for the simulation in years (e.g., 10 for a 10-year model, or ~80 for a lifetime horizon). Default is 10.
#' @param discount_rate Numeric. The annual discount rate applied to future costs and QALYs to reflect time preference. Default is 0.03 (3%).
#' @param n_samples Integer. The number of probabilistic iterations (PSA samples) to run. Default is 100.
#'
#' @return An `omopheor_sim` (`hermes_sim`) object containing the simulated total costs and QALYs across all samples.
#'
#' @export
simulate_economics <- function(traj_obj, time_horizon = 10, discount_rate = 0.03, n_samples = 100) {
  # ==============================================================================
  # Probabilistic Sensitivity Analysis (PSA) Markov Simulation Engine
  # ==============================================================================
  #
  #  PSA Sampling & Markov Cycle Rollout:
  #
  #   For sample s in 1..n_samples:
  #     1. Draw State Costs from Gamma(shape, scale)
  #     2. Draw State Utilities from Beta(alpha, beta)
  #     3. Draw Transition Matrices via Row-Wise Dirichlet Sampling
  #     4. For strategy in c(Target, Comparator):
  #          Initialize state trace: current_state = [1, 0] (Start at State_Baseline)
  #          For cycle t in 1..n_cycles:
  #            current_state = current_state %*% s_trans
  #            Discount factor d_t = (1 + discount_rate)^(-t * cycle_length)
  #            Accumulate cycle costs:   current_state . s_costs * d_t
  #            Accumulate cycle QALYs:   current_state . s_utils * (cycle_length / 365.25) * d_t
  #
  #   Outputs: Total Discounted Costs & QALYs per strategy across all PSA iterations.
  # ==============================================================================

  n_cycles <- round(time_horizon * (365.25 / 30)) # 30-day cycles

  if (length(traj_obj$matrices) == 0 || is.null(traj_obj$costs) || nrow(traj_obj$costs) == 0) {
    stop("Cannot run economic simulation: empty transition matrices or cost summaries in traj_obj. Ensure Stage 3 (PS) and Stage 4 (Trajectories) completed successfully.")
  }

  strategies <- names(traj_obj$matrices)
  if (is.null(strategies)) strategies <- paste0("Strategy_", 1:length(traj_obj$matrices))
  n_strategies <- length(strategies)

  # Determine discrete Markov health state space
  if (length(traj_obj$matrices) > 0 && !is.null(rownames(traj_obj$matrices[[1]]))) {
    states <- rownames(traj_obj$matrices[[1]])
  } else if (!is.null(traj_obj$costs$health_state)) {
    states <- unique(traj_obj$costs$health_state)
  } else {
    states <- c("State_Baseline", "State_Outcome")
  }
  n_states <- length(states)

  # Pre-allocate results containers
  res_costs <- data.frame(sample = integer(), strategy_id = integer(), costs = numeric())
  res_qalys <- data.frame(sample = integer(), strategy_id = integer(), qalys = numeric())

  # Step 1: Fit method of moments for Gamma distribution on health state costs
  cost_means <- numeric(n_states)
  cost_ses <- numeric(n_states)
  for (i in seq_along(states)) {
    idx <- which(traj_obj$costs$health_state == states[i])
    if (length(idx) > 0) {
      cost_means[i] <- traj_obj$costs$mean_cost[idx[1]]
      cost_ses[i] <- traj_obj$costs$se_cost[idx[1]]
    } else {
      cost_means[i] <- 0
      cost_ses[i] <- 0
    }
  }

  cost_shape <- ifelse(cost_ses > 0, (cost_means / cost_ses)^2, NA)
  cost_scale <- ifelse(cost_ses > 0, (cost_ses^2) / cost_means, NA)

  # Step 2: Configure state utility values and Beta priors
  if (is.null(traj_obj$utilities) || nrow(traj_obj$utilities) == 0) {
    util_df <- data.frame(
      health_state = states,
      mean_utility = ifelse(states == "State_Baseline", 0.85, 0.70),
      se_utility = 0.05
    )
  } else {
    util_df <- traj_obj$utilities
  }

  # Helper: method of moments for Beta distribution on health utilities
  get_beta_params <- function(mu, se) {
    if (is.na(se) || se == 0) {
      return(list(a = NA, b = NA))
    }
    var <- se^2
    tmp <- (mu * (1 - mu) / var) - 1
    if (tmp <= 0) {
      return(list(a = NA, b = NA))
    }
    list(a = mu * tmp, b = (1 - mu) * tmp)
  }

  # Step 3: Compute continuous annual discount factor per cycle
  discount_vec <- 1 / ((1 + discount_rate)^((1:n_cycles) * (30 / 365.25)))

  # Step 4: Run Monte Carlo PSA simulation iterations
  for (s in 1:n_samples) {
    # Draw sample costs from Gamma distributions
    s_costs <- numeric(n_states)
    for (i in 1:n_states) {
      if (is.na(cost_shape[i])) {
        s_costs[i] <- cost_means[i]
      } else {
        s_costs[i] <- stats::rgamma(1, shape = cost_shape[i], scale = cost_scale[i])
      }
    }

    # Draw sample utilities from Beta distributions
    s_utils <- numeric(n_states)
    for (i in 1:n_states) {
      bp <- get_beta_params(util_df$mean_utility[i], util_df$se_utility[i])
      if (is.na(bp$a)) {
        s_utils[i] <- util_df$mean_utility[i]
      } else {
        s_utils[i] <- stats::rbeta(1, bp$a, bp$b)
      }
    }

    # Step 5: Simulate each strategy over defined Markov cycles
    for (strat_idx in 1:n_strategies) {
      trans_mat <- traj_obj$matrices[[strategies[strat_idx]]]

      # Sample transition matrix (Dirichlet via Gamma draws)
      s_trans <- trans_mat
      for (r in 1:nrow(s_trans)) {
        alphas <- s_trans[r, ] * 100
        alphas[alphas == 0] <- 0.001
        g_draws <- stats::rgamma(length(alphas), shape = alphas, scale = 1)
        s_trans[r, ] <- g_draws / sum(g_draws)
      }

      state_dist <- matrix(0, nrow = n_cycles, ncol = n_states)
      current_state <- c(1, rep(0, n_states - 1)) # Start in Baseline state

      total_cost <- 0
      total_qaly <- 0

      for (cycle in 1:n_cycles) {
        current_state <- current_state %*% s_trans
        state_dist[cycle, ] <- current_state

        cycle_cost <- sum(current_state * s_costs) * discount_vec[cycle]
        cycle_qaly <- sum(current_state * s_utils) * (30 / 365.25) * discount_vec[cycle]

        total_cost <- total_cost + cycle_cost
        total_qaly <- total_qaly + cycle_qaly
      }

      res_costs <- rbind(res_costs, data.frame(sample = s, strategy_id = strat_idx, costs = total_cost))
      res_qalys <- rbind(res_qalys, data.frame(sample = s, strategy_id = strat_idx, qalys = total_qaly))
    }
  }

  # Step 6: Package results into hermes_sim S3 container
  new_omopheor_sim(
    list(
      traj_obj = traj_obj,
      time_horizon = time_horizon,
      discount_rate = discount_rate,
      hesim_ce = list(
        costs = res_costs,
        qalys = res_qalys
      )
    )
  )
}
