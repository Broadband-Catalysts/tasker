#' Get database connection
#'
#' Uses connection pool if available (set via options(tasker.pool = pool)),
#' otherwise creates a new connection.
#'
#' @return DBI connection object (or pool object that behaves like a connection)
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- get_db_connection()
#' # If not using pool, disconnect when done:
#' # DBI::dbDisconnect(conn)
#' }
get_db_connection <- function() {
  ensure_configured()
  
  # Check for connection pool first (set by Shiny app)
  pool <- getOption("tasker.pool", default = NULL)
  if (!is.null(pool)) {
    # Return pool object - it can be used like a regular connection
    # Pool automatically manages checkout/return
    return(pool)
  }
  
  # No pool available, create individual connection
  config <- getOption("tasker.config")
  db <- config$database
  
  if (db$driver == "postgresql") {
    if (!requireNamespace("RPostgres", quietly = TRUE)) {
      stop("Package 'RPostgres' required. Install with: install.packages('RPostgres')")
    }
    
    conn <- DBI::dbConnect(
      RPostgres::Postgres(),
      host     = db$host,
      port     = db$port,
      dbname   = db$dbname,
      user     = db$user,
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
      host     = db$host,
      port     = db$port,
      dbname   = db$dbname,
      user     = db$user,
      password = db$password
    )
    
  } else {
    stop("Unsupported driver: ", db$driver)
  }
  
  conn
}

#' Safely close a database connection
#'
#' Closes a database connection, but only if it's not a Pool object.
#' Pool objects should not be disconnected as they manage their own lifecycle.
#' Also checks if connection is valid before attempting to close.
#'
#' @param conn Database connection to close
#' @return TRUE if connection was closed (or was Pool), FALSE otherwise
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- get_db_connection()
#' # ... do work ...
#' safe_disconnect(conn)
#' }
safe_disconnect <- function(conn) {
  # Don't close Pool objects - they manage their own lifecycle
  if (inherits(conn, "Pool")) {
    return(TRUE)
  }
  
  # Check if connection is valid before closing
  if (!is.null(conn) && DBI::dbIsValid(conn)) {
    tryCatch({
      DBI::dbDisconnect(conn)
      TRUE
    }, error = function(e) {
      warning("Error disconnecting: ", e$message)
      FALSE
    })
  } else {
    TRUE
  }
}


# get_placeholder and build_sql are defined in utils.R
