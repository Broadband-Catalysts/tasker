#' Get list of active database queries
#'
#' Executes database-specific SQL to retrieve currently running queries.
#' Supports PostgreSQL (pg_stat_activity) and MySQL (SHOW FULL PROCESSLIST).
#' SQLite returns empty data frame (does not support query monitoring).
#'
#' @param con DBI database connection
#' @param status Query state filter: "active" (default), "idle", "any", or other pg_stat_activity states
#' @param db_type Database type: "postgresql", "mysql", or "sqlite" (default: from config)
#'
#' @return Data frame with active queries (may be empty). Columns: pid, duration, username, query, state
#' @export
#' @importFrom stringr str_squish
#'
#' @examples
#' \dontrun{
#' config <- tasker_config()
#' con <- get_monitor_connection(config)
#' queries <- get_database_queries(con)
#' queries <- get_database_queries(con, status = "any")
#' print(queries)
#' }
get_database_queries <- function(con, status = "active", db_type = NULL) {
  if (is.null(db_type)) {
    config <- getOption("tasker.config")
    db_type <- if (is.null(config$database$driver)) "postgresql" else config$database$driver
  }
  
  if (db_type == "postgresql") {
    query_sql <- "
      SELECT 
        pid,
        now() - query_start as duration,
        usename as username,
        query,
        state
      FROM pg_stat_activity
      WHERE backend_type != 'parallel worker'
        AND pid != pg_backend_pid()
        AND state IS NOT NULL
      ORDER BY query_start
    "
    queries <- DBI::dbGetQuery(con, query_sql)
    
    # Apply status filtering
    if (status != "any") {
      queries <- queries[queries$state == status, ]
    }
    
    # Clean up query text
    queries$query <- stringr::str_squish(queries$query)
    
    return(queries)
  } else if (db_type == "mysql") {
    query_sql <- "SHOW FULL PROCESSLIST"
    queries <- DBI::dbGetQuery(con, query_sql)
    
    # Apply status filtering if applicable
    if (status != "any" && "State" %in% names(queries)) {
      queries <- queries[queries$State == status, ]
    }
    
    # Clean up query text
    if ("Info" %in% names(queries)) {
      queries$Info <- stringr::str_squish(queries$Info)
    }
    
    return(queries)
  } else if (db_type == "sqlite") {
    # SQLite is an embedded database without multi-user support
    # Return empty data frame with standard query columns
    return(data.frame(
      pid = integer(0),
      duration = numeric(0),
      username = character(0),
      query = character(0),
      state = character(0),
      stringsAsFactors = FALSE
    ))
  } else {
    stop(sprintf("Unsupported database type: %s", db_type), call. = FALSE)
  }
}
