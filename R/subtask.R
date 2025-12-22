#' Start tracking a subtask
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number
#' @param subtask_name Subtask name/description
#' @param items_total Total items to process (optional)
#' @param message Progress message (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @return progress_id
#' @export
#'
#' @examples
#' \dontrun{
#' subtask_start(run_id, 1, "Processing state-level data", items_total = 56)
#' }
subtask_start <- function(run_id, subtask_number, subtask_name,
                         items_total = NULL, message = NULL, quiet = FALSE, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  subtask_progress_table <- get_table_name("subtask_progress", conn)
  db_driver <- config$database$driver
  time_func <- if (db_driver == "sqlite") "datetime('now')" else "NOW()"
  
  # Convert NULL to SQL NULL literal
  items_total_sql <- if (is.null(items_total)) DBI::SQL("NULL") else items_total
  message_sql <- if (is.null(message)) DBI::SQL("NULL") else message
  
  tryCatch({
    progress_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {subtask_progress_table}
               (run_id, subtask_number, subtask_name, status, start_time,
                items_total, progress_message)
               VALUES ({run_id}, {subtask_number}, {subtask_name}, 'STARTED', {time_func*}, 
                       {items_total_sql}, {message_sql})
               ON CONFLICT (run_id, subtask_number) 
               DO UPDATE SET 
                 subtask_name = EXCLUDED.subtask_name,
                 status = 'STARTED',
                 start_time = {time_func*},
                 items_total = EXCLUDED.items_total,
                 progress_message = EXCLUDED.progress_message
               RETURNING progress_id", .con = conn)
    )$progress_id
    
    if (!quiet) {
      log_message <- sprintf("[SUBTASK START] Subtask %d: %s", 
                            subtask_number, subtask_name)
      if (!is.null(message)) {
        log_message <- paste0(log_message, " - ", message)
      }
      message(log_message)
    }
    
    progress_id
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}


#' Update subtask progress
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number
#' @param status Status: RUNNING, COMPLETED, FAILED, SKIPPED
#' @param percent Percent complete 0-100 (optional)
#' @param items_complete Items completed (optional)
#' @param message Progress message (optional)
#' @param error_message Error message if failed (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' subtask_update(run_id, 1, "RUNNING", percent = 50, items_complete = 28)
#' subtask_update(run_id, 1, "COMPLETED", percent = 100, items_complete = 56)
#' }
subtask_update <- function(run_id, subtask_number, status,
                          percent = NULL, items_complete = NULL,
                          message = NULL, error_message = NULL,
                          quiet = FALSE, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  subtask_progress_table <- get_table_name("subtask_progress", conn)
  db_driver <- config$database$driver
  time_func <- if (db_driver == "sqlite") "datetime('now')" else "NOW()"
  
  valid_statuses <- c("RUNNING", "COMPLETED", "FAILED", "SKIPPED")
  if (!status %in% valid_statuses) {
    stop("Invalid status: ", status, ". Must be one of: ", 
         paste(valid_statuses, collapse = ", "))
  }
  
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
      log_message <- sprintf("[SUBTASK UPDATE] Subtask %d - %s", 
                            subtask_number, status)
      if (!is.null(message)) {
        log_message <- paste0(log_message, ": ", message)
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


#' Complete a subtask
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number
#' @param items_completed Items completed (optional)
#' @param message Final message (optional)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
subtask_complete <- function(run_id, subtask_number, items_completed = NULL, 
                            message = NULL, quiet = FALSE, conn = NULL) {
  subtask_update(run_id, subtask_number, status = "COMPLETED",
                percent = 100, items_complete = items_completed, 
                message = message, quiet = quiet, conn = conn)
}


#' Mark a subtask as failed
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number
#' @param error_message Error message
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
subtask_fail <- function(run_id, subtask_number, error_message, quiet = FALSE, conn = NULL) {
  subtask_update(run_id, subtask_number, status = "FAILED",
                error_message = error_message, quiet = quiet, conn = conn)
}
