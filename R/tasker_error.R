#' Create standardized tasker error with consistent formatting
#' @param message Error message
#' @param context Additional context about where error occurred
#' @param call Whether to include call information
#' @keywords internal
tasker_error <- function(message, context = NULL, call = FALSE) {
  full_message <- if (!is.null(context)) {
    sprintf("[tasker:%s] %s", context, message)
  } else {
    sprintf("[tasker] %s", message)
  }
  stop(full_message, call. = call)
}
