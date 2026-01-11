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
