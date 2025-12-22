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


#' Get active (running) tasks
#'
#' @param conn Database connection (optional)
#' @return Data frame with active tasks
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


#' Get all stages
#'
#' @param conn Database connection (optional)
#' @return Data frame with stages
#' @export
get_stages <- function(conn = NULL) {
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
    paste0(schema, ".stages")
  } else {
    "stages"
  }
  
  tryCatch({
    DBI::dbGetQuery(
      conn,
      sprintf("SELECT * FROM %s 
               ORDER BY stage_order, stage_name", table_ref)
    )
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}


#' Get all tasks (alias for get_task_status)
#'
#' @param ... Arguments passed to get_task_status
#' @return Data frame with task status
#' @export
#'
#' @examples
#' \dontrun{
#' get_tasks()
#' }
get_tasks <- function(...) {
  get_task_status(...)
}


#' Get task execution history
#'
#' @param stage Stage name (optional)
#' @param task Task name (optional)
#' @param limit Maximum number of results (default: 100)
#' @param conn Database connection (optional)
#' @return Data frame with task execution history
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
