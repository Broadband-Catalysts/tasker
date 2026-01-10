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


# get_placeholder and build_sql are defined in utils.R
