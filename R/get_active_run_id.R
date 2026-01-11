#' Get the active run_id or throw an error
#'
#' @return The active run_id
#' @keywords internal
#' @noRd
get_active_run_id <- function() {
  run_id <- .tasker_env$active_run_id
  if (is.null(run_id)) {
    stop(
      "No active task run context found.\n",
      "Solutions:\n",
      "  1. Call task_start() first (sets context automatically), OR\n",
      "  2. Pass run_id explicitly to this function, OR\n",
      "  3. Set context with tasker_context(run_id)",
      call. = FALSE
    )
  }
  run_id
}
