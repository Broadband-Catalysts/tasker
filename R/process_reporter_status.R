#' Get process reporter status
#'
#' Checks if a process reporter is running on a specific host.
#'
#' @param hostname Check specific host (NULL = current host)
#' @param con Database connection (NULL = get default)
#'
#' @return Data frame with reporter status or NULL if not running
#' @export
#'
#' @examples
#' \dontrun{
#' status <- get_process_reporter_status()
#' if (!is.null(status)) {
#'   cat("Reporter running, PID:", status$process_id, "\n")
#' }
#' }
get_process_reporter_status <- function(hostname = NULL, con = NULL) {
  
  if (is.null(hostname)) {
    hostname <- Sys.info()["nodename"]
  }
  
  close_con <- FALSE
  if (is.null(con)) {
    con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (is.null(con)) return(NULL)
    close_con <- TRUE
  }
  
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  result <- tryCatch({
    table_name <- get_table_name("process_reporter_status", con, char = TRUE)
    sql <- sprintf("
      SELECT 
        hostname,
        process_id,
        started_at,
        last_heartbeat,
        version,
        shutdown_requested
      FROM %s
      WHERE hostname = ?
    ", table_name)
    DBI::dbGetQuery(con, sql, params = list(hostname))
  }, error = function(e) {
    warning("Failed to query reporter status: ", e$message)
    return(NULL)
  })
  
  if (is.null(result) || nrow(result) == 0) {
    return(NULL)
  }
  
  return(result)
}


#' Register or update process reporter in database
#'
#' Internal function to register a reporter or update its registration.
#' Uses UPSERT to handle concurrent starts.
#'
#' @param con Database connection
#' @param hostname Reporter hostname
#' @param process_id Reporter PID
#' @param version Package version
#'
#' @return TRUE on success
#' @keywords internal
register_reporter <- function(
    con,
    hostname,
    process_id,
    version = as.character(packageVersion("tasker"))
) {
  
# Generate parameter placeholders based on database type  
  db_class <- class(con)[1]
  if (db_class == "PqConnection") {
    # PostgreSQL uses $1, $2, etc.
    placeholders <- c("$1", "$2", "$3")
  } else {
    # SQLite, MySQL, and others use ?
    placeholders <- c("?", "?", "?")
  }
  
  sql <- paste0("
    INSERT INTO ", get_table_name('process_reporter_status', con, char = TRUE), "
      (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested)
    VALUES (", placeholders[1], ", ", placeholders[2], ", ", 
           if (db_class == "SQLiteConnection") "datetime('now')" else "NOW()", ", ",
           if (db_class == "SQLiteConnection") "datetime('now')" else "NOW()", ", ",
           placeholders[3], ", ", if (db_class == "SQLiteConnection") "0" else "FALSE", ")
    ON CONFLICT (hostname) DO UPDATE SET
      process_id = EXCLUDED.process_id,
      started_at = EXCLUDED.started_at,
      last_heartbeat = EXCLUDED.last_heartbeat,
      version = EXCLUDED.version,
      shutdown_requested = ", if (db_class == "SQLiteConnection") "0" else "FALSE", "
  ")
  
  DBI::dbExecute(con, sql, params = list(hostname, process_id, version))
  
  TRUE
}


#' Update reporter heartbeat timestamp
#'
#' Internal function to update the last_heartbeat timestamp for a reporter.
#'
#' @param con Database connection
#' @param hostname Reporter hostname
#'
#' @return Number of rows updated
#' @keywords internal
update_reporter_heartbeat <- function(con, hostname) {
  
  table_name <- get_table_name("process_reporter_status", con, char = TRUE)
  
  # Database-specific NOW() function
  config <- getOption("tasker.config")
  if (!is.null(config) && config$database$driver == "sqlite") {
    sql <- sprintf("
      UPDATE %s
      SET last_heartbeat = datetime('now')
      WHERE hostname = ?
    ", table_name)
  } else {
    sql <- sprintf("
      UPDATE %s
      SET last_heartbeat = NOW()
      WHERE hostname = $1
    ", table_name)
  }
  
  DBI::dbExecute(con, sql, params = list(hostname))
}


#' Stop process reporter
#'
#' Stops a running process reporter by setting shutdown flag in database.
#'
#' @param hostname Which reporter to stop (default: current host)
#' @param timeout Seconds to wait for graceful shutdown (default: 30)
#' @param con Database connection (NULL = get default)
#'
#' @return TRUE if stopped successfully, FALSE otherwise
#' @export
#'
#' @examples
#' \dontrun{
#' # Stop reporter on current host
#' stop_process_reporter()
#' 
#' # Stop reporter on specific host
#' stop_process_reporter(hostname = "server1")
#' }
stop_process_reporter <- function(
    hostname = Sys.info()["nodename"],
    timeout = 30,
    con = NULL
) {
  
  close_con <- FALSE
  if (is.null(con)) {
    con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (is.null(con)) {
      warning("Cannot connect to database to stop reporter")
      return(FALSE)
    }
    close_con <- TRUE
  }
  
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  # Set shutdown flag
  table_name <- get_table_name("process_reporter_status", con, char = TRUE)
  
  config <- getOption("tasker.config")
  if (!is.null(config) && config$database$driver == "sqlite") {
    sql <- sprintf("
      UPDATE %s
      SET shutdown_requested = 1
      WHERE hostname = ?
    ", table_name)
  } else {
    sql <- sprintf("
      UPDATE %s
      SET shutdown_requested = TRUE
      WHERE hostname = $1
    ", table_name)
  }
  
  DBI::dbExecute(con, sql, params = list(hostname))
  # Wait for reporter to exit
  start_time <- Sys.time()
  while (difftime(Sys.time(), start_time, units = "secs") < timeout) {
    status <- get_process_reporter_status(hostname, con)
    if (is.null(status)) {
      message("Reporter stopped successfully")
      return(TRUE)
    }
    Sys.sleep(1)
  }
  
  warning("Reporter did not stop within ", timeout, " seconds")
  return(FALSE)
}
