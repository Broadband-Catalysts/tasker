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
  db_type <- config$database$driver %||% "postgresql"
  
  if (db_type == "postgresql") {
    if (!requireNamespace("RPostgres", quietly = TRUE)) {
      stop("RPostgres package required for PostgreSQL", call. = FALSE)
    }
    con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = config$database$host,
      port = config$database$port,
      dbname = config$database$dbname,
      user = config$database$user,
      password = config$database$password
    )
  } else if (db_type == "mysql") {
    if (!requireNamespace("RMySQL", quietly = TRUE)) {
      stop("RMySQL package required for MySQL", call. = FALSE)
    }
    con <- DBI::dbConnect(
      RMySQL::MySQL(),
      host = config$database$host,
      port = config$database$port,
      dbname = config$database$dbname,
      user = config$database$user,
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


#' Get list of active database queries
#'
#' Executes database-specific SQL to retrieve currently running queries.
#' Supports PostgreSQL (pg_stat_activity) and MySQL (SHOW FULL PROCESSLIST).
#' SQLite returns empty data frame (does not support query monitoring).
#'
#' @param con DBI database connection
#' @param db_type Database type: "postgresql", "mysql", or "sqlite" (default: from config)
#'
#' @return Data frame with active queries (may be empty). Columns: pid, duration, username, query, state
#' @export
#'
#' @examples
#' \dontrun{
#' config <- tasker_config()
#' con <- get_monitor_connection(config)
#' queries <- get_database_queries(con)
#' print(queries)
#' }
get_database_queries <- function(con, db_type = NULL) {
  if (is.null(db_type)) {
    config <- getOption("tasker.config")
    db_type <- config$database$driver %||% "postgresql"
  }
  
  if (db_type == "postgresql") {
    query_sql <- "
      SELECT 
        pid,
        (now() - query_start)::text as duration,
        usename as username,
        query,
        state
      FROM pg_stat_activity
      WHERE state != 'idle'
        AND pid != pg_backend_pid()
      ORDER BY query_start
    "
    queries <- DBI::dbGetQuery(con, query_sql)
    return(queries)
  } else if (db_type == "mysql") {
    query_sql <- "SHOW FULL PROCESSLIST"
    queries <- DBI::dbGetQuery(con, query_sql)
    return(queries)
  } else if (db_type == "sqlite") {
    # SQLite is an embedded database without multi-user support
    # Return empty data frame with standard query columns
    return(data.frame(
      pid = integer(0),
      duration = character(0),
      username = character(0),
      query = character(0),
      state = character(0),
      stringsAsFactors = FALSE
    ))
  } else {
    stop(sprintf("Unsupported database type: %s", db_type), call. = FALSE)
  }
}
