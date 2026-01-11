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
