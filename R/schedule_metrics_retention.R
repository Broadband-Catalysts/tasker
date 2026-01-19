#' Schedule Retention for Completed Task
#'
#' Records retention information when a task completes so metrics can be
#' cleaned up after the retention period expires.
#'
#' @param run_id Task run ID that completed
#' @param completed_at Completion timestamp
#' @param retention_days Days to retain metrics (default: 30)
#' @param conn Database connection
#' @keywords internal
schedule_metrics_retention <- function(run_id, completed_at, retention_days = 30, conn = NULL) {
	if (is.null(conn)) {
		conn <- get_tasker_db_connection()
		close_conn <- TRUE
		on.exit({ if (close_conn && !is.null(conn) && DBI::dbIsValid(conn)) DBI::dbDisconnect(conn) })
	} else {
		close_conn <- FALSE
	}

	config <- get_tasker_config()
	driver <- config$database$driver
	process_metrics_retention_table <- get_table_name("process_metrics_retention", conn)

	if (driver == "sqlite") {
		delete_after_val <- as.character(as.POSIXct(completed_at, tz = "UTC") + as.difftime(retention_days, units = "days"))
		sql <- glue::glue_sql("INSERT OR IGNORE INTO {process_metrics_retention_table} (run_id, task_completed_at, metrics_delete_after, metrics_deleted) VALUES (?, ?, ?, 0)", .con = conn)
		DBI::dbExecute(conn, sql, params = list(run_id, as.character(completed_at), delete_after_val))
	} else {
		sql <- glue::glue_sql("INSERT INTO {process_metrics_retention_table} (run_id, task_completed_at, metrics_delete_after, metrics_deleted) VALUES (?, ?, ? + INTERVAL '1 day' * ?, FALSE) ON CONFLICT (run_id) DO NOTHING", .con = conn)
		DBI::dbExecute(conn, sql, params = list(run_id, completed_at, completed_at, retention_days))
	}
}
