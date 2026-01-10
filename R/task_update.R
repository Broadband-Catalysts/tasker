#' Update task execution status
#'
#' @param status Status: RUNNING, COMPLETED, FAILED, SKIPPED, CANCELLED
#' @param current_subtask Current subtask number (optional)
#' @param overall_percent Overall percent complete 0-100 (optional)
#' @param message Progress message (optional)
#' @param error_message Error message if failed (optional)
#' @param error_detail Detailed error info (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @return TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' # With explicit run_id
#' task_update(status = "RUNNING", overall_percent = 50, run_id = run_id)
#'
#' # With context (run_id optional)
#' task_start("STAGE", "Task")
#' task_update(status = "RUNNING", overall_percent = 50)
#' }
task_update <- function(status, current_subtask = NULL,
                       overall_percent = NULL, message = NULL,
                       error_message = NULL, error_detail = NULL,
                       quiet = FALSE, conn = NULL, run_id = NULL) {
  ensure_configured()
  
  # Input validation
  if (missing(status) || !is.character(status) || length(status) != 1) {
    stop("'status' must be a single character string", call. = FALSE)
  }
  
  if (!is.null(current_subtask)) {
    if (!is.numeric(current_subtask) || length(current_subtask) != 1 || current_subtask < 1) {
      stop("'current_subtask' must be a positive integer if provided", call. = FALSE)
    }
    current_subtask <- as.integer(current_subtask)
  }
  
  if (!is.null(overall_percent)) {
    if (!is.numeric(overall_percent) || length(overall_percent) != 1 || 
        overall_percent < 0 || overall_percent > 100) {
      stop("'overall_percent' must be a number between 0 and 100 if provided", call. = FALSE)
    }
  }
  
  if (!is.logical(quiet) || length(quiet) != 1) {
    stop("'quiet' must be TRUE or FALSE", call. = FALSE)
  }
  
  # Resolve run_id from context if not provided
  if (is.null(run_id)) {
    run_id <- get_active_run_id()
  }
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  # Ensure cleanup on exit
  on.exit({
    if (close_on_exit && !is.null(conn) && DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
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
    sql_template <- paste0("UPDATE {task_runs_table} SET ", update_str, " WHERE run_id = {run_id}")
    
    DBI::dbExecute(
      conn, 
      glue::glue_sql(sql_template, .con = conn)
    )
    
    if (!quiet) {
      # Get task_order for display
      task_order_info <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT t.task_order FROM {task_runs_table} tr
                 JOIN {`get_table_name('tasks', conn)`} t ON tr.task_id = t.task_id
                 WHERE tr.run_id = {run_id}", .con = conn)
      )
      
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      task_num <- if (nrow(task_order_info) > 0 && !is.na(task_order_info$task_order[1])) {
        paste0("Task ", task_order_info$task_order[1])
      } else {
        "Task"
      }
      log_message <- sprintf("[%s] %s %s | run_id: %s", 
                            timestamp, task_num, status, run_id)
      if (!is.na(message)) {
        log_message <- paste0(log_message, " | ", message)
      }
      message(log_message)
    }
    
    TRUE
    
  }, error = function(e) {
    stop("Failed to update task status: ", conditionMessage(e), call. = FALSE)
  })
}


#' Complete a task execution
#'
#' @param message Final message (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @return TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' # With explicit run_id
#' task_complete(message = "All done", run_id = run_id)
#'
#' # With context (run_id optional)
#' task_start("STAGE", "Task")
#' task_complete(message = "All done")
#' }
task_complete <- function(message = NULL, quiet = FALSE, conn = NULL, run_id = NULL) {
  task_update(status = "COMPLETED", overall_percent = 100,
              message = message, quiet = quiet, conn = conn, run_id = run_id)
}


#' Mark a task execution as failed
#'
#' @param error_message Error message
#' @param error_detail Detailed error info (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @return TRUE on success
#' @export
task_fail <- function(error_message, error_detail = NULL, quiet = FALSE, conn = NULL, run_id = NULL) {
  task_update(status = "FAILED", 
              error_message = error_message,
              error_detail = error_detail,
              quiet = quiet,
              conn = conn,
              run_id = run_id)
}


#' End a task execution with specified status
#'
#' Generic function to end a task with any status. For convenience,
#' use task_complete() or task_fail() instead.
#'
#' @param status Status: "COMPLETED", "FAILED", "CANCELLED", "SKIPPED"
#' @param message Final message (optional)
#' @param error_message Error message (for FAILED status)
#' @param error_detail Detailed error info (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @return TRUE on success
#' @export
task_end <- function(status, message = NULL, 
                     error_message = NULL, error_detail = NULL, quiet = FALSE, conn = NULL, run_id = NULL) {
  if (status == "COMPLETED") {
    task_complete(message = message, quiet = quiet, conn = conn, run_id = run_id)
  } else if (status == "FAILED") {
    if (is.null(error_message)) error_message <- "Task failed"
    task_fail(error_message = error_message, 
              error_detail = error_detail, quiet = quiet, conn = conn, run_id = run_id)
  } else {
    task_update(status = status, message = message,
                error_message = error_message, error_detail = error_detail,
                quiet = quiet, conn = conn, run_id = run_id)
  }
}
