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
#' @param .active Set this run as the active context (default: TRUE).
#'   When TRUE, subsequent tasker function calls can omit the run_id parameter.
#'   Set to FALSE if starting a task within a library function to avoid
#'   overwriting the user's active context.
#' @return run_id (UUID) to track this execution
#' @export
#'
#' @examples
#' \dontrun{
#' # Old style - explicit run_id
#' run_id <- task_start("STATIC", "Process FCC Data")
#'
#' # New style - automatic context (run_id optional in subsequent calls)
#' task_start("STATIC", "Process FCC Data")
#' subtask_start("Load files")  # No run_id needed!
#' subtask_complete()
#' task_complete()
#' }
task_start <- function(stage, task, total_subtasks = NULL, 
                      message = NULL, version = NULL, 
                      git_commit = NULL, quiet = FALSE, conn = NULL,
                      .active = TRUE) {
  
  # Input validation
  if (missing(stage) || !is.character(stage) || length(stage) != 1 || nchar(trimws(stage)) == 0) {
    stop("'stage' must be a non-empty character string", call. = FALSE)
  }
  
  if (missing(task) || !is.character(task) || length(task) != 1 || nchar(trimws(task)) == 0) {
    stop("'task' must be a non-empty character string", call. = FALSE)
  }
  
  if (!is.null(total_subtasks)) {
    if (!is.numeric(total_subtasks) || length(total_subtasks) != 1 || total_subtasks < 1) {
      stop("'total_subtasks' must be a positive integer if provided", call. = FALSE)
    }
    total_subtasks <- as.integer(total_subtasks)
  }
  
  if (!is.logical(quiet) || length(quiet) != 1) {
    stop("'quiet' must be TRUE or FALSE", call. = FALSE)
  }
  
  if (!is.logical(.active) || length(.active) != 1) {
    stop("'.active' must be TRUE or FALSE", call. = FALSE)
  }
  
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  tasks_table <- get_table_name("tasks", conn)
  stages_table <- get_table_name("stages", conn)
  task_runs_table <- get_table_name("task_runs", conn)
  
  # Convert NULL to SQL NULL literal for glue_sql
  total_subtasks_sql <- if (is.null(total_subtasks)) DBI::SQL("NULL") else total_subtasks
  message_sql <- if (is.null(message)) DBI::SQL("NULL") else message
  version_sql <- if (is.null(version)) DBI::SQL("NULL") else version
  git_commit_sql <- if (is.null(git_commit)) DBI::SQL("NULL") else git_commit
  
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
                       'STARTED', {total_subtasks_sql}, {message_sql}, {version_sql},
                       {git_commit_sql}, {user_name})
               RETURNING run_id", .con = conn)
    )$run_id
    
    if (!quiet) {
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      task_num <- if (!is.na(task_order)) paste0("Task ", task_order) else "Task"
      log_message <- sprintf("[%s] %s START | %s / %s | run_id: %s", 
                            timestamp, task_num, stage, task, run_id)
      if (!is.null(message)) {
        log_message <- paste0(log_message, " | ", message)
      }
      message(log_message)
    }
    
    # Set as active context if requested
    if (.active) {
      tasker_context(run_id)
    }
    
    run_id
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
