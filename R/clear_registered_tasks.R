#' Clear All Registered Tasks
#'
#' This function deletes all task registrations from the tasks and stages tables.
#' It preserves task execution history (task_runs and subtask_progress).
#' This is useful for re-registering tasks with updated configurations.
#' 
#' **WARNING**: This will delete all task definitions. You will need to 
#' re-register tasks before running new task executions.
#'
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param confirmation_string The confirmation string the user must type to proceed.
#'   Default is "CLEAR TASKS". Set to NULL to skip confirmation prompt
#'   (useful for programmatic use).
#' @param interactive If TRUE (default), prompts user for confirmation. 
#'   Set to FALSE for non-interactive scripts (requires confirmation_string = NULL).
#'
#' @return TRUE if successful, FALSE if cancelled
#' @export
#'
#' @examples
#' \dontrun{
#' # Interactive mode (will prompt for confirmation)
#' clear_registered_tasks()
#'
#' # Programmatic mode (skips confirmation - USE WITH CAUTION!)
#' clear_registered_tasks(confirmation_string = NULL, interactive = FALSE)
#' }
clear_registered_tasks <- function(conn = NULL, 
                                   confirmation_string = "CLEAR TASKS",
                                   interactive = TRUE) {
  ensure_configured()
  
  close_conn <- FALSE
  
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_conn <- TRUE
  }
  
  on.exit({
    if (close_conn && !is.null(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  # Display warning
  message("\n")
  message(crayon::bold(crayon::yellow("WARNING: TASK REGISTRATION DELETION")))
  message(crayon::yellow("========================================"))
  message("This function will delete ALL registered tasks from:")
  message("  • tasks table (task definitions)")
  message("  • stages table (stage definitions)")
  message("")
  message(crayon::bold("Task execution history will be preserved."))
  message("You will need to re-register tasks before running new executions.")
  message(crayon::yellow("========================================"))
  message("\n")
  
  # Handle confirmation
  if (interactive && !is.null(confirmation_string)) {
    message("To proceed, type: ", crayon::bold(confirmation_string))
    user_input <- readline(prompt = "--> ")
    
    if (user_input != confirmation_string) {
      message(crayon::green("\u2713 Operation cancelled. No tasks were deleted."))
      return(FALSE)
    }
  } else if (!interactive && !is.null(confirmation_string)) {
    stop("Non-interactive mode requires confirmation_string = NULL to proceed with task deletion.")
  }
  
  message("\n")
  message("Clearing registered tasks...")
  
  tryCatch({
    # Get table names based on driver
    stages_table <- get_table_name("stages", conn)
    tasks_table <- get_table_name("tasks", conn)
    
    # Count existing records
    if (driver == "postgresql") {
      task_count <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT COUNT(*)::INTEGER as n FROM {tasks_table}", .con = conn)
      )$n
      
      stage_count <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT COUNT(*)::INTEGER as n FROM {stages_table}", .con = conn)
      )$n
      
      # Delete in order respecting foreign key constraints
      DBI::dbExecute(conn, glue::glue_sql("DELETE FROM {tasks_table}", .con = conn))
      message(sprintf("  \u2713 Deleted %d task(s) from %s", task_count, tasks_table))
      
      DBI::dbExecute(conn, glue::glue_sql("DELETE FROM {stages_table}", .con = conn))
      message(sprintf("  \u2713 Deleted %d stage(s) from %s", stage_count, stages_table))
      
      # Reset sequences
      message("\nResetting sequences...")
      sequences <- DBI::dbGetQuery(
        conn,
        "SELECT sequence_name FROM information_schema.sequences 
         WHERE sequence_schema = 'tasker'
         AND sequence_name IN ('stages_stage_id_seq', 'tasks_task_id_seq')"
      )$sequence_name
      
      for (seq in sequences) {
        DBI::dbExecute(conn, sprintf("ALTER SEQUENCE tasker.%s RESTART WITH 1", seq))
        message(sprintf("  \u2713 Reset sequence tasker.%s", seq))
      }
      
    } else if (driver == "sqlite") {
      task_count <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table}", .con = conn)
      )$n
      
      stage_count <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table}", .con = conn)
      )$n
      
      # Delete in order respecting foreign key constraints
      DBI::dbExecute(conn, glue::glue_sql("DELETE FROM {tasks_table}", .con = conn))
      message(sprintf("  \u2713 Deleted %d task(s) from %s", task_count, tasks_table))
      
      DBI::dbExecute(conn, glue::glue_sql("DELETE FROM {stages_table}", .con = conn))
      message(sprintf("  \u2713 Deleted %d stage(s) from %s", stage_count, stages_table))
      
      # Reset autoincrement counters in SQLite
      message("\nResetting autoincrement counters...")
      DBI::dbExecute(conn, "DELETE FROM sqlite_sequence WHERE name IN ('stages', 'tasks')")
      message("  \u2713 Reset autoincrement counters")
      
    } else {
      stop("Unsupported database driver: ", driver)
    }
    
    message("\n")
    message(crayon::bold(crayon::green("\u2713 All registered tasks have been cleared successfully")))
    message("You can now re-register tasks with updated configurations.")
    message("\n")
    
    TRUE
    
  }, error = function(e) {
    message("\n")
    message(crayon::bold(crayon::red("\u2717 Error clearing registered tasks:")))
    message(e$message)
    FALSE
  })
}
