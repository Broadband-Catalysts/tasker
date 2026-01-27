#' Update subtask progress
#'
#' @param status Status: RUNNING, COMPLETED, FAILED, SKIPPED. Partial matching
#'   is supported (e.g., "COMPLETE" will match "COMPLETED").
#' @param percent Percent complete 0-100 (optional)
#' @param items_complete Items completed - sets absolute value (optional)
#' @param message Progress message (optional)
#' @param error_message Error message if failed (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @param subtask_number Subtask number, or NULL to use current subtask
#' @return TRUE on success
#'
#' @seealso [subtask_increment()] for atomic counter updates safe for parallel
#'   workers, [subtask_start()] to start tracking a subtask,
#'   [get_subtask_progress()] to query subtask progress,
#'   [subtask_complete()] for convenient completion marking,
#'   [find_and_update_subtask()] to update subtask by searching for it
#'
#' @export
#'
#' @note For parallel workers incrementing counters, use subtask_increment() instead
#'   to avoid race conditions. Related functions subtask_increment and subtask_complete
#'   are now in separate files (subtask_increment.R and subtask_complete.R).
#'
#' @examples
#' \dontrun{
#' # Old style
#' subtask_update(status = "RUNNING", percent = 50, items_complete = 28,
#'                run_id = run_id, subtask_number = 1)
#'
#' # New style - use context
#' subtask_update(status = "RUNNING", percent = 50)
#'
#' # Partial matching works
#' subtask_update(status = "COMPLETED", percent = 100)  # Canonical completion status
#' }
subtask_update <- function(status = c("RUNNING", "COMPLETED", "FAILED", "SKIPPED"),
                          percent = NULL, items_complete = NULL,
                          message = NULL, error_message = NULL,
                          quiet = FALSE, conn = NULL,
                          run_id = NULL, subtask_number = NULL) {
  ensure_configured()
  
  # Validate status parameter with partial matching
  status <- match.arg(status)
  
  if (!is.null(percent)) {
    if (!is.numeric(percent) || length(percent) != 1 || percent < 0 || percent > 100) {
      stop("'percent' must be a number between 0 and 100 if provided", call. = FALSE)
    }
  }
  
  if (!is.null(items_complete)) {
    if (!is.numeric(items_complete) || length(items_complete) != 1 || items_complete < 0) {
      stop("'items_complete' must be a non-negative number if provided", call. = FALSE)
    }
    items_complete <- as.integer(items_complete)
  }
  
  if (!is.logical(quiet) || length(quiet) != 1) {
    stop("'quiet' must be TRUE or FALSE", call. = FALSE)
  }
  
  # Resolve run_id from context if not provided
  if (is.null(run_id)) {
    run_id <- get_active_run_id()
  }
  
  # Resolve subtask_number from current subtask if not provided
  if (is.null(subtask_number)) {
    subtask_number <- get_current_subtask(run_id)
    if (is.null(subtask_number)) {
      stop("No subtask currently active. Either pass subtask_number explicitly or start a subtask first.",
           call. = FALSE)
    }
  }
  
  # Get connection from context if available, otherwise create one
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_connection(run_id)
    if (is.null(conn)) {
      conn <- get_db_connection()
      close_on_exit <- TRUE
    }
  }
  
  config <- getOption("tasker.config")
  subtask_progress_table <- get_table_name("subtask_progress", conn)
  db_driver <- config$database$driver
  time_func <- if (db_driver == "sqlite") "datetime('now')" else "NOW()"
  
  # Convert NULL to NA for glue_sql
  percent <- if (is.null(percent)) NA else percent
  items_complete <- if (is.null(items_complete)) NA else items_complete
  message <- if (is.null(message)) NA else message
  error_message <- if (is.null(error_message)) NA else error_message
  
  tryCatch({
    # Build UPDATE clause parts
    update_clauses <- c("status = {status}")
    
    if (!is.na(percent)) {
      update_clauses <- c(update_clauses, "percent_complete = {percent}")
    }
    
    if (!is.na(items_complete)) {
      update_clauses <- c(update_clauses, "items_complete = {items_complete}")
      # Auto-transition from STARTED to RUNNING when progress occurs
      if (items_complete > 0 && status == "STARTED") {
        status <- "RUNNING"
        update_clauses[1] <- "status = 'RUNNING'"
      }
    }
    
    if (!is.na(message)) {
      update_clauses <- c(update_clauses, "progress_message = {message}")
    }
    
    if (!is.na(error_message)) {
      update_clauses <- c(update_clauses, "error_message = {error_message}")
    }
    
    if (status %in% c("COMPLETED", "FAILED")) {
      update_clauses <- c(update_clauses, paste0("end_time = ", time_func))
    }
    
    update_str <- paste(update_clauses, collapse = ", ")
    sql_template <- paste0("UPDATE {subtask_progress_table} SET ", update_str, 
                          " WHERE run_id = {run_id} AND subtask_number = {subtask_number}")
    
    DBI::dbExecute(
      conn,
      glue::glue_sql(sql_template, .con = conn)
    )
    
    if (!quiet) {
      # Get task_order for display
      task_runs_table <- get_table_name("task_runs", conn)
      tasks_table <- get_table_name("tasks", conn)
      task_order_info <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT t.task_order FROM {task_runs_table} tr
                 JOIN {tasks_table} t ON tr.task_id = t.task_id
                 WHERE tr.run_id = {run_id}", .con = conn)
      )
      
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      subtask_label <- if (nrow(task_order_info) > 0 && !is.na(task_order_info$task_order[1])) {
        sprintf("Subtask %d.%d", task_order_info$task_order[1], subtask_number)
      } else {
        sprintf("Subtask %d", subtask_number)
      }
      log_message <- sprintf("[%s] %s %s", 
                            timestamp, subtask_label, status)
      if (!is.null(percent) && !is.na(percent)) {
        log_message <- paste0(log_message, sprintf(" | %.1f%%", percent))
      }
      if (!is.null(items_complete) && !is.na(items_complete)) {
        log_message <- paste0(log_message, sprintf(" | %d items", items_complete))
      }
      if (!is.null(message)) {
        log_message <- paste0(log_message, " | ", message)
      }
      message(log_message)
    }
    
    TRUE
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
