#' Remove Subtask Progress Records
#'
#' Removes subtask progress records for a specific run or all runs of a task.
#' This is useful for cleaning up orphaned or test subtask records.
#' 
#' **WARNING**: This will permanently remove subtask progress data.
#' Use with caution.
#'
#' @param run_id Run ID (UUID) to remove subtasks from, or NULL to specify by task
#' @param task_id Task ID to remove all subtask records from (ignored if run_id is provided)
#' @param script_filename Script filename to identify task (alternative to task_id)
#' @param subtask_number Optional specific subtask number to remove (NULL removes all)
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param confirmation_string The confirmation string the user must type to proceed.
#'   Default is "REMOVE SUBTASKS". Set to NULL to skip confirmation prompt
#'   (useful for programmatic use).
#' @param interactive If TRUE (default), prompts user for confirmation. 
#'   Set to FALSE for non-interactive scripts (requires confirmation_string = NULL).
#' @param quiet If TRUE, suppress informational messages (default: FALSE)
#'
#' @return Invisibly returns a list with removal details:
#'   \item{subtasks_removed}{Number of subtask records removed}
#'   \item{run_id}{Run ID if specified}
#'   \item{task_id}{Task ID if specified}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Remove all subtasks for a specific run (interactive)
#' remove_subtask(run_id = "123e4567-e89b-12d3-a456-426614174000")
#'
#' # Remove all subtasks for all runs of a task
#' remove_subtask(script_filename = "ONEOFF_01_Test_Script.R",
#'                confirmation_string = NULL, interactive = FALSE)
#'
#' # Remove specific subtask number from a run
#' remove_subtask(run_id = "123e4567-e89b-12d3-a456-426614174000",
#'                subtask_number = 2,
#'                confirmation_string = NULL, interactive = FALSE)
#' }
remove_subtask <- function(run_id = NULL,
                          task_id = NULL,
                          script_filename = NULL,
                          subtask_number = NULL,
                          conn = NULL, 
                          confirmation_string = "REMOVE SUBTASKS",
                          interactive = TRUE,
                          quiet = FALSE) {
  ensure_configured()
  
  # Input validation
  if (is.null(run_id) && is.null(task_id) && is.null(script_filename)) {
    stop("Must provide either 'run_id', 'task_id', or 'script_filename'", call. = FALSE)
  }
  
  if (!is.null(subtask_number)) {
    if (!is.numeric(subtask_number) || length(subtask_number) != 1 || subtask_number < 1) {
      stop("'subtask_number' must be a positive integer if provided", call. = FALSE)
    }
    subtask_number <- as.integer(subtask_number)
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
  subtask_table <- get_table_name("subtask_progress", conn)
  task_runs_table <- get_table_name("task_runs", conn)
  tasks_table <- get_table_name("tasks", conn)
  
  # Build query based on input parameters
  where_clause <- c()
  params <- list()
  
  if (!is.null(run_id)) {
    # Direct run_id lookup
    where_clause <- c(where_clause, glue::glue_sql("{`subtask_table`}.run_id = {run_id}", .con = conn))
    
    # Get task info for display
    task_info <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("
        SELECT t.task_name, t.script_filename, tr.run_id
        FROM {task_runs_table} tr
        JOIN {tasks_table} t ON t.task_id = tr.task_id
        WHERE tr.run_id = {run_id}
      ", .con = conn)
    )
    
    if (nrow(task_info) == 0) {
      if (!quiet) {
        message("Run ID '", run_id, "' not found")
      }
      return(invisible(list(
        subtasks_removed = 0,
        run_id = run_id,
        task_id = NULL
      )))
    }
    
    scope_description <- glue::glue("run_id: {run_id} (task: {task_info$task_name[1]})")
    
  } else {
    # Task-based lookup
    if (!is.null(script_filename)) {
      # Look up task_id from script_filename
      task_lookup <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT task_id, task_name FROM {tasks_table} WHERE script_filename = {script_filename}",
                       .con = conn)
      )
      
      if (nrow(task_lookup) == 0) {
        if (!quiet) {
          message("Task with script_filename '", script_filename, "' not found")
        }
        return(invisible(list(
          subtasks_removed = 0,
          run_id = NULL,
          task_id = NULL
        )))
      }
      
      task_id <- task_lookup$task_id[1]
      task_name <- task_lookup$task_name[1]
    } else {
      # task_id provided directly
      task_info <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT task_name FROM {tasks_table} WHERE task_id = {task_id}",
                       .con = conn)
      )
      
      if (nrow(task_info) == 0) {
        if (!quiet) {
          message("Task ID '", task_id, "' not found")
        }
        return(invisible(list(
          subtasks_removed = 0,
          run_id = NULL,
          task_id = task_id
        )))
      }
      
      task_name <- task_info$task_name[1]
    }
    
    # Build query to get all run_ids for this task
    where_clause <- c(where_clause, glue::glue_sql(
      "{`subtask_table`}.run_id IN (SELECT run_id FROM {task_runs_table} WHERE task_id = {task_id})",
      .con = conn
    ))
    
    scope_description <- glue::glue("all runs of task: {task_name}")
  }
  
  # Add subtask_number filter if specified
  if (!is.null(subtask_number)) {
    where_clause <- c(where_clause, glue::glue_sql("{`subtask_table`}.subtask_number = {subtask_number}", .con = conn))
    scope_description <- glue::glue("{scope_description}, subtask #{subtask_number}")
  }
  
  # Count subtasks to be removed
  count_query <- glue::glue_sql(
    "SELECT COUNT(*) as n FROM {subtask_table} WHERE {glue::glue_collapse(where_clause, sep = ' AND ')}",
    .con = conn
  )
  
  subtask_count <- DBI::dbGetQuery(conn, count_query)$n
  
  if (subtask_count == 0) {
    if (!quiet) {
      message("No subtasks found matching criteria - nothing to remove")
    }
    return(invisible(list(
      subtasks_removed = 0,
      run_id = run_id,
      task_id = task_id
    )))
  }
  
  # Display warning
  if (!quiet) {
    message("\n")
    message(crayon::bold(crayon::yellow("WARNING: SUBTASK REMOVAL")))
    message(crayon::yellow("=========================="))
    message("This will remove subtask progress records for:")
    message("  • Scope: ", scope_description)
    message("  • Number of subtask records: ", subtask_count)
    message("")
    message(crayon::bold("This operation cannot be undone."))
    message("")
  }
  
  # Handle confirmation
  if (interactive) {
    if (is.null(confirmation_string)) {
      stop("In interactive mode, 'confirmation_string' cannot be NULL. ",
           "Set interactive = FALSE to skip confirmation.", call. = FALSE)
    }
    
    if (!quiet) {
      message(sprintf("Type '%s' to confirm removal: ", confirmation_string))
    }
    user_input <- readline(prompt = "")
    
    if (trimws(user_input) != confirmation_string) {
      if (!quiet) {
        message("\nCancelled - confirmation did not match")
      }
      return(invisible(list(
        subtasks_removed = 0,
        run_id = run_id,
        task_id = task_id
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
    message("\nRemoving subtasks...")
  }
  
  tryCatch({
    # Remove the subtasks
    delete_query <- glue::glue_sql(
      "DELETE FROM {subtask_table} WHERE {glue::glue_collapse(where_clause, sep = ' AND ')}",
      .con = conn
    )
    
    rows_removed <- DBI::dbExecute(conn, delete_query)
    
    if (!quiet) {
      message(sprintf("  \u2713 Removed %d subtask record(s)", rows_removed))
      message("\nSubtask removal completed successfully.")
    }
    
    invisible(list(
      subtasks_removed = rows_removed,
      run_id = run_id,
      task_id = task_id
    ))
    
  }, error = function(e) {
    stop("Failed to remove subtasks: ", conditionMessage(e), call. = FALSE)
  })
}
