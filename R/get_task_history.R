#' Get task execution history
#'
#' @param stage Stage name (optional)
#' @param task Task name (optional)
#' @param limit Maximum number of results (default: 100)
#' @param conn Database connection (optional)
#' @return Data frame with task execution history
#'
#' @seealso [get_task_status()] to view current status, [get_active_tasks()]
#'   to see running tasks, [get_subtask_progress()] to view subtask details
#'   for a run
#'
#' @export
get_task_history <- function(stage = NULL, task = NULL, limit = 100, conn = NULL) {
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
    where_clauses <- c(where_clauses, "s.stage_name = ?")
    params <- c(params, list(stage))
  }
  
  if (!is.null(task)) {
    where_clauses <- c(where_clauses, "t.task_name = ?")
    params <- c(params, list(task))
  }
  
  where_sql <- if (length(where_clauses) > 0) {
    paste("WHERE", paste(where_clauses, collapse = " AND "))
  } else {
    ""
  }
  
  if (nchar(schema) > 0) {
    sql <- sprintf(
      "SELECT tr.run_id, s.stage_name, t.task_name, t.task_type,
              tr.hostname, tr.process_id, tr.status,
              tr.start_time, tr.end_time, tr.last_update,
              tr.total_subtasks, tr.current_subtask,
              tr.overall_percent_complete, tr.overall_progress_message,
              tr.error_message
       FROM %s.task_runs tr
       JOIN %s.tasks t ON tr.task_id = t.task_id
       JOIN %s.stages s ON t.stage_id = s.stage_id
       %s
       ORDER BY tr.start_time DESC
       LIMIT %d",
      schema, schema, schema, where_sql, as.integer(limit)
    )
  } else {
    sql <- sprintf(
      "SELECT tr.run_id, s.stage_name, t.task_name, t.task_type,
              tr.hostname, tr.process_id, tr.status,
              tr.start_time, tr.end_time, tr.last_update,
              tr.total_subtasks, tr.current_subtask,
              tr.overall_percent_complete, tr.overall_progress_message,
              tr.error_message
       FROM task_runs tr
       JOIN tasks t ON tr.task_id = t.task_id
       JOIN stages s ON t.stage_id = s.stage_id
       %s
       ORDER BY tr.start_time DESC
       LIMIT %d",
      where_sql, as.integer(limit)
    )
  }
  
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
