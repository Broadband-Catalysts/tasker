#' Get subtask progress for a task run
#'
#' @param run_id Run ID
#' @param conn Database connection (optional)
#' @return Data frame with subtask progress
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
      sprintf("SELECT * FROM %s 
               WHERE run_id = ? 
               ORDER BY subtask_number", table_ref),
      params = list(run_id)
    )
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
