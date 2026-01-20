#' Update reporter heartbeat timestamp
#'
#' Internal function to update the last_heartbeat timestamp for a reporter.
#'
#' @param con Database connection
#' @param hostname Reporter hostname
#'
#' @return TRUE if successful, FALSE otherwise
#' @keywords internal
update_reporter_heartbeat <- function(con, hostname) {
  tryCatch({
    table_name <- get_table_name("reporter_status", con, char = TRUE)
    current_pid <- Sys.getpid()
    current_time_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    version <- as.character(utils::packageVersion("tasker"))
    config <- getOption("tasker.config")

    if (!is.null(config) && config$database$driver == "sqlite") {
      check_sql <- sprintf("SELECT process_id, started_at FROM %s WHERE hostname = ?", table_name)
      check_params <- list(hostname)
    } else {
      check_sql <- sprintf("SELECT process_id, started_at FROM %s WHERE hostname = $1", table_name)
      check_params <- list(hostname)
    }

    existing <- tryCatch(DBI::dbGetQuery(con, check_sql, params = check_params), error = function(e) data.frame(process_id = integer(0), started_at = character(0)))
    need_replace <- nrow(existing) == 0 || existing$process_id[1] != current_pid

    if (need_replace) {
      DBI::dbBegin(con)
      tryCatch({
        if (!is.null(config) && config$database$driver == "sqlite") {
          DBI::dbExecute(con, sprintf("DELETE FROM %s WHERE hostname = ?", table_name), params = list(hostname))
          host_lit <- DBI::dbQuoteString(con, hostname)
          ver_lit <- DBI::dbQuoteString(con, version)
          DBI::dbExecute(con, sprintf("INSERT INTO %s (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested) VALUES (%s, %d, datetime('now'), datetime('now'), %s, 0)", table_name, host_lit, as.integer(current_pid), ver_lit))
        } else {
          DBI::dbExecute(con, sprintf("DELETE FROM %s WHERE hostname = $1", table_name), params = list(hostname))
          insert_sql <- sprintf("INSERT INTO %s (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested) VALUES ($1, $2, $3, $4, $5, FALSE)", table_name)
          DBI::dbExecute(con, insert_sql, params = list(hostname, current_pid, current_time_str, current_time_str, version))
        }
        DBI::dbCommit(con)
      }, error = function(e) { DBI::dbRollback(con); stop("Transaction failed: ", e$message) })
    } else {
      if (!is.null(config) && config$database$driver == "sqlite") {
        ver_lit <- DBI::dbQuoteString(con, version)
        host_lit <- DBI::dbQuoteString(con, hostname)
        DBI::dbExecute(con, sprintf("UPDATE %s SET last_heartbeat = datetime('now'), version = %s WHERE hostname = %s AND process_id = %d", table_name, ver_lit, host_lit, as.integer(current_pid)))
      } else {
        update_sql <- sprintf("UPDATE %s SET last_heartbeat = NOW(), version = $1 WHERE hostname = $2 AND process_id = $3", table_name)
        DBI::dbExecute(con, update_sql, params = list(version, hostname, current_pid))
      }
    }
    TRUE
  }, error = function(e) { warning("Failed to update reporter heartbeat: ", e$message); FALSE })
}
