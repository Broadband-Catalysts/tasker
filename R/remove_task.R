#' Remove a Specific Task
#'
#' Removes a task from the task registry by script filename.
#' Task execution history (task_runs and subtask_progress) is preserved.
#' This is useful for removing individual obsolete tasks.
#' 
#' **WARNING**: This will permanently remove the task definition.
#' Use with caution.
#'
#' @param script_filename Script filename of the task to remove (e.g., "ONEOFF_01_Create_Partitioned_BDC_Locations.R")
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param confirmation_string The confirmation string the user must type to proceed.
#'   Default is "REMOVE TASK". Set to NULL to skip confirmation prompt
#'   (useful for programmatic use).
#' @param interactive If TRUE (default), prompts user for confirmation. 
#'   Set to FALSE for non-interactive scripts (requires confirmation_string = NULL).
#' @param quiet If TRUE, suppress informational messages (default: FALSE)
#'
#' @return Invisibly returns a list with removal details:
#'   \item{task_removed}{TRUE if task was removed}
#'   \item{task_name}{Name of removed task}
#'   \item{script_filename}{Script filename of removed task}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Interactive mode (will prompt for confirmation)
#' remove_task("ONEOFF_01_Create_Partitioned_BDC_Locations.R")
#'
#' # Programmatic mode (skips confirmation - USE WITH CAUTION!)
#' remove_task("obsolete_script.R", confirmation_string = NULL, interactive = FALSE)
#'
#' # Quiet mode for scripts
#' remove_task("old_script.R", confirmation_string = NULL, interactive = FALSE, quiet = TRUE)
#' }
remove_task <- function(script_filename,
                       conn = NULL, 
                       confirmation_string = "REMOVE TASK",
                       interactive = TRUE,
                       quiet = FALSE) {
  ensure_configured()
  
  # Input validation
  if (missing(script_filename) || !is.character(script_filename) || 
      length(script_filename) != 1 || nchar(trimws(script_filename)) == 0) {
    stop("'script_filename' must be a non-empty character string", call. = FALSE)
  }
  
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
  
  # Get table names
  tasks_table <- get_table_name("tasks", conn)
  
  # Check if task exists and get details
  task_info <- DBI::dbGetQuery(
    conn,
    glue::glue_sql("SELECT task_id, task_name FROM {tasks_table} 
                    WHERE script_filename = {script_filename}",
                   .con = conn)
  )
  
  if (nrow(task_info) == 0) {
    if (!quiet) {
      message("Task with script_filename '", script_filename, "' not found - nothing to remove")
    }
    return(invisible(list(
      task_removed = FALSE,
      task_name = NA,
      script_filename = script_filename
    )))
  }
  
  task_id <- task_info$task_id[1]
  task_name <- task_info$task_name[1]
  
  # Display warning
  if (!quiet) {
    message("\n")
    message(crayon::bold(crayon::yellow("WARNING: TASK REMOVAL")))
    message(crayon::yellow("======================"))
    message("This function will remove the task:")
    message("  • Task Name: ", task_name)
    message("  • Script Filename: ", script_filename)
    message("")
    message(crayon::bold("Task execution history will be preserved."))
    message("")
  }
  
  # Handle confirmation
  if (interactive) {
    if (is.null(confirmation_string)) {
      stop("In interactive mode, 'confirmation_string' cannot be NULL. ",
           "Set interactive = FALSE to skip confirmation.", call. = FALSE)
    }
    
    if (!quiet) {
      message(sprintf("Type '%s' to confirm deletion: ", confirmation_string))
    }
    user_input <- readline(prompt = "")
    
    if (trimws(user_input) != confirmation_string) {
      if (!quiet) {
        message("\nCancelled - confirmation did not match")
      }
      return(invisible(list(
        task_removed = FALSE,
        task_name = task_name,
        script_filename = script_filename
      )))
    }
  } else {
    # Non-interactive mode: require NULL confirmation_string
    if (!is.null(confirmation_string)) {
      stop("In non-interactive mode, 'confirmation_string' must be NULL. ",
           "This prevents accidental removal.", call. = FALSE)
    }
  }
  
  # Proceed with removal
  if (!quiet) {
    message("\nRemoving task...")
  }
  
  tryCatch({
    # Remove the task
    rows_deleted <- DBI::dbExecute(
      conn,
      glue::glue_sql("DELETE FROM {tasks_table} WHERE task_id = {task_id}",
                     .con = conn)
    )
    
    if (!quiet) {
      message(sprintf("  \u2713 Removed task '%s' (script_filename: %s)", 
                     task_name, script_filename))
      message("\nTask removal completed successfully.")
    }
    
    invisible(list(
      task_removed = TRUE,
      task_name = task_name,
      script_filename = script_filename
    ))
    
  }, error = function(e) {
    stop("Failed to remove task: ", conditionMessage(e), call. = FALSE)
  })
}
