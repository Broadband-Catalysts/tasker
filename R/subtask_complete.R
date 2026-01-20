#' Mark a subtask as completed
#'
#' Convenience function to mark a subtask as completed with optional message.
#' Sets status to COMPLETED and percent to 100.
#'
#' @param items_completed Total items completed (optional)
#' @param message Completion message (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @param subtask_number Subtask number, or NULL to use current subtask
#' @return TRUE on success
#' @export
#'
#' @seealso [subtask_update()] for updating subtask status with more options,
#'   [subtask_start()] to start tracking a subtask,
#'   [task_complete()] to mark entire task as complete
#'
#' @examples
#' \dontrun{
#' # Old style
#' subtask_complete(items_completed = 100, message = "Processing done",
#'                  run_id = run_id, subtask_number = 1)
#'
#' # New style - use context
#' subtask_complete(message = "Done")
#' }
subtask_complete <- function(items_completed = NULL, message = NULL, 
                            quiet = FALSE, conn = NULL,
                            run_id = NULL, subtask_number = NULL) {
  subtask_update(status = "COMPLETED",
                percent = 100, items_complete = items_completed, 
                message = message, quiet = quiet, conn = conn,
                run_id = run_id, subtask_number = subtask_number)
}
