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
