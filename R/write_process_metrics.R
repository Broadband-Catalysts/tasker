#' Write process metrics to database
#'
#' Writes collected process metrics to the process_metrics table.
#' Handles both successful metrics and collection errors.
#'
#' @param metrics_data Output from collect_process_metrics()
#' @param con Database connection (NULL = get default connection)
#'
#' @return metric_id of inserted row (invisible)
#' @export
#'
#' @examples
#' \dontrun{
#' metrics <- collect_process_metrics(run_id, process_id)
#' write_process_metrics(metrics)
#' }
write_process_metrics <- function(metrics_data, con = NULL) {
  
  close_con <- FALSE
  if (is.null(con)) {
    con <- get_db_connection()
    close_con <- TRUE
  }
  
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  # Generate parameter placeholders and SQL based on database type  
  db_class <- class(con)[1]
  
  if (db_class == "PqConnection") {
    # PostgreSQL uses $1, $2, etc. (31 parameters, timestamp is auto-generated)
    placeholders <- paste0("$", 1:31)
    timestamp_func <- "NOW()"
    returning_clause <- "RETURNING metric_id"
  } else if (db_class %in% c("MariaDBConnection", "MySQLConnection")) {
    # MySQL/MariaDB use ? placeholders
    placeholders <- rep("?", 31)
    timestamp_func <- "NOW()"
    returning_clause <- ""  # MySQL doesn't support RETURNING
  } else {
    # SQLite and others use ? (31 parameters, timestamp is auto-generated)
    placeholders <- rep("?", 31)
    timestamp_func <- "datetime('now')"
    returning_clause <- "RETURNING metric_id"
  }
  
  # Build INSERT statement with all fields
  sql <- paste0("
    INSERT INTO ", get_table_name('process_metrics', con, char = TRUE), " (
      run_id, timestamp, process_id, hostname, is_alive, process_start_time,
      cpu_percent, cpu_cores, memory_mb, memory_percent, memory_vms_mb, swap_mb,
      read_bytes, write_bytes, read_count, write_count, io_wait_percent,
      open_files, num_fds, num_threads,
      page_faults_minor, page_faults_major,
      num_ctx_switches_voluntary, num_ctx_switches_involuntary,
      child_count, child_total_cpu_percent, child_total_memory_mb,
      collection_error, error_message, error_type,
      reporter_version, collection_duration_ms
    ) VALUES (",
    placeholders[1], ", ", 
    timestamp_func, ", ",
    paste(placeholders[2:31], collapse = ", "),
    ") ",
    returning_clause
  )
  
  # Helper to get value or NULL/NA for database
  get_val <- function(name, default = NA) {
    val <- metrics_data[[name]]
    if (is.null(val) || (length(val) == 1 && is.na(val))) {
      # Return proper database NULL - use NA instead of NULL for DBI
      if (is.null(default)) NA else default
    } else {
      val
    }
  }
  
  params <- list(
    metrics_data$run_id,                              # $1
    metrics_data$process_id,                          # $2  
    metrics_data$hostname,                            # $3
    get_val("is_alive", TRUE),                        # $4
    get_val("process_start_time", NA),                # $5
    get_val("cpu_percent", NA),                       # $6
    get_val("cpu_cores", NA),                        # $7
    get_val("memory_mb", NA),                         # $8
    get_val("memory_percent", NA),                    # $9
    get_val("memory_vms_mb", NA),                     # $9
    get_val("swap_mb", NA),                           # $10
    get_val("read_bytes", NA),                        # $11
    get_val("write_bytes", NA),                       # $12
    get_val("read_count", NA),                        # $13
    get_val("write_count", NA),                       # $14
    get_val("io_wait_percent", NA),                   # $15
    get_val("open_files", NA),                        # $16
    get_val("num_fds", NA),                           # $17
    get_val("num_threads", NA),                       # $18
    get_val("page_faults_minor", NA),                 # $19
    get_val("page_faults_major", NA),                 # $20
    get_val("num_ctx_switches_voluntary", NA),        # $21
    get_val("num_ctx_switches_involuntary", NA),      # $22
    get_val("child_count", 0),                        # $23
    get_val("child_total_cpu_percent", NA),           # $24
    get_val("child_total_memory_mb", NA),             # $25
    get_val("collection_error", FALSE),               # $26
    get_val("error_message", NA),                     # $27
    get_val("error_type", NA),                        # $28
    get_val("reporter_version", NA),                  # $29
    get_val("collection_duration_ms", NA)             # $30
  )
  
  if (db_class %in% c("MariaDBConnection", "MySQLConnection")) {
    # MySQL/MariaDB: Execute INSERT and get LAST_INSERT_ID separately
    DBI::dbExecute(con, sql, params = params)
    result <- DBI::dbGetQuery(con, "SELECT LAST_INSERT_ID() AS metric_id")
  } else {
    # PostgreSQL and SQLite support RETURNING clause
    result <- DBI::dbGetQuery(con, sql, params = params)
  }
  
  invisible(result$metric_id[1])
}
