#' Estimate task completion time using Poisson distribution
#'
#' Analyzes progress snapshots to estimate completion time with 95% confidence intervals
#' using Poisson distribution modeling and gamma-based confidence intervals.
#'
#' @param progress_history_env Environment containing progress snapshot history
#' @param run_id Task run ID
#' @param subtask_number Subtask number (1-based)
#' @param quiet Suppress debug messages (default: FALSE)
#' @return List with eta, confidence_interval, confidence level, rate, and items_remaining,
#'   or NULL if insufficient data
#' @export
#' @examples
#' \dontrun{
#' env <- new.env()
#' # ... collect progress snapshots ...
#' estimate <- get_completion_estimate(env, "run_123", 1)
#' }
get_completion_estimate <- function(progress_history_env, run_id, subtask_number, quiet = FALSE) {
  # Build storage key
  run_key <- paste0("run_", run_id)
  subtask_key <- paste0("subtask_", subtask_number)
  storage_key <- paste0(run_key, "_", subtask_key)
  
  # Get history from environment
  history_list <- if (exists(storage_key, envir = progress_history_env)) {
    get(storage_key, envir = progress_history_env)
  } else {
    NULL
  }
  
  # Debug output
  if (!quiet) {
    history_length <- if (is.null(history_list)) 0 else length(history_list)
    message("DEBUG: get_completion_estimate for ", run_key, " ", subtask_key, 
            " - history length: ", history_length)
  }
  
  if (is.null(history_list) || length(history_list) < 3) {
    return(NULL)
  }
  
  # Get snapshots from most recent 50 entries (or all if less)
  recent_snapshots <- tail(history_list, 50)
  
  # Calculate progress rates between consecutive snapshots
  rates <- c()
  for (i in 2:length(recent_snapshots)) {
    prev_snapshot <- recent_snapshots[[i-1]]
    curr_snapshot <- recent_snapshots[[i]]
    
    time_diff <- as.numeric(difftime(curr_snapshot$timestamp, prev_snapshot$timestamp, units = "secs"))
    items_diff <- curr_snapshot$items_complete - prev_snapshot$items_complete
    
    if (time_diff > 0 && items_diff >= 0) {
      rate <- items_diff / time_diff  # items per second
      if (rate > 0) {
        rates <- c(rates, rate)
      }
    }
  }
  
  if (length(rates) == 0) {
    if (!quiet) message("DEBUG: No valid rates calculated - returning NULL")
    return(NULL)
  }

  if (!quiet) message("DEBUG: Calculated ", length(rates), " rates, lambda = ", mean(rates))
  
  # Calculate lambda (average rate) for Poisson distribution
  lambda_estimate <- mean(rates)
  
  # Determine confidence level based on data quality
  confidence <- if (length(rates) >= 10) "high" else if (length(rates) >= 5) "medium" else "low"
  
  # Get current status
  current_snapshot <- tail(recent_snapshots, 1)[[1]]
  items_remaining <- current_snapshot$items_total - current_snapshot$items_complete
  
  # Return NULL if no items remaining (task complete) or invalid rate
  if (items_remaining < 0 || lambda_estimate <= 0) {
    if (!quiet) message("DEBUG: Invalid state - items_remaining: ", items_remaining, ", lambda: ", lambda_estimate)
    return(NULL)
  }
  
  # If no items remaining, return immediate completion
  if (items_remaining == 0) {
    return(list(
      eta = 0,
      confidence_interval = c(0, 0),
      confidence = confidence,
      rate = lambda_estimate,
      items_remaining = 0
    ))
  }

  if (!quiet) message("DEBUG: Computing estimate - items_remaining: ", items_remaining, ", ETA: ", items_remaining / lambda_estimate, " seconds")
  
  # Expected time = items_remaining / lambda_estimate
  eta_seconds <- items_remaining / lambda_estimate
  
  # Use gamma distribution for confidence intervals
  # For Poisson rate estimation, use gamma distribution with shape = items_remaining, rate = lambda_estimate
  alpha <- 0.05  # 95% confidence interval
  ci_lower_time <- items_remaining / qgamma(1 - alpha/2, shape = items_remaining, rate = lambda_estimate)
  ci_upper_time <- items_remaining / qgamma(alpha/2, shape = items_remaining, rate = lambda_estimate)
  
  return(list(
    eta = eta_seconds,
    confidence_interval = c(ci_lower_time, ci_upper_time),
    confidence = confidence,
    rate = lambda_estimate,
    items_remaining = items_remaining
  ))
}

#' Format completion estimate with confidence interval for display
#' @param estimate List returned from get_completion_estimate()
#' @param quiet Suppress debug messages (default: TRUE)
#' @return Character string with formatted estimate and confidence interval
#' @export
format_completion_with_ci <- function(estimate, quiet = TRUE) {
  if (is.null(estimate)) {
    if (!quiet) message("DEBUG: format_completion_with_ci called with NULL estimate")
    return("Computing...")
  }
  
  if (!quiet) message("DEBUG: Formatting estimate with ETA: ", estimate$eta, " seconds")
  
  eta_str <- format_duration_seconds(estimate$eta)
  ci_lower_str <- format_duration_seconds(estimate$confidence_interval[1])
  ci_upper_str <- format_duration_seconds(estimate$confidence_interval[2])
  
  # Confidence indicator: ● (high), ◐ (medium), ○ (low)
  indicator <- switch(estimate$confidence,
                      "high" = "●",
                      "medium" = "◐", 
                      "low" = "○",
                      "○")
  
  return(paste0(eta_str, " ", indicator, " (95% CI: ", ci_lower_str, " - ", ci_upper_str, ")"))
}

#' Format duration from seconds to human readable format
#' @param seconds Number of seconds
#' @return Character string with formatted duration
#' @export
format_duration_seconds <- function(seconds) {
  if (is.na(seconds) || is.null(seconds) || seconds <= 0) {
    return("0s")
  }
  
  days <- floor(seconds / 86400)
  hours <- floor((seconds %% 86400) / 3600)
  minutes <- floor((seconds %% 3600) / 60)
  secs <- floor(seconds %% 60)
  
  if (days > 0) {
    if (hours > 0) {
      return(paste0(days, "d ", hours, "h"))
    } else {
      return(paste0(days, "d"))
    }
  } else if (hours > 0) {
    if (minutes > 0) {
      return(paste0(hours, "h ", minutes, "m"))
    } else {
      return(paste0(hours, "h"))
    }
  } else if (minutes > 0) {
    return(paste0(minutes, "m"))
  } else {
    return(paste0(secs, "s"))
  }
}
