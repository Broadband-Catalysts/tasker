#' Start tracking a task execution
#'
#' @param stage Stage name
#' @param task Task name
#' @param total_subtasks Total number of subtasks (optional)
#' @param message Initial progress message (optional)
#' @param version Version string (optional)
#' @param git_commit Git commit hash (optional)
#' @param conn Database connection (optional)
#' @return run_id (UUID) to track this execution
#' @export
#'
#' @examples
#' \dontrun{
#' run_id <- task_start("STATIC", "Process FCC Data")
#' }
task_start <- function(stage, task, total_subtasks = NULL, 
                      message = NULL, version = NULL, 
                      git_commit = NULL, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  tasks_table <- get_table_name("tasks", conn)
  stages_table <- get_table_name("stages", conn)
  task_runs_table <- get_table_name("task_runs", conn)
  
  # Convert NULL to NA for glue_sql
  total_subtasks <- if (is.null(total_subtasks)) NA else total_subtasks
  message <- if (is.null(message)) NA else message
  version <- if (is.null(version)) NA else version
  git_commit <- if (is.null(git_commit)) NA else git_commit
  
  # Determine the current timestamp function based on driver
  config <- getOption("tasker.config")
  time_func <- if (config$database$driver == "sqlite") "datetime('now')" else "NOW()"
  
  tryCatch({
    task_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT t.task_id FROM {tasks_table*} t
               JOIN {stages_table*} s ON t.stage_id = s.stage_id
               WHERE s.stage_name = {stage} AND t.task_name = {task}",
              .con = conn)
    )$task_id
    
    if (length(task_id) == 0) {
      stop("Task '", task, "' in stage '", stage, "' not found. Register it first with register_task()")
    }
    
    hostname <- Sys.info()["nodename"]
    process_id <- Sys.getpid()
    parent_pid <- get_parent_pid()
    user_name <- Sys.info()["user"]
    
    run_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {task_runs_table*} 
               (task_id, hostname, process_id, parent_pid, start_time, 
                status, total_subtasks, overall_progress_message, 
                version, git_commit, user_name)
               VALUES ({task_id}, {hostname}, {process_id}, {parent_pid}, {time_func*}, 
                       'STARTED', {total_subtasks}, {message}, {version},
                       {git_commit}, {user_name})
               RETURNING run_id", .con = conn)
    )$run_id
    
    log_message <- sprintf("[TASK START] %s / %s (run_id: %s)", stage, task, run_id)
    if (!is.null(message)) {
      log_message <- paste0(log_message, " - ", message)
    }
    message(log_message)
    
    run_id
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}


#' Update task execution status
#'
#' @param run_id Run ID from task_start()
#' @param status Status: RUNNING, COMPLETED, FAILED, SKIPPED, CANCELLED
#' @param current_subtask Current subtask number (optional)
#' @param overall_percent Overall percent complete 0-100 (optional)
#' @param message Progress message (optional)
#' @param error_message Error message if failed (optional)
#' @param error_detail Detailed error info (optional)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' task_update(run_id, status = "RUNNING", overall_percent = 50)
#' task_update(run_id, status = "COMPLETED", overall_percent = 100)
#' }
task_update <- function(run_id, status, current_subtask = NULL,
                       overall_percent = NULL, message = NULL,
                       error_message = NULL, error_detail = NULL,
                       conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  task_runs_table <- get_table_name("task_runs", conn)
  db_driver <- config$database$driver
  time_func <- if (db_driver == "sqlite") "datetime('now')" else "NOW()"
  
  valid_statuses <- c("RUNNING", "COMPLETED", "FAILED", "SKIPPED", "CANCELLED")
  if (!status %in% valid_statuses) {
    stop("Invalid status: ", status, ". Must be one of: ", 
         paste(valid_statuses, collapse = ", "))
  }
  
  # Convert NULL to NA for glue_sql
  current_subtask <- if (is.null(current_subtask)) NA else current_subtask
  overall_percent <- if (is.null(overall_percent)) NA else overall_percent
  message <- if (is.null(message)) NA else message
  error_message <- if (is.null(error_message)) NA else error_message
  error_detail <- if (is.null(error_detail)) NA else error_detail
  
  tryCatch({
    # Build UPDATE clause parts
    update_clauses <- c("status = {status}")
    
    if (!is.na(current_subtask)) {
      update_clauses <- c(update_clauses, "current_subtask = {current_subtask}")
    }
    
    if (!is.na(overall_percent)) {
      update_clauses <- c(update_clauses, "overall_percent_complete = {overall_percent}")
    }
    
    if (!is.na(message)) {
      update_clauses <- c(update_clauses, "overall_progress_message = {message}")
    }
    
    if (!is.na(error_message)) {
      update_clauses <- c(update_clauses, "error_message = {error_message}")
    }
    
    if (!is.na(error_detail)) {
      update_clauses <- c(update_clauses, "error_detail = {error_detail}")
    }
    
    if (status %in% c("COMPLETED", "FAILED", "CANCELLED")) {
      update_clauses <- c(update_clauses, paste0("end_time = ", time_func))
    }
    
    update_str <- paste(update_clauses, collapse = ", ")
    sql_template <- paste0("UPDATE {task_runs_table*} SET ", update_str, " WHERE run_id = {run_id}")
    
    DBI::dbExecute(
      conn, 
      glue::glue_sql(sql_template, .con = conn)
    )
    
    log_message <- sprintf("[TASK UPDATE] %s - %s", run_id, status)
    if (!is.null(message)) {
      log_message <- paste0(log_message, ": ", message)
    }
    message(log_message)
    
    TRUE
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}


#' Complete a task execution
#'
#' @param run_id Run ID from task_start()
#' @param message Final message (optional)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
task_complete <- function(run_id, message = NULL, conn = NULL) {
  task_update(run_id, status = "COMPLETED", overall_percent = 100,
              message = message, conn = conn)
}


#' Mark a task execution as failed
#'
#' @param run_id Run ID from task_start()
#' @param error_message Error message
#' @param error_detail Detailed error info (optional)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
task_fail <- function(run_id, error_message, error_detail = NULL, conn = NULL) {
  task_update(run_id, status = "FAILED", 
              error_message = error_message,
              error_detail = error_detail,
              conn = conn)
}


#' End a task execution with specified status
#'
#' Generic function to end a task with any status. For convenience,
#' use task_complete() or task_fail() instead.
#'
#' @param run_id Run ID from task_start()
#' @param status Status: "COMPLETED", "FAILED", "CANCELLED", "SKIPPED"
#' @param message Final message (optional)
#' @param error_message Error message (for FAILED status)
#' @param error_detail Detailed error info (optional)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
task_end <- function(run_id, status, message = NULL, 
                     error_message = NULL, error_detail = NULL, conn = NULL) {
  if (status == "COMPLETED") {
    task_complete(run_id, message = message, conn = conn)
  } else if (status == "FAILED") {
    if (is.null(error_message)) error_message <- "Task failed"
    task_fail(run_id, error_message = error_message, 
              error_detail = error_detail, conn = conn)
  } else {
    task_update(run_id, status = status, message = message,
                error_message = error_message, error_detail = error_detail,
                conn = conn)
  }
}


#' Get parent process ID
#'
#' @return Parent PID or NULL
#' @keywords internal
get_parent_pid <- function() {
  tryCatch({
    if (.Platform$OS.type == "unix") {
      ppid <- system2("ps", c("-o", "ppid=", "-p", Sys.getpid()), 
                      stdout = TRUE, stderr = FALSE)
      as.integer(trimws(ppid))
    } else {
      NULL
    }
  }, error = function(e) NULL)
}
