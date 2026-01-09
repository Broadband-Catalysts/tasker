#' Internal environment for tasker package state
#'
#' @keywords internal
#' @noRd
.tasker_env <- new.env(parent = emptyenv())

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
    # Setting context
    if (!is.null(run_id) && !is.character(run_id)) {
      stop("run_id must be a character string or NULL", call. = FALSE)
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

#' Get the active run_id or throw an error
#'
#' @return The active run_id
#' @keywords internal
#' @noRd
get_active_run_id <- function() {
  run_id <- .tasker_env$active_run_id
  if (is.null(run_id)) {
    stop(
      "No active task run context.\n",
      "  Either:\n",
      "  1. Call task_start() first (it sets the context automatically), OR\n",
      "  2. Pass run_id explicitly to this function, OR\n",
      "  3. Set context with tasker_context(run_id)",
      call. = FALSE
    )
  }
  run_id
}

#' Get the next subtask number for auto-numbering
#'
#' @param run_id The run_id to get the next subtask for
#' @return Integer subtask number
#' @keywords internal
#' @noRd
get_next_subtask <- function(run_id) {
  # Initialize counter if not exists
  if (is.null(.tasker_env$subtask_counter)) {
    .tasker_env$subtask_counter <- list()
  }
  
  if (is.null(.tasker_env$subtask_counter[[run_id]])) {
    .tasker_env$subtask_counter[[run_id]] <- 0
  }
  
  # Increment and return
  .tasker_env$subtask_counter[[run_id]] <- .tasker_env$subtask_counter[[run_id]] + 1
  .tasker_env$subtask_counter[[run_id]]
}

#' Get the current subtask number (last started)
#'
#' @param run_id The run_id to get the current subtask for
#' @return Integer subtask number, or NULL if no subtasks started
#' @keywords internal
#' @noRd
get_current_subtask <- function(run_id) {
  if (is.null(.tasker_env$subtask_counter) || 
      is.null(.tasker_env$subtask_counter[[run_id]])) {
    return(NULL)
  }
  
  counter <- .tasker_env$subtask_counter[[run_id]]
  if (counter == 0) {
    return(NULL)
  }
  
  return(counter)
}

#' Reset subtask counter for a run
#'
#' @param run_id The run_id to reset
#' @keywords internal
#' @noRd
reset_subtask_counter <- function(run_id) {
  if (!is.null(.tasker_env$subtask_counter)) {
    .tasker_env$subtask_counter[[run_id]] <- 0
  }
}
