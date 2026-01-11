#' Get active (running) tasks
#'
#' @param conn Database connection (optional)
#' @return Data frame with active tasks
#'
#' @seealso [get_task_status()] to query all task statuses with filtering,
#'   [get_task_history()] to view execution history, [task_start()] to start
#'   tracking a task
#'
#' @export
#'
#' @examples
#' \dontrun{
#' get_active_tasks()
#' }
get_active_tasks <- function(conn = NULL) {
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
    paste0(schema, ".active_tasks")
  } else {
    "active_tasks"
  }
  
  tryCatch({
    DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s", table_ref))
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
