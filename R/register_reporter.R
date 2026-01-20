#' Register or update reporter in database
#'
#' Internal function to register a reporter or update its registration.
#' Uses UPSERT to handle concurrent starts.
#'
#' @param con Database connection
#' @param hostname Reporter hostname
#' @param process_id Reporter PID
#' @param version Package version
#'
#' @return TRUE on success
#' @keywords internal
register_reporter <- function(con, hostname, process_id, version = as.character(packageVersion("tasker"))) {
  db_class <- class(con)[1]
  placeholders <- if (db_class == "PqConnection") c("$1","$2","$3") else c("?","?","?")
  sql <- paste0("INSERT INTO ", get_table_name('reporter_status', con, char = TRUE), " (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested) VALUES (", placeholders[1], ", ", placeholders[2], ", ", if (db_class == "SQLiteConnection") "datetime('now')" else "NOW()", ", ", if (db_class == "SQLiteConnection") "datetime('now')" else "NOW()", ", ", placeholders[3], ", ", if (db_class == "SQLiteConnection") "0" else "FALSE", ") ON CONFLICT (hostname) DO UPDATE SET process_id = EXCLUDED.process_id, started_at = EXCLUDED.started_at, last_heartbeat = EXCLUDED.last_heartbeat, version = EXCLUDED.version, shutdown_requested = ", if (db_class == "SQLiteConnection") "0" else "FALSE")
  DBI::dbExecute(con, sql, params = list(hostname, process_id, version))
  TRUE
}
