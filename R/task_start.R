#' Start tracking a task execution
#'
#' Automatically detects the executing script and looks up stage/task from the
#' database, or accepts explicit stage/task parameters for backward compatibility.
#'
#' @param stage Stage name (optional - will auto-detect from script filename)
#' @param task Task name (optional - will auto-detect from script filename)
#' @param total_subtasks Total number of subtasks (optional). Zero is allowed
#'   for tasks that have no subtasks.
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
#'
#' @seealso [task_update()] to update task status, [task_mark_complete()] to
#'   mark task complete, [task_reset()] to reset task state,
#'   [subtask_start()] to start tracking subtasks, [get_task_status()] to
#'   query task status
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # New style - automatic detection (zero configuration!)
#' task_start()  # Auto-detects script, looks up stage/task from database
#' subtask_start("Load files")
#' subtask_complete()
#' task_complete()
#'
#' # Old style - explicit parameters (still supported)
#' task_start("STATIC", "Process FCC Data")
#' subtask_start("Load files")
#' subtask_complete()
#' task_complete()
#' }
task_start <- function(stage = NULL, task = NULL, total_subtasks = NULL, 
                      message = NULL, version = NULL, 
                      git_commit = NULL, quiet = FALSE, conn = NULL,
                      .active = TRUE) {
  
  # Auto-detect stage and task from script filename if not provided
  if (is.null(stage) || is.null(task)) {
    script_filename <- get_script_filename()
    
    if (!is.null(script_filename)) {
      task_info <- lookup_task_by_script(script_filename, conn)
      
      if (!is.null(task_info)) {
        if (is.null(stage)) stage <- task_info$stage
        if (is.null(task)) task <- task_info$task
        
        if (!quiet) {
          message(sprintf("Auto-detected from script '%s': %s / %s", 
                         script_filename, stage, task))
        }
      } else if (is.null(stage) || is.null(task)) {
        stop("Could not auto-detect stage/task from script '", script_filename, 
             "'. Either:\n",
             "  1. Register the task with register_task() including script_filename, or\n",
             "  2. Provide stage and task parameters explicitly",
             call. = FALSE)
      }
    } else if (is.null(stage) || is.null(task)) {
      stop("Could not auto-detect script filename and stage/task not provided.\n",
           "Provide stage and task parameters explicitly or ensure script is run via Rscript/R CMD BATCH",
           call. = FALSE)
    }
  }
  
  # Input validation
  if (!is.character(stage) || length(stage) != 1 || nchar(trimws(stage)) == 0) {
    stop("'stage' must be a non-empty character string", call. = FALSE)
  }
  
  if (!is.character(task) || length(task) != 1 || nchar(trimws(task)) == 0) {
    stop("'task' must be a non-empty character string", call. = FALSE)
  }
  
  if (!is.null(total_subtasks)) {
    if (!is.numeric(total_subtasks) || length(total_subtasks) != 1 || total_subtasks < 0) {
      stop("'total_subtasks' must be a non-negative integer if provided", call. = FALSE)
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
  
  # Create or get connection
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
    
    # Auto-start reporter if needed (silent - no messages unless error)
    tryCatch({
      auto_start_reporter(hostname, conn)
    }, error = function(e) {
      # Don't fail task start if reporter auto-start fails
      if (!quiet) {
        warning("Failed to auto-start reporter: ", e$message)
      }
    })
    
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
    
    # Store connection for reuse if we created it
    if (close_on_exit) {
      store_connection(run_id, conn)
    }
    
    run_id
    
  }, error = function(e) {
    # Clean up connection on error
    if (close_on_exit && !is.null(conn) && DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
    stop(e)
  })
}
