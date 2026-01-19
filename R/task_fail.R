#' Mark a task execution as failed
#'
#' @param error_message Error message
#' @param error_detail Detailed error info (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @return TRUE on success
#' @export
#'
#' @seealso [task_update()] for updating task progress, [task_start()] to begin a task,
#'   [task_complete()] to mark a task as complete, [task_end()] for generic status updates
#'
#' @examples
#' \dontrun{
#' # With explicit run_id
#' task_fail(error_message = "Processing failed", run_id = run_id)
#'
#' # With context (run_id optional)
#' task_start("STAGE", "Task")
#' task_fail(error_message = "Something went wrong")
#' }
task_fail <- function(error_message, error_detail = NULL, quiet = FALSE, conn = NULL, run_id = NULL) {
  # Resolve run_id if needed
  if (is.null(run_id)) {
    run_id <- get_active_run_id()
  }
  
  # Get connection from context if available, otherwise create one
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_connection(run_id)
    if (is.null(conn)) {
      conn <- create_connection()
      close_on_exit <- TRUE
    }
  }
  
  # End any active subtasks first
  tryCatch({
    config <- getOption("tasker.config")
    subtask_progress_table <- get_table_name("subtask_progress", conn)
    db_driver <- config$database$driver
    time_func <- if (db_driver == "sqlite") "datetime('now')" else "NOW()"
    
    # Find and fail all active subtasks (not COMPLETED or FAILED)
    active_subtasks_sql <- glue::glue_sql(
      "UPDATE {subtask_progress_table}
       SET status = 'FAILED', 
           end_time = {time_func},
           error_message = 'Task failed - subtask terminated'
       WHERE run_id = {run_id}
         AND status NOT IN ('COMPLETED', 'FAILED')
         AND end_time IS NULL",
      .con = conn
    )
    
    DBI::dbExecute(conn, active_subtasks_sql)
  }, error = function(e) {
    # Don't let subtask cleanup prevent task failure
    warning("Failed to update active subtasks during task failure: ", conditionMessage(e))
  })
  
  # Update the main task status
  result <- task_update(status = "FAILED", 
                        error_message = error_message,
                        error_detail = error_detail,
                        quiet = quiet,
                        conn = conn,
                        run_id = run_id)
  
  # Close connection if we created it
  if (close_on_exit && !is.null(conn) && DBI::dbIsValid(conn)) {
    DBI::dbDisconnect(conn)
  }
  
  # Close and remove the connection for this run_id
  close_connection(run_id)
  
  result
}
