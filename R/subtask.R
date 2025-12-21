#' Start tracking a subtask
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number
#' @param subtask_name Subtask name/description
#' @param items_total Total items to process (optional)
#' @param message Progress message (optional)
#' @param conn Database connection (optional)
#' @return progress_id
#' @export
#'
#' @examples
#' \dontrun{
#' subtask_start(run_id, 1, "Processing state-level data", items_total = 56)
#' }
subtask_start <- function(run_id, subtask_number, subtask_name,
                         items_total = NULL, message = NULL, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  schema <- config$database$schema
  
  tryCatch({
    progress_id <- DBI::dbGetQuery(
      conn,
      sprintf("INSERT INTO %s.subtask_progress
               (run_id, subtask_number, subtask_name, status, start_time,
                items_total, progress_message)
               VALUES ($1, $2, $3, 'STARTED', NOW(), $4, $5)
               ON CONFLICT (run_id, subtask_number) 
               DO UPDATE SET 
                 subtask_name = EXCLUDED.subtask_name,
                 status = 'STARTED',
                 start_time = NOW(),
                 items_total = EXCLUDED.items_total,
                 progress_message = EXCLUDED.progress_message
               RETURNING progress_id", schema),
      params = list(run_id, subtask_number, subtask_name, items_total, message)
    )$progress_id
    
    log_message <- sprintf("[SUBTASK START] Subtask %d: %s", 
                          subtask_number, subtask_name)
    if (!is.null(message)) {
      log_message <- paste0(log_message, " - ", message)
    }
    message(log_message)
    
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
                          conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  schema <- config$database$schema
  
  valid_statuses <- c("RUNNING", "COMPLETED", "FAILED", "SKIPPED")
  if (!status %in% valid_statuses) {
    stop("Invalid status: ", status, ". Must be one of: ", 
         paste(valid_statuses, collapse = ", "))
  }
  
  tryCatch({
    updates <- c("status = $3")
    params <- list(run_id, subtask_number, status)
    param_num <- 3
    
    if (!is.null(percent)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("percent_complete = $%d", param_num))
      params <- c(params, list(percent))
    }
    
    if (!is.null(items_complete)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("items_complete = $%d", param_num))
      params <- c(params, list(items_complete))
    }
    
    if (!is.null(message)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("progress_message = $%d", param_num))
      params <- c(params, list(message))
    }
    
    if (!is.null(error_message)) {
      param_num <- param_num + 1
      updates <- c(updates, sprintf("error_message = $%d", param_num))
      params <- c(params, list(error_message))
    }
    
    if (status %in% c("COMPLETED", "FAILED")) {
      updates <- c(updates, "end_time = NOW()")
    }
    
    sql <- sprintf(
      "UPDATE %s.subtask_progress SET %s 
       WHERE run_id = $1 AND subtask_number = $2",
      schema,
      paste(updates, collapse = ", ")
    )
    
    DBI::dbExecute(conn, sql, params = params)
    
    log_message <- sprintf("[SUBTASK UPDATE] Subtask %d - %s", 
                          subtask_number, status)
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


#' Complete a subtask
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number
#' @param message Final message (optional)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
subtask_complete <- function(run_id, subtask_number, message = NULL, conn = NULL) {
  subtask_update(run_id, subtask_number, status = "COMPLETED",
                percent = 100, message = message, conn = conn)
}


#' Mark a subtask as failed
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number
#' @param error_message Error message
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
subtask_fail <- function(run_id, subtask_number, error_message, conn = NULL) {
  subtask_update(run_id, subtask_number, status = "FAILED",
                error_message = error_message, conn = conn)
}
