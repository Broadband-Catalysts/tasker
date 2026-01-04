#' Manually Mark a Task as Complete
#'
#' Creates a task run record and immediately marks it as complete. 
#' This is useful for administrative purposes when a task has been run 
#' outside of the tasker tracking system or when you need to manually 
#' update task status.
#' 
#' Unlike task_start() + task_complete(), this function:
#' - Creates the run with both start_time and end_time
#' - Sets status directly to COMPLETED
#' - Uses current timestamp for both times (or specified timestamp)
#' - Optionally creates completed subtask records
#'
#' @param stage Stage name (e.g., "STATIC", "DAILY")
#' @param task Task name
#' @param message Completion message (optional)
#' @param total_subtasks Number of subtasks to mark complete (optional)
#' @param version Version string (optional)
#' @param git_commit Git commit hash (optional)
#' @param timestamp Timestamp to use for start/end (optional, defaults to current time)
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @return run_id (UUID) of the created completion record
#' @export
#'
#' @examples
#' \dontrun{
#' # Mark a task as complete
#' task_mark_complete(stage = "STATIC", task = "STATIC_01_Create_State_View.R")
#' 
#' # Mark with completion message
#' task_mark_complete(
#'   stage = "STATIC", 
#'   task = "STATIC_01_Create_State_View.R",
#'   message = "Manually marked complete after external execution"
#' )
#' 
#' # Mark with subtasks
#' task_mark_complete(
#'   stage = "STATIC", 
#'   task = "STATIC_01_Create_State_View.R",
#'   total_subtasks = 3,
#'   message = "Completed successfully"
#' )
#' }
task_mark_complete <- function(stage, 
                              task, 
                              message = NULL, 
                              total_subtasks = NULL,
                              version = NULL, 
                              git_commit = NULL,
                              timestamp = NULL,
                              quiet = FALSE, 
                              conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  on.exit({
    if (close_on_exit && !is.null(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
  tasks_table <- get_table_name("tasks", conn)
  stages_table <- get_table_name("stages", conn)
  task_runs_table <- get_table_name("task_runs", conn)
  subtask_progress_table <- get_table_name("subtask_progress", conn)
  
  # Convert NULL to NA for glue_sql
  total_subtasks <- if (is.null(total_subtasks)) NA else total_subtasks
  message <- if (is.null(message)) NA else message
  version <- if (is.null(version)) NA else version
  git_commit <- if (is.null(git_commit)) NA else git_commit
  
  # Determine timestamp to use
  config <- getOption("tasker.config")
  if (is.null(timestamp)) {
    if (config$database$driver == "sqlite") {
      time_value <- DBI::SQL("datetime('now')")
    } else {
      time_value <- DBI::SQL("NOW()")
    }
  } else {
    # Use provided timestamp
    time_value <- timestamp
  }
  
  tryCatch({
    # Verify task exists and get task_id
    task_info <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT t.task_id, t.task_order FROM {tasks_table} t
               JOIN {stages_table} s ON t.stage_id = s.stage_id
               WHERE s.stage_name = {stage} AND t.task_name = {task}",
              .con = conn)
    )
    
    if (nrow(task_info) == 0) {
      stop("Task '", task, "' in stage '", stage, "' not found. Register it first with register_task()")
    }
    
    task_id <- task_info$task_id
    task_order <- task_info$task_order
    
    # Get system information
    hostname <- Sys.info()["nodename"]
    process_id <- Sys.getpid()
    parent_pid <- get_parent_pid()
    user_name <- Sys.info()["user"]
    
    # Create a completed task run
    run_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {task_runs_table} 
               (task_id, hostname, process_id, parent_pid, 
                start_time, end_time, status, 
                total_subtasks, current_subtask, overall_percent_complete,
                overall_progress_message, version, git_commit, user_name)
               VALUES ({task_id}, {hostname}, {process_id}, {parent_pid}, 
                       {time_value*}, {time_value*}, 'COMPLETED',
                       {total_subtasks}, {total_subtasks}, 100,
                       {message}, {version}, {git_commit}, {user_name})
               RETURNING run_id", .con = conn)
    )$run_id
    
    # Create subtask progress records if specified
    if (!is.na(total_subtasks) && total_subtasks > 0) {
      for (i in seq_len(total_subtasks)) {
        DBI::dbExecute(
          conn,
          glue::glue_sql("INSERT INTO {subtask_progress_table}
                   (run_id, subtask_number, subtask_description, 
                    start_time, end_time, status, 
                    items_total, items_completed, progress_percent,
                    progress_message)
                   VALUES ({run_id}, {i}, {paste0('Subtask ', i)},
                           {time_value*}, {time_value*}, 'COMPLETED',
                           1, 1, 100,
                           'Manually marked complete')", .con = conn)
        )
      }
    }
    
    if (!quiet) {
      timestamp_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      task_num <- if (!is.na(task_order)) paste0("Task ", task_order) else "Task"
      log_message <- sprintf("[%s] %s MARKED COMPLETE | %s / %s | run_id: %s", 
                            timestamp_str, task_num, stage, task, run_id)
      if (!is.na(message)) {
        log_message <- paste0(log_message, " | ", message)
      }
      message(log_message)
    }
    
    invisible(run_id)
    
  }, error = function(e) {
    stop("Failed to mark task as complete: ", e$message)
  })
}
