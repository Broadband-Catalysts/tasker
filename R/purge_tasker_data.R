#' Purge All Data from tasker Tables
#'
#' This function deletes all data from the tasker database tables. 
#' It preserves the schema structure but removes all task registrations,
#' execution history, and progress tracking data.
#' 
#' **WARNING**: This operation is irreversible. All task history and 
#' progress data will be permanently deleted.
#'
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param confirmation_string The confirmation string the user must type to proceed.
#'   Default is "DELETE ALL DATA". Set to NULL to skip confirmation prompt
#'   (useful for programmatic use, but be very careful!).
#' @param interactive If TRUE (default), prompts user for confirmation. 
#'   Set to FALSE for non-interactive scripts (requires confirmation_string = NULL).
#'
#' @return TRUE if successful, FALSE if cancelled
#' @export
#'
#' @examples
#' \dontrun{
#' # Interactive mode (will prompt for confirmation)
#' purge_tasker_data()
#'
#' # Programmatic mode (skips confirmation - USE WITH CAUTION!)
#' purge_tasker_data(confirmation_string = NULL, interactive = FALSE)
#' }
purge_tasker_data <- function(conn = NULL, confirmation_string="DELETE ALL DATA") {
  close_conn <- FALSE

  if (is.null(conn)) {
    ensure_configured()
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
  message(crayon::bold(crayon::red("WARNING: DATA DELETION")))
  message(crayon::red("========================================"))
  message("This function will delete ALL data from the tasker database tables:")
  message("  • tasker.subtask_progress")
  message("  • tasker.task_runs")
  message("  • tasker.tasks")
  message("  • tasker.stages")
  message("")
  message(crayon::bold("This operation is IRREVERSIBLE!"))
  message("All task history, execution records, and progress tracking will be permanently lost.")
  message(crayon::red("========================================"))
  message("\n")

  # Handle confirmation
  if (interactive()) {
    message("To proceed, type: ", crayon::bold(confirmation_string))
    user_input <- readline(prompt = "--> ")

    if (user_input != confirmation_string) {
      message(crayon::green("\u2713 Operation cancelled. No data was deleted."))
      return(FALSE)
    }
  } else {
    if (!is.null(confirmation_string))
      stop("Non-interactive mode requires confirmation_string = NULL to proceed with data deletion.")
  }

  message("\n")
  message("Purging tasker data...")

  tryCatch({
    # Get table names based on driver
    if (driver == "postgresql") {
      # Delete in order respecting foreign key constraints
      tables <- c("subtask_progress", "task_runs", "tasks", "stages")

      for (table in tables) {
        count_before <- DBI::dbGetQuery(
          conn,
          sprintf("SELECT COUNT(*)::INTEGER as n FROM tasker.%s", table)
        )$n

        DBI::dbExecute(conn, sprintf("DELETE FROM tasker.%s", table))

        message(sprintf("  \u2713 Deleted %d rows from tasker.%s", count_before, table))
      }

      # Reset sequences
      message("\nResetting sequences...")
      sequences <- DBI::dbGetQuery(
        conn,
        "SELECT sequence_name FROM information_schema.sequences 
         WHERE sequence_schema = 'tasker'"
      )$sequence_name

      for (seq in sequences) {
        DBI::dbExecute(conn, sprintf("ALTER SEQUENCE tasker.%s RESTART WITH 1", seq))
        message(sprintf("  \u2713 Reset sequence tasker.%s", seq))
      }

    } else if (driver == "sqlite") {
      # Delete in order respecting foreign key constraints
      tables <- c("subtask_progress", "task_runs", "tasks", "stages")

      for (table in tables) {
        count_before <- DBI::dbGetQuery(
          conn,
          sprintf("SELECT COUNT(*)::INTEGER as n FROM %s", table)
        )$n

        DBI::dbExecute(conn, sprintf("DELETE FROM %s", table))

        message(sprintf("  \u2713 Deleted %d rows from %s", count_before, table))
      }

      # Reset autoincrement counters in SQLite
      message("\nResetting autoincrement counters...")
      DBI::dbExecute(conn, "DELETE FROM sqlite_sequence WHERE name IN ('stages', 'tasks', 'subtask_progress')")
      message("  \u2713 Reset autoincrement counters")

    } else {
      stop("Unsupported database driver: ", driver)
    }

    message("\n")
    message(crayon::bold(crayon::green("\u2713 All tasker data has been purged successfully")))
    message("The schema structure remains intact and ready for new task registrations.")
    message("\n")

    TRUE

  }, error = function(e) {
    message("\n")
    message(crayon::bold(crayon::red("\u2717 Error purging tasker data:")))
    message(e$message)
    FALSE
  })
}
