#' Get subtask progress for a task run
#'
#' @param run_id Run ID
#' @param conn Database connection (optional)
#' 
#' @return Data frame with subtask progress containing the following columns:
#' \describe{
#'   \item{progress_id}{Unique identifier for the subtask progress record}
#'   \item{run_id}{Task run ID}
#'   \item{subtask_number}{Subtask sequence number (1-based)}
#'   \item{subtask_name}{Name/description of the subtask}
#'   \item{status}{Current status (STARTED, RUNNING, COMPLETED, FAILED)}
#'   \item{start_time}{Timestamp when subtask started}
#'   \item{end_time}{Timestamp when subtask ended (NULL if still running)}
#'   \item{last_update}{Timestamp of last progress update}
#'   \item{overall_percent_complete}{Completion percentage (0-100)}
#'   \item{overall_progress_message}{Current progress message}
#'   \item{items_total}{Total number of items to process}
#'   \item{items_complete}{Number of items completed}
#'   \item{error_message}{Error message if status is FAILED}
#' }
#' @export
#'
#' @examples
#' \dontrun{
#' get_subtask_progress(run_id)
#' }
get_subtask_progress <- function(run_id, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  schema <- if (driver == "postgresql") config$database$schema else ""
  
  table_ref <- if (nchar(schema) > 0) {
    paste0(schema, ".subtask_progress")
  } else {
    "subtask_progress"
  }
  
  tryCatch({
    DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT progress_id, run_id, subtask_number, subtask_name,
                             status, start_time, end_time, last_update,
                             percent_complete, progress_message,
                             items_total::INTEGER as items_total,
                             items_complete::INTEGER as items_complete,
                             error_message
                      FROM {DBI::SQL(table_ref)} 
                      WHERE run_id = {run_id} 
                      ORDER BY subtask_number", .con = conn)
    )
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
