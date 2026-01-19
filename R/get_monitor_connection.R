#' Get or create database connection for monitoring
#'
#' Creates a new database connection or returns an existing valid connection
#' for monitoring database queries. Supports PostgreSQL and MySQL databases.
#'
#' @param config Configuration list (default: getOption("tasker.config"))
#' @param session_con Existing connection to reuse if valid (optional)
#'
#' @return DBI database connection
#' @export
#'
#' @examples
#' \dontrun{
#' config <- tasker_config()
#' con <- get_monitor_connection(config)
#' # ... use connection ...
#' 
#' # Reuse connection
#' con <- get_monitor_connection(config, con)
#' }
get_monitor_connection <- function(config = NULL, session_con = NULL) {
  if (is.null(config)) {
    config <- getOption("tasker.config")
  }
  
  if (is.null(config)) {
    stop("Tasker configuration not loaded", call. = FALSE)
  }
  
  # Return existing connection if valid
  if (!is.null(session_con) && DBI::dbIsValid(session_con)) {
    return(session_con)
  }
  
  # Create new connection based on database type
  db_type <- if (is.null(config$database$driver)) "postgresql" else config$database$driver
  
  if (db_type == "postgresql") {
    if (!requireNamespace("RPostgres", quietly = TRUE)) {
      stop("RPostgres package required for PostgreSQL", call. = FALSE)
    }
    con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host     = config$database$host,
      port     = config$database$port,
      dbname   = config$database$dbname,
      user     = config$database$user,
      password = config$database$password
    )
  } else if (db_type == "mysql") {
    if (!requireNamespace("RMariaDB", quietly = TRUE)) {
      stop("RMariaDB package required for MySQL", call. = FALSE)
    }
    con <- DBI::dbConnect(
      RMariaDB::MariaDB(),
      host     = config$database$host,
      port     = config$database$port,
      dbname   = config$database$dbname,
      user     = config$database$user,
      password = config$database$password
    )
  } else if (db_type == "sqlite") {
    if (!requireNamespace("RSQLite", quietly = TRUE)) {
      stop("RSQLite package required for SQLite", call. = FALSE)
    }
    con <- DBI::dbConnect(
      RSQLite::SQLite(),
      dbname = config$database$dbname
    )
  } else {
    stop(sprintf("Unsupported database type: %s", db_type), call. = FALSE)
  }
  
  return(con)
}
