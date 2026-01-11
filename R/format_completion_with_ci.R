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
