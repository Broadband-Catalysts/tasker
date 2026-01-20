#' Stop reporter
#'
#' Stops a running reporter by setting shutdown flag in database.
#'
#' @param hostname Which reporter to stop (default: current host)
#' @param timeout Seconds to wait for graceful shutdown (default: 30)
#' @param con Database connection (NULL = get default)
#'
#' @return TRUE if stopped successfully, FALSE otherwise
#' @export
stop_reporter <- function(hostname = Sys.info()["nodename"], timeout = 30, con = NULL) {
  close_con <- FALSE

  # Establish database connection if not provided
  if (is.null(con)) {
    con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (is.null(con)) {
      warning("Cannot connect to database to stop reporter")
      return(FALSE)
    }
    close_con <- TRUE
  }

  # Ensure connection is cleaned up on exit
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })

  # Validate connection is still valid; reconnect if needed
  if (!DBI::dbIsValid(con)) {
    new_con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (!is.null(new_con)) {
      con <- new_con
      close_con <- TRUE
    } else {
      warning("Cannot obtain valid DB connection to stop reporter")
      return(FALSE)
    }
  }

  # Get reporter_status table name (accounts for schema prefixes)
  table_name <- get_table_name("reporter_status", con, char = TRUE)

  # Determine SQL dialect (SQLite vs PostgreSQL)
  config <- getOption("tasker.config")
  is_sqlite <- !is.null(config) && config$database$driver == "sqlite"

  # Set shutdown flag in database to request graceful shutdown
  shutdown_sql <- if (is_sqlite) {
    sprintf("UPDATE %s SET shutdown_requested = 1 WHERE hostname = ?", table_name)
  } else {
    sprintf("UPDATE %s SET shutdown_requested = TRUE WHERE hostname = $1", table_name)
  }
  DBI::dbExecute(con, shutdown_sql, params = list(hostname))

  # Check if reporter is still running
  reporter_info <- get_reporter_database_status(hostname, con)
  if (is.null(reporter_info)) {
    return(TRUE)  # Already stopped
  }

  reporter_pid <- reporter_info$process_id
  is_same_machine <- tolower(Sys.info()["nodename"]) == tolower(hostname)

  # Poll database for graceful shutdown with timeout
  start_time <- Sys.time()
  while (difftime(Sys.time(), start_time, units = "secs") < timeout) {
    status <- get_reporter_database_status(hostname, con)
    if (is.null(status)) {
      message("Reporter stopped successfully")
      return(TRUE)
    }
    Sys.sleep(1)
  }

  # Force termination if on same machine (graceful shutdown timed out)
  if (is_same_machine) {
    warning(
      "Reporter did not stop within ", timeout,
      " seconds - terminating process ", reporter_pid
    )

    kill_result <- tryCatch({
      # Send SIGTERM first
      system2("kill", args = as.character(reporter_pid), stdout = FALSE, stderr = FALSE)
      Sys.sleep(2)

      # Check if process still exists
      ps_check <- system2(
        "kill",
        args = c("-0", as.character(reporter_pid)),
        stdout = FALSE,
        stderr = FALSE
      )

      # If still alive, send SIGKILL
      if (ps_check == 0) {
        message("Process still alive, sending SIGKILL")
        system2("kill", args = c("-9", as.character(reporter_pid)), stdout = FALSE, stderr = FALSE)
        Sys.sleep(1)
      }

      TRUE
    }, error = function(e) {
      warning("Failed to kill process ", reporter_pid, ": ", e$message)
      FALSE
    })

    # Clean up database record after successful termination
    if (kill_result) {
      cleanup_sql <- if (is_sqlite) {
        sprintf("DELETE FROM %s WHERE hostname = ?", table_name)
      } else {
        sprintf("DELETE FROM %s WHERE hostname = $1", table_name)
      }
      DBI::dbExecute(con, cleanup_sql, params = list(hostname))
      message("Reporter process terminated and database record cleaned up")
      return(TRUE)
    }
  } else {
    warning(
      "Reporter did not stop within ", timeout,
      " seconds (running on different machine)"
    )
  }

  return(FALSE)
}
