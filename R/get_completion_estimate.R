#' Estimate task completion time with confidence intervals
#'
#' Calculates estimated time to completion using simple linear extrapolation:
#' (elapsed time / items completed) * items remaining. 
#' Provides confidence intervals using normal approximation for the rate estimate.
#'
#' @param progress_history_env Environment containing progress snapshot history
#' @param run_id Task run ID
#' @param subtask_number Subtask number (1-based)
#' @param confidence_level Confidence level for intervals (default: 0.95 for 95% CI)
#' @param quiet Suppress debug messages (default: FALSE)
#' @return List with eta, confidence_interval, confidence level, rate, and items_remaining,
#'   or NULL if insufficient data
#' @export
#' @examples
#' \dontrun{
#' env <- new.env()
#' # ... collect progress snapshots ...
#' estimate <- get_completion_estimate(env, "run_123", 1)
#' estimate_90 <- get_completion_estimate(env, "run_123", 1, confidence_level = 0.90)
#' }
get_completion_estimate <- function(progress_history_env, run_id, subtask_number, confidence_level = 0.95, quiet = FALSE) {
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
  
  if (is.null(history_list) || length(history_list) < 2) {
    return(NULL)
  }
  
  # Get the first and most recent snapshots
  first_snapshot <- history_list[[1]]
  current_snapshot <- tail(history_list, 1)[[1]]
  
  # Calculate elapsed time and items completed
  elapsed_time <- as.numeric(difftime(current_snapshot$timestamp, first_snapshot$timestamp, units = "secs"))
  items_complete <- current_snapshot$items_complete - first_snapshot$items_complete
  items_remaining <- current_snapshot$items_total - current_snapshot$items_complete
  
  # Validate data
  if (elapsed_time <= 0 || items_complete <= 0) {
    if (!quiet) message("DEBUG: No progress detected - elapsed: ", elapsed_time, ", items_complete: ", items_complete)
    return(NULL)
  }
  
  if (items_remaining < 0) {
    if (!quiet) message("DEBUG: Invalid state - items_remaining: ", items_remaining)
    return(NULL)
  }
  
  # If no items remaining, return immediate completion
  if (items_remaining == 0) {
    return(list(
      eta = 0,
      confidence_interval = c(0, 0),
      confidence = "high",
      rate = items_complete / elapsed_time,
      items_remaining = 0
    ))
  }
  
  # Simple estimate: (elapsed / # completed) * # remaining
  eta_seconds <- (elapsed_time / items_complete) * items_remaining
  
  if (!quiet) message("DEBUG: Computing estimate - elapsed: ", elapsed_time, 
                     ", items_complete: ", items_complete, 
                     ", items_remaining: ", items_remaining, 
                     ", ETA: ", eta_seconds, " seconds")
  
  # Calculate confidence intervals using normal approximation
  # For a Poisson process, the rate estimate has variance lambda/t
  # The completion time estimate has variance (items_remaining^2 / lambda^2) * (lambda / elapsed_time)
  lambda_estimate <- items_complete / elapsed_time  # items per second
  
  # Standard error of the rate estimate
  se_lambda <- sqrt(lambda_estimate / elapsed_time)
  
  # Calculate z-score for the specified confidence level
  # For confidence_level, we want the (1 + confidence_level)/2 quantile
  alpha <- 1 - confidence_level
  z_score <- qnorm(1 - alpha/2)
  
  # Confidence interval for lambda (using normal approximation)
  # Lower bound for rate gives upper bound for time
  lambda_lower <- max(lambda_estimate - z_score * se_lambda, 1e-10)  # Prevent division by zero
  lambda_upper <- lambda_estimate + z_score * se_lambda
  
  # Confidence intervals for completion time
  ci_lower_time <- items_remaining / lambda_upper  # Faster rate = less time
  ci_upper_time <- items_remaining / lambda_lower  # Slower rate = more time
  
  # Determine confidence level based on sample size (items completed)
  confidence <- if (items_complete >= 30) "high" else if (items_complete >= 10) "medium" else "low"
  
  return(list(
    eta = eta_seconds,
    confidence_interval = c(ci_lower_time, ci_upper_time),
    confidence = confidence,
    rate = lambda_estimate,
    items_remaining = items_remaining
  ))
}
