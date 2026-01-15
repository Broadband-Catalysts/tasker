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
  
  # Build INSERT statement with all fields
  sql <- "
    INSERT INTO tasker.process_metrics (
      run_id, timestamp, process_id, hostname, is_alive, process_start_time,
      cpu_percent, memory_mb, memory_percent, memory_vms_mb, swap_mb,
      read_bytes, write_bytes, read_count, write_count, io_wait_percent,
      open_files, num_fds, num_threads,
      page_faults_minor, page_faults_major,
      num_ctx_switches_voluntary, num_ctx_switches_involuntary,
      child_count, child_total_cpu_percent, child_total_memory_mb,
      collection_error, error_message, error_type,
      reporter_version, collection_duration_ms
    ) VALUES (
      $1, NOW(), $2, $3, $4, $5,
      $6, $7, $8, $9, $10,
      $11, $12, $13, $14, $15,
      $16, $17, $18,
      $19, $20,
      $21, $22,
      $23, $24, $25,
      $26, $27, $28,
      $29, $30
    )
    RETURNING metric_id
  "
  
  # Helper to get value or NULL
  get_val <- function(name, default = NA) {
    val <- metrics_data[[name]]
    if (is.null(val) || (length(val) == 1 && is.na(val))) default else val
  }
  
  params <- list(
    metrics_data$run_id,                              # $1
    metrics_data$process_id,                          # $2
    metrics_data$hostname,                            # $3
    get_val("is_alive", TRUE),                        # $4
    get_val("process_start_time", NULL),              # $5
    get_val("cpu_percent", NULL),                     # $6
    get_val("memory_mb", NULL),                       # $7
    get_val("memory_percent", NULL),                  # $8
    get_val("memory_vms_mb", NULL),                   # $9
    get_val("swap_mb", NULL),                         # $10
    get_val("read_bytes", NULL),                      # $11
    get_val("write_bytes", NULL),                     # $12
    get_val("read_count", NULL),                      # $13
    get_val("write_count", NULL),                     # $14
    get_val("io_wait_percent", NULL),                 # $15
    get_val("open_files", NULL),                      # $16
    get_val("num_fds", NULL),                         # $17
    get_val("num_threads", NULL),                     # $18
    get_val("page_faults_minor", NULL),               # $19
    get_val("page_faults_major", NULL),               # $20
    get_val("num_ctx_switches_voluntary", NULL),      # $21
    get_val("num_ctx_switches_involuntary", NULL),    # $22
    get_val("child_count", 0),                        # $23
    get_val("child_total_cpu_percent", NULL),         # $24
    get_val("child_total_memory_mb", NULL),           # $25
    get_val("collection_error", FALSE),               # $26
    get_val("error_message", NULL),                   # $27
    get_val("error_type", NULL),                      # $28
    get_val("reporter_version", NULL),                # $29
    get_val("collection_duration_ms", NULL)           # $30
  )
  
  result <- DBI::dbGetQuery(con, sql, params = params)
  
  invisible(result$metric_id[1])
}
