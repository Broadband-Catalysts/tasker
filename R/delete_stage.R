#' Delete a Specific Stage and Its Tasks
#'
#' Deletes a stage and all its associated tasks from the task registry.
#' Task execution history (task_runs and subtask_progress) is preserved.
#' This is useful for removing obsolete stages that have no replacement.
#' 
#' **WARNING**: This will permanently delete the stage definition and all
#' its task definitions. Use with caution.
#'
#' @param stage_name Name of the stage to delete
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param confirmation_string The confirmation string the user must type to proceed.
#'   Default is "DELETE STAGE". Set to NULL to skip confirmation prompt
#'   (useful for programmatic use).
#' @param interactive If TRUE (default), prompts user for confirmation. 
#'   Set to FALSE for non-interactive scripts (requires confirmation_string = NULL).
#' @param quiet If TRUE, suppress informational messages (default: FALSE)
#'
#' @return Invisibly returns a list with deletion details:
#'   \item{stage_deleted}{TRUE if stage was deleted}
#'   \item{tasks_deleted}{Number of tasks deleted}
#'   \item{stage_name}{Name of deleted stage}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Interactive mode (will prompt for confirmation)
#' delete_stage("DAILY_FCC_UPDATE")
#'
#' # Programmatic mode (skips confirmation - USE WITH CAUTION!)
#' delete_stage("OBSOLETE_STAGE", confirmation_string = NULL, interactive = FALSE)
#'
#' # Quiet mode for scripts
#' delete_stage("OLD_STAGE", confirmation_string = NULL, interactive = FALSE, quiet = TRUE)
#' }
delete_stage <- function(stage_name,
                        conn = NULL, 
                        confirmation_string = "DELETE STAGE",
                        interactive = TRUE,
                        quiet = FALSE) {
  ensure_configured()
  
  # Input validation
  if (missing(stage_name) || !is.character(stage_name) || 
      length(stage_name) != 1 || nchar(trimws(stage_name)) == 0) {
    stop("'stage_name' must be a non-empty character string", call. = FALSE)
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
  stages_table <- get_table_name("stages", conn)
  tasks_table <- get_table_name("tasks", conn)
  
  # Check if stage exists
  stage_exists <- DBI::dbGetQuery(
    conn,
    glue::glue_sql("SELECT stage_id FROM {stages_table} WHERE stage_name = {stage_name}",
                   .con = conn)
  )
  
  if (nrow(stage_exists) == 0) {
    if (!quiet) {
      message("Stage '", stage_name, "' not found - nothing to delete")
    }
    return(invisible(list(
      stage_deleted = FALSE,
      tasks_deleted = 0,
      stage_name = stage_name
    )))
  }
  
  stage_id <- stage_exists$stage_id[1]
  
  # Count tasks to be deleted
  task_count <- DBI::dbGetQuery(
    conn,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table} WHERE stage_id = {stage_id}",
                   .con = conn)
  )$n
  
  # Get task names for display
  task_names <- if (task_count > 0) {
    DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT task_name FROM {tasks_table} WHERE stage_id = {stage_id} ORDER BY task_order",
                     .con = conn)
    )$task_name
  } else {
    character(0)
  }
  
  # Display warning
  if (!quiet) {
    message("\n")
    message(crayon::bold(crayon::yellow("WARNING: STAGE DELETION")))
    message(crayon::yellow("========================================"))
    message("This will delete the following:")
    message("  • Stage: ", crayon::bold(stage_name))
    message("  • Number of tasks: ", task_count)
    if (task_count > 0) {
      message("  • Task names:")
      for (task_name in task_names) {
        message("    - ", task_name)
      }
    }
    message("")
    message(crayon::bold("Task execution history will be preserved."))
    message(crayon::yellow("========================================"))
    message("\n")
  }
  
  # Handle confirmation
  if (interactive && !is.null(confirmation_string)) {
    message("To proceed, type: ", crayon::bold(confirmation_string))
    user_input <- readline(prompt = "--> ")
    
    if (user_input != confirmation_string) {
      if (!quiet) {
        message(crayon::green("\u2713 Operation cancelled. Nothing was deleted."))
      }
      return(invisible(list(
        stage_deleted = FALSE,
        tasks_deleted = 0,
        stage_name = stage_name
      )))
    }
  } else if (!interactive && !is.null(confirmation_string)) {
    stop("Non-interactive mode requires confirmation_string = NULL to proceed with deletion.", call. = FALSE)
  }
  
  if (!quiet) {
    message("\n")
    message("Deleting stage '", stage_name, "'...")
  }
  
  tryCatch({
    # Delete tasks first (foreign key constraint)
    tasks_deleted <- DBI::dbExecute(
      conn,
      glue::glue_sql("DELETE FROM {tasks_table} WHERE stage_id = {stage_id}",
                     .con = conn)
    )
    
    if (!quiet && tasks_deleted > 0) {
      message("  \u2713 Deleted ", tasks_deleted, " task(s)")
    }
    
    # Delete stage
    DBI::dbExecute(
      conn,
      glue::glue_sql("DELETE FROM {stages_table} WHERE stage_id = {stage_id}",
                     .con = conn)
    )
    
    if (!quiet) {
      message("  \u2713 Deleted stage '", stage_name, "'")
      message("\n")
      message(crayon::bold(crayon::green("\u2713 Stage deletion completed successfully")))
      message("\n")
    }
    
    invisible(list(
      stage_deleted = TRUE,
      tasks_deleted = tasks_deleted,
      stage_name = stage_name
    ))
    
  }, error = function(e) {
    if (!quiet) {
      message("\n")
      message(crayon::bold(crayon::red("\u2717 Error deleting stage:")))
      message(e$message)
    }
    stop("Failed to delete stage: ", e$message, call. = FALSE)
  })
}
