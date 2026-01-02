#' Reset Task Status
#'
#' Resets a task by deleting its execution history from task_runs table.
#' This sets the task back to NOT_STARTED state. Subtask progress is 
#' automatically deleted via cascade.
#'
#' @param stage Stage name (required)
#' @param task Task name (required)
#' @param run_id Specific run_id to delete (optional). If NULL, deletes all runs for the task.
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @return TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' # Reset a specific task
#' task_reset(stage = "DAILY", task = "process_counties")
#' 
#' # Reset a specific run
#' task_reset(stage = "DAILY", task = "process_counties", run_id = "...")
#' }
task_reset <- function(stage, task, run_id = NULL, quiet = FALSE, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  on.exit({
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
  
  config <- getOption("tasker.config")
  task_runs_table <- get_table_name("task_runs", conn)
  tasks_table <- get_table_name("tasks", conn)
  stages_table <- get_table_name("stages", conn)
  
  tryCatch({
    # Get task_id
    task_info <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT t.task_id, t.task_name FROM {tasks_table} t
               JOIN {stages_table} s ON t.stage_id = s.stage_id
               WHERE s.stage_name = {stage} AND t.task_name = {task}",
              .con = conn)
    )
    
    if (nrow(task_info) == 0) {
      stop("Task '", task, "' in stage '", stage, "' not found")
    }
    
    task_id <- task_info$task_id
    
    # Count runs to delete
    if (is.null(run_id)) {
      count_sql <- glue::glue_sql(
        "SELECT COUNT(*)::INTEGER as n FROM {task_runs_table} WHERE task_id = {task_id}",
        .con = conn
      )
    } else {
      count_sql <- glue::glue_sql(
        "SELECT COUNT(*)::INTEGER as n FROM {task_runs_table} WHERE task_id = {task_id} AND run_id = {run_id}",
        .con = conn
      )
    }
    
    count_result <- DBI::dbGetQuery(conn, count_sql)
    n_runs <- if (config$database$driver == "postgresql") {
      count_result$n
    } else {
      # SQLite doesn't support ::INTEGER cast
      as.integer(count_result[[1]])
    }
    
    if (n_runs == 0) {
      if (!quiet) {
        message("No task runs found to reset for ", stage, " / ", task)
      }
      return(TRUE)
    }
    
    # Delete task runs (cascade will delete subtask_progress)
    if (is.null(run_id)) {
      delete_sql <- glue::glue_sql(
        "DELETE FROM {task_runs_table} WHERE task_id = {task_id}",
        .con = conn
      )
    } else {
      delete_sql <- glue::glue_sql(
        "DELETE FROM {task_runs_table} WHERE task_id = {task_id} AND run_id = {run_id}",
        .con = conn
      )
    }
    
    DBI::dbExecute(conn, delete_sql)
    
    if (!quiet) {
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      message(sprintf("[%s] Reset task: %s / %s (%d run%s deleted)", 
                     timestamp, stage, task, n_runs, 
                     if (n_runs == 1) "" else "s"))
    }
    
    TRUE
    
  }, error = function(e) {
    if (!quiet) {
      message("Error resetting task: ", e$message)
    }
    stop(e)
  })
}
