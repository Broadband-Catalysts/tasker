#' Get current task status
#'
#' @param stage Filter by stage (optional)
#' @param task Filter by task name (optional)
#' @param status Filter by status (optional)
#' @param limit Maximum number of results (default: all)
#' @param conn Database connection (optional)
#' @return Data frame with task status
#' @export
#'
#' @examples
#' \dontrun{
#' get_task_status()
#' get_task_status(status = "RUNNING")
#' get_task_status(stage = "DAILY")
#' }
get_task_status <- function(stage = NULL, task = NULL, status = NULL,
                           limit = NULL, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  schema <- if (driver == "postgresql") config$database$schema else ""
  
  where_clauses <- c()
  params <- list()
  
  if (!is.null(stage)) {
    where_clauses <- c(where_clauses, "stage_name = ?")
    params <- c(params, list(stage))
  }
  
  if (!is.null(task)) {
    where_clauses <- c(where_clauses, "task_name = ?")
    params <- c(params, list(task))
  }
  
  if (!is.null(status)) {
    where_clauses <- c(where_clauses, "status = ?")
    params <- c(params, list(status))
  }
  
  where_sql <- if (length(where_clauses) > 0) {
    paste("WHERE", paste(where_clauses, collapse = " AND "))
  } else {
    ""
  }
  
  limit_sql <- if (!is.null(limit)) {
    sprintf("LIMIT %d", as.integer(limit))
  } else {
    ""
  }
  
  table_ref <- if (nchar(schema) > 0) {
    paste0(schema, ".current_task_status")
  } else {
    "current_task_status"
  }
  
  sql <- sprintf(
    "SELECT * FROM %s %s
     ORDER BY stage_order, task_order, start_time DESC
     %s",
    table_ref, where_sql, limit_sql
  )
  
  tryCatch({
    result <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, sql, params = params)
    } else {
      DBI::dbGetQuery(conn, sql)
    }
    
    result
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
