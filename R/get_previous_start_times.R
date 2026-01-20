#' Get previous process start times for multiple runs (batch query)
#'
#' Efficiently retrieves the most recent process_start_time for multiple run_ids
#' in a single database query. Used for PID reuse detection.
#' 
#' Uses database-specific optimizations:
#' - PostgreSQL: DISTINCT ON (most efficient)
#' - MySQL/MariaDB: Window functions (ROW_NUMBER)
#' - SQLite: Subquery with MAX/GROUP BY
#' - Generic: Correlated subquery (works everywhere)
#'
#' @param con Database connection
#' @param run_ids Vector of run_ids (UUIDs) to query
#'
#' @return Named list where names are run_ids and values are POSIXct start times (or NULL)
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' start_times <- get_previous_start_times(con, c(run_id1, run_id2, run_id3))
#' prev_time <- start_times[[run_id1]]
#' }
get_previous_start_times <- function(con, run_ids) {
  
  if (length(run_ids) == 0) {
    return(list())
  }
  
  # Detect database type
  db_class <- class(con)
  
  # Build database-specific query
  if (any(grepl("Postgres", db_class, ignore.case = TRUE))) {
    # PostgreSQL: Use DISTINCT ON (most efficient)
    table_name <- get_table_name("process_metrics", con, char = TRUE)
    sql <- sprintf("
      SELECT DISTINCT ON (run_id) 
        run_id, 
        process_start_time
      FROM %s
      WHERE run_id = ANY($1)
      ORDER BY run_id, timestamp DESC
    ", table_name)
    params <- list(run_ids)
    
  } else if (any(grepl("MySQL|MariaDB", db_class, ignore.case = TRUE))) {
    # MySQL/MariaDB: Use window functions
    table_name <- get_table_name("process_metrics", con, char = TRUE)
    placeholders <- paste(rep("?", length(run_ids)), collapse = ", ")
    sql <- sprintf("
      SELECT run_id, process_start_time
      FROM (
        SELECT 
          run_id, 
          process_start_time,
          ROW_NUMBER() OVER (PARTITION BY run_id ORDER BY timestamp DESC) as rn
        FROM %s
        WHERE run_id IN (%s)
      ) ranked
      WHERE rn = 1
    ", table_name, placeholders)
    params <- as.list(run_ids)
    
  } else if (any(grepl("SQLite", db_class, ignore.case = TRUE))) {
    # SQLite: Use subquery with MAX/GROUP BY
    table_name <- get_table_name("process_metrics", con, char = TRUE)
    placeholders <- paste(rep("?", length(run_ids)), collapse = ", ")
    sql <- sprintf("
      SELECT pm1.run_id, pm1.process_start_time
      FROM %s pm1
      INNER JOIN (
        SELECT run_id, MAX(timestamp) as max_timestamp
        FROM %s
        WHERE run_id IN (%s)
        GROUP BY run_id
      ) pm2 ON pm1.run_id = pm2.run_id AND pm1.timestamp = pm2.max_timestamp
    ", table_name, table_name, placeholders)
    params <- as.list(run_ids)
    
  } else {
    # Generic fallback: Correlated subquery (works on all SQL databases)
    table_name <- get_table_name("process_metrics", con, char = TRUE)
    placeholders <- paste(rep("?", length(run_ids)), collapse = ", ")
    sql <- sprintf("
      SELECT pm1.run_id, pm1.process_start_time
      FROM %s pm1
      WHERE pm1.run_id IN (%s)
        AND pm1.timestamp = (
          SELECT MAX(pm2.timestamp)
          FROM %s pm2
          WHERE pm2.run_id = pm1.run_id
        )
    ", table_name, placeholders, table_name)
    params <- as.list(run_ids)
  }
  
  result <- tryCatch({
    DBI::dbGetQuery(con, sql, params = params)
  }, error = function(e) {
    warning("Failed to query previous start times: ", e$message)
    return(NULL)
  })
  
  if (is.null(result) || nrow(result) == 0) {
    return(list())
  }
  
  # Convert to named list for fast lookup
  start_times <- as.list(result$process_start_time)
  names(start_times) <- result$run_id
  
  return(start_times)
}
