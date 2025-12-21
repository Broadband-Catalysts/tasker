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
  
  config <- getOption("tasker.config")
  schema <- config$database$schema
  
  tryCatch({
    task_id <- DBI::dbGetQuery(
      conn,
      sprintf("SELECT t.task_id FROM %s.tasks t
               JOIN %s.stages s ON t.stage_id = s.stage_id
               WHERE s.stage_name = $1 AND t.task_name = $2",
              schema, schema),
      params = list(stage, task)
    )$task_id
    
    if (length(task_id) == 0) {
      stop("Task '", task, "' in stage '", stage, "' not found. Register it first with register_task()")
    }
    
    run_id <- DBI::dbGetQuery(
      conn,
      sprintf("INSERT INTO %s.task_runs 
               (task_id, hostname, process_id, parent_pid, start_time, 
                status, total_subtasks, overall_progress_message, 
                version, git_commit, user_name)
               VALUES ($1, $2, $3, $4, NOW(), 'STARTED', $5, $6, $7, $8, $9)
               RETURNING run_id", schema),
      params = list(
        task_id,
        Sys.info()["nodename"],
        Sys.getpid(),
        get_parent_pid(),
        total_subtasks,
        message,
        version,
        git_commit,
        Sys.info()["user"]
      )
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
  schema <- config$database$schema
  
  valid_statuses <- c("RUNNING", "COMPLETED", "FAILED", "SKIPPED", "CANCELLED")
  if (!status %in% valid_statuses) {
    stop("Invalid status: ", status, ". Must be one of: ", 
         paste(valid_statuses, collapse = ", "))
  }
  
  tryCatch({
    updates <- c("status = $2")
    params <- list(run_id, status)
    param_num <- 2
    
    if (!is.null(current_subtask)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("current_subtask = $%d", param_num))
      params <- c(params, list(current_subtask))
    }
    
    if (!is.null(overall_percent)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("overall_percent_complete = $%d", param_num))
      params <- c(params, list(overall_percent))
    }
    
    if (!is.null(message)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("overall_progress_message = $%d", param_num))
      params <- c(params, list(message))
    }
    
    if (!is.null(error_message)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("error_message = $%d", param_num))
      params <- c(params, list(error_message))
    }
    
    if (!is.null(error_detail)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("error_detail = $%d", param_num))
      params <- c(params, list(error_detail))
    }
    
    if (status %in% c("COMPLETED", "FAILED", "CANCELLED")) {
      updates <- c(updates, "end_time = NOW()")
    }
    
    sql <- sprintf(
      "UPDATE %s.task_runs SET %s WHERE run_id = $1",
      schema,
      paste(updates, collapse = ", ")
    )
    
    DBI::dbExecute(conn, sql, params = params)
    
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
