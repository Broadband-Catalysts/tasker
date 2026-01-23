#' Create and display a tasker log message
#'
#' Internal helper function to format and display consistent log messages across
#' tasker functions. Uses numeric identifiers (stage.task or stage.task.subtask)
#' for concise output with fixed-width fields for easy scanning.
#'
#' Format: [timestamp] script_name │ ID EVENT │ message
#' - Script name: 20 chars (left-aligned, truncated with ... if needed)
#' - Numeric ID: 7 chars (right-aligned, supports up to 99.99.99)
#' - Event type: 8 chars (left-aligned, color-coded if crayon available)
#'
#' @param event_type Event type (e.g., "START", "COMPLETE", "FAILED", "UPDATE")
#' @param stage_order Stage order number (optional)
#' @param task_order Task order number (optional)
#' @param subtask_number Subtask number (optional)
#' @param message Additional message text (optional)
#' @param script_filename Script filename (optional, auto-detected if NULL)
#' @param quiet Suppress message output (default: FALSE)
#' @param use_color Use color coding for event types (default: TRUE if crayon available)
#'
#' @return Formatted log message string (invisibly)
#' @keywords internal
#' @noRd
tasker_log_message <- function(event_type,
                               stage_order = NULL,
                               task_order = NULL,
                               subtask_number = NULL,
                               message = NULL,
                               script_filename = NULL,
                               quiet = FALSE,
                               use_color = NULL) {
  if (quiet) {
    return(invisible(NULL))
  }
  
  # Check if crayon is available for color support
  has_crayon <- requireNamespace("crayon", quietly = TRUE)
  if (is.null(use_color)) {
    use_color <- has_crayon
  }
  
  # Build timestamp
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  # Build numeric identifier (stage.task or stage.task.subtask)
  numeric_id <- ""
  if (!is.null(stage_order) && !is.null(task_order)) {
    if (!is.null(subtask_number) && !is.na(subtask_number)) {
      numeric_id <- sprintf("%d.%d.%d", stage_order, task_order, subtask_number)
    } else {
      numeric_id <- sprintf("%d.%d", stage_order, task_order)
    }
  } else if (!is.null(task_order)) {
    # If we only have task_order (shouldn't happen but handle gracefully)
    numeric_id <- sprintf("?.%d", task_order)
  }
  
  # Get script filename if not provided
  if (is.null(script_filename)) {
    script_filename <- tryCatch({
      get_script_filename()
    }, error = function(e) NULL)
  }
  
  # Format script name (20 chars, left-aligned, truncated with ... if needed)
  script_display <- ""
  if (!is.null(script_filename) && !is.na(script_filename) && nchar(script_filename) > 0) {
    script_name <- basename(script_filename)
    if (nchar(script_name) > 20) {
      script_display <- sprintf("%-20s", paste0(substr(script_name, 1, 17), "..."))
    } else {
      script_display <- sprintf("%-20s", script_name)
    }
  } else {
    script_display <- sprintf("%-20s", "(unknown)")
  }
  
  # Format numeric ID (7 chars, right-aligned)
  id_display <- sprintf("%7s", numeric_id)
  
  # Format event type (8 chars, left-aligned) with optional color
  event_display <- sprintf("%-8s", event_type)
  if (use_color && has_crayon) {
    event_display <- switch(
      event_type,
      "START" = crayon::green(event_display),
      "COMPLETE" = crayon::blue(event_display),
      "FAILED" = crayon::red(event_display),
      "UPDATE" = crayon::yellow(event_display),
      "MARKED COMPLETE" = crayon::cyan(event_display),
      event_display  # No color for unknown types
    )
  }
  
  # Build log message: [timestamp] script │ ID EVENT │ message
  log_message <- sprintf("[%s] %s │%s %s", 
                         timestamp, 
                         script_display, 
                         id_display, 
                         event_display)
  
  # Add message if provided
  if (!is.null(message) && !is.na(message) && nchar(trimws(message)) > 0) {
    log_message <- paste(log_message, "│", message)
  }
  
  # Output the message
  message(log_message)
  
  invisible(log_message)
}
