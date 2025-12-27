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
    # Get task_order for display
    task_runs_table <- get_table_name("task_runs", conn)
    tasks_table <- get_table_name("tasks", conn)
    task_order_info <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT t.task_order FROM {task_runs_table} tr
               JOIN {tasks_table} t ON tr.task_id = t.task_id
               WHERE tr.run_id = {run_id}", .con = conn)
    )
    
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
    
    # Automatically transition parent task to RUNNING status when subtask starts
    # and update current_subtask to reflect which subtask is being worked on
    # This ensures that tasks with active subtasks are properly marked as RUNNING
    # and the progress (current_subtask/total_subtasks) is accurately displayed
    DBI::dbExecute(
      conn,
      glue::glue_sql("UPDATE {task_runs_table} 
               SET status = 'RUNNING',
                   current_subtask = {subtask_number}
               WHERE run_id = {run_id} AND status = 'STARTED'", .con = conn)
    )
    
    # Also update current_subtask if already RUNNING (for subsequent subtasks)
    DBI::dbExecute(
      conn,
      glue::glue_sql("UPDATE {task_runs_table} 
               SET current_subtask = {subtask_number}
               WHERE run_id = {run_id} AND status = 'RUNNING'", .con = conn)
    )
    
    if (!quiet) {
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      subtask_label <- if (nrow(task_order_info) > 0 && !is.na(task_order_info$task_order[1])) {
        sprintf("Subtask %d.%d", task_order_info$task_order[1], subtask_number)
      } else {
        sprintf("Subtask %d", subtask_number)
      }
      log_message <- sprintf("[%s] %s START | %s", 
                            timestamp, subtask_label, subtask_name)
      if (!is.null(message)) {
        log_message <- paste0(log_message, " | ", message)
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
