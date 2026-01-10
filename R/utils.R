# Internal utility functions for tasker package

#' Get table name with or without schema
#' @param table Table name
#' @param conn Database connection
#' @return SQL identifier with schema prefix if applicable
#' @keywords internal
get_table_name <- function(table, conn) {
  config <- getOption("tasker.config")
  if (is.null(config) || is.null(config$database) || is.null(config$database$driver)) {
    stop("tasker configuration not loaded. Call load_tasker_config() first.")
  }
  
  db_driver <- config$database$driver
  
  if (db_driver == "sqlite") {
    return(DBI::SQL(table))
  } else {
    schema <- config$database$schema
    if (is.null(schema) || nchar(schema) == 0) {
      return(DBI::SQL(table))
    }
    return(DBI::SQL(sprintf("%s.%s", schema, table)))
  }
}


#' Create standardized tasker error with consistent formatting
#' @param message Error message
#' @param context Additional context about where error occurred
#' @param call Whether to include call information
#' @keywords internal
tasker_error <- function(message, context = NULL, call = FALSE) {
  full_message <- if (!is.null(context)) {
    sprintf("[tasker:%s] %s", context, message)
  } else {
    sprintf("[tasker] %s", message)
  }
  stop(full_message, call. = call)
}


#' Validate and clean run_id parameter
#' @param run_id Run ID to validate
#' @return Cleaned run_id or error
#' @keywords internal
validate_run_id <- function(run_id) {
  if (is.null(run_id)) {
    return(NULL)
  }
  
  if (!is.character(run_id) || length(run_id) != 1 || nchar(trimws(run_id)) == 0) {
    tasker_error("'run_id' must be a non-empty character string")
  }
  
  # Basic UUID format validation
  uuid_pattern <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  if (!grepl(uuid_pattern, run_id, ignore.case = TRUE)) {
    warning("'run_id' does not appear to be a valid UUID format", call. = FALSE)
  }
  
  trimws(run_id)
}


#' Get parent process ID
#' @return Parent PID or NULL
#' @keywords internal
get_parent_pid <- function() {
  tryCatch({
    if (.Platform$OS.type == "unix") {
      ppid <- system2("ps", c("-o", "ppid=", "-p", Sys.getpid()), 
                      stdout = TRUE, stderr = FALSE)
      as.integer(trimws(ppid))
    } else {
      NULL
    }
  }, error = function(e) NULL)
}


#' Get SQL placeholder for parameter
#' 
#' Returns the correct parameter placeholder syntax for the database
#' 
#' @param n Parameter number (1-based)
#' @param conn Database connection (optional)
#' @return Placeholder string ("$1" for PostgreSQL, "?" for SQLite/MySQL)
#' @keywords internal
get_placeholder <- function(n = NULL, conn = NULL) {
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  if (driver == "postgresql") {
    if (is.null(n)) return("$")
    return(paste0("$", n))
  } else {
    # SQLite and MySQL use ?
    return("?")
  }
}


#' Build parameterized SQL with correct placeholders
#' 
#' Replaces $1, $2, etc. with correct placeholders for the database
#' 
#' @param sql SQL string with $1, $2, ... placeholders
#' @param conn Database connection (optional)
#' @return SQL string with correct placeholders
#' @keywords internal
build_sql <- function(sql, conn = NULL) {
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  if (driver == "sqlite" || driver == "mysql") {
    # Replace $1, $2, ... with ?
    sql <- gsub("\\$[0-9]+", "?", sql)
  }
  
  sql
}



# These functions are defined in tasker_config.R
