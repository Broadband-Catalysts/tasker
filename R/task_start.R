#' Start tracking a task execution
#'
#' @param stage Stage name
#' @param task Task name
#' @param total_subtasks Total number of subtasks (optional)
#' @param message Initial progress message (optional)
#' @param version Version string (optional)
#' @param git_commit Git commit hash (optional)
#' @param quiet Suppress console messages (default: FALSE)
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
                      git_commit = NULL, quiet = FALSE, conn = NULL) {
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
    
    hostname <- Sys.info()["nodename"]
    process_id <- Sys.getpid()
    parent_pid <- get_parent_pid()
    user_name <- Sys.info()["user"]
    
    run_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {task_runs_table} 
               (task_id, hostname, process_id, parent_pid, start_time, 
                status, total_subtasks, overall_progress_message, 
                version, git_commit, user_name)
               VALUES ({task_id}, {hostname}, {process_id}, {parent_pid}, {time_func*}, 
                       'STARTED', {total_subtasks}, {message}, {version},
                       {git_commit}, {user_name})
               RETURNING run_id", .con = conn)
    )$run_id
    
    if (!quiet) {
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      task_num <- if (!is.na(task_order)) paste0("Task ", task_order) else "Task"
      log_message <- sprintf("[%s] %s START | %s / %s | run_id: %s", 
                            timestamp, task_num, stage, task, run_id)
      if (!is.na(message)) {
        log_message <- paste0(log_message, " | ", message)
      }
      message(log_message)
    }
    
    run_id
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
