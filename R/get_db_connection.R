#' Get database connection
#'
#' @return DBI connection object
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- get_db_connection()
#' DBI::dbDisconnect(conn)
#' }
get_db_connection <- function() {
  ensure_configured()
  
  config <- getOption("tasker.config")
  db <- config$database
  
  if (db$driver == "postgresql") {
    if (!requireNamespace("RPostgres", quietly = TRUE)) {
      stop("Package 'RPostgres' required. Install with: install.packages('RPostgres')")
    }
    
    conn <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = db$host,
      port = db$port,
      dbname = db$dbname,
      user = db$user,
      password = db$password
    )
    
  } else if (db$driver == "sqlite") {
    if (!requireNamespace("RSQLite", quietly = TRUE)) {
      stop("Package 'RSQLite' required. Install with: install.packages('RSQLite')")
    }
    
    conn <- DBI::dbConnect(
      RSQLite::SQLite(),
      dbname = db$dbname
    )
    
  } else if (db$driver == "mysql") {
    if (!requireNamespace("RMariaDB", quietly = TRUE)) {
      stop("Package 'RMariaDB' required. Install with: install.packages('RMariaDB')")
    }
    
    conn <- DBI::dbConnect(
      RMariaDB::MariaDB(),
      host = db$host,
      port = db$port,
      dbname = db$dbname,
      user = db$user,
      password = db$password
    )
    
  } else {
    stop("Unsupported driver: ", db$driver)
  }
  
  conn
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


#' Create tasker database schema
#'
#' @param conn Database connection (optional, will create if NULL)
#' @param schema Schema name (default: from config)
#' @return TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' create_schema()
#' }
create_schema <- function(conn = NULL, schema = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  if (is.null(schema)) {
    config <- getOption("tasker.config")
    schema <- config$database$schema
  }
  
  sql_file <- system.file("sql", "postgresql", "create_schema.sql", 
                          package = "tasker")
  
  if (!file.exists(sql_file)) {
    stop("Schema SQL file not found: ", sql_file)
  }
  
  sql <- readLines(sql_file, warn = FALSE)
  sql <- paste(sql, collapse = "\n")
  sql <- gsub("tasker", schema, sql, fixed = TRUE)
  
  tryCatch({
    DBI::dbExecute(conn, paste0("CREATE SCHEMA IF NOT EXISTS ", schema))
    DBI::dbExecute(conn, sql)
    message("Schema '", schema, "' created successfully")
    TRUE
  }, error = function(e) {
    stop("Failed to create schema: ", e$message)
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
