#' Complete a task execution
#'
#' @param message Final message (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @return TRUE on success
#' @export
#'
#' @seealso [task_update()] for updating task progress, [task_start()] to begin a task,
#'   [task_fail()] to mark a task as failed, [task_end()] for generic status updates
#'
#' @examples
#' \dontrun{
#' # With explicit run_id
#' task_complete(message = "All done", run_id = run_id)
#'
#' # With context (run_id optional)
#' task_start("STAGE", "Task")
#' task_complete(message = "All done")
#' }
task_complete <- function(message = NULL, quiet = FALSE, conn = NULL, run_id = NULL) {
  # Resolve run_id if needed
  if (is.null(run_id)) {
    run_id <- get_active_run_id()
  }
  
  result <- task_update(status = "COMPLETED", overall_percent = 100,
                        message = message, quiet = quiet, conn = conn, run_id = run_id)
  
  # Close and remove the connection for this run_id
  close_connection(run_id)
  
  result
}
