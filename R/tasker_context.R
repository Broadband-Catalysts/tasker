#' Get or set the active task run context
#'
#' This function manages the active run_id context for the current R session.
#' When a run_id is provided, it sets that as the active context. When called
#' without arguments, it returns the currently active run_id.
#'
#' The context allows you to omit the run_id parameter from tasker functions,
#' making code cleaner and less repetitive. This is especially useful in
#' sequential workflows where a single task is being tracked.
#'
#' @param run_id Character UUID of a task run, or NULL to query the current context
#' @return The active run_id (invisibly when setting, visibly when getting)
#' @export
#'
#' @examples
#' \dontrun{
#' # Start a task - it becomes the active context
#' task_start("STAGE", "Task Name")
#'
#' # Check what's active
#' tasker_context()  # Returns the run_id
#'
#' # Explicitly set context (useful for switching between tasks)
#' tasker_context(some_run_id)
#'
#' # Clear context
#' tasker_context(NULL)
#' }
tasker_context <- function(run_id = NULL) {
  if (!missing(run_id)) {
    # Setting context - validate input
    if (!is.null(run_id)) {
      if (!is.character(run_id) || length(run_id) != 1 || nchar(trimws(run_id)) == 0) {
        stop("'run_id' must be a non-empty character string or NULL", call. = FALSE)
      }
      # Basic UUID format validation
      uuid_pattern <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
      if (!grepl(uuid_pattern, run_id, ignore.case = TRUE)) {
        warning("'run_id' does not appear to be a valid UUID format", call. = FALSE)
      }
    }
    .tasker_env$active_run_id <- run_id
    
    # Reset subtask counter when context changes
    if (!is.null(run_id)) {
      .tasker_env$subtask_counter[[run_id]] <- 0
    }
    
    return(invisible(run_id))
  } else {
    # Getting context
    return(.tasker_env$active_run_id)
  }
}
