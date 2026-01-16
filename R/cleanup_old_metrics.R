#' Cleanup Old Process Metrics
#'
#' Removes process metrics older than the specified retention period.
#' Implements the retention policy by deleting metrics for tasks completed 
#' more than `retention_days` ago. Records deletion in retention tracking table.
#'
#' @param retention_days Number of days to retain metrics after task completion (default: 30)
#' @param conn Database connection. If NULL, uses default tasker connection  
#' @param dry_run If TRUE, return what would be deleted without actually deleting (default: FALSE)
#' @param quiet Suppress progress messages (default: FALSE)
#' Cleanup Old Process Metrics
#'
#' Removes process metrics older than the specified retention period.
#' Implements the retention policy by deleting metrics for tasks completed
#' more than `retention_days` ago. Records deletion in retention tracking table.
#'
#' @param retention_days Number of days to retain metrics after task completion (default: 30)
#' @param conn Database connection. If NULL, uses default tasker connection
#' @param dry_run If TRUE, return what would be deleted without actually deleting (default: FALSE)
#' @param quiet Suppress progress messages (default: FALSE)
#'
#' @return Data frame with columns: run_id, task_name, metrics_deleted_count,
#'   completed_at, deleted_at
#' @export
cleanup_old_metrics <- function(retention_days = 30,
																conn = NULL,
																dry_run = FALSE,
																quiet = FALSE) {
	if (is.null(conn)) {
		conn <- get_tasker_db_connection()
		close_conn <- TRUE
		on.exit({
			if (close_conn && !is.null(conn) && DBI::dbIsValid(conn)) DBI::dbDisconnect(conn)
		})
	} else {
		close_conn <- FALSE
	}

	config <- get_tasker_config()
	driver <- config$database$driver

	task_runs_table <- get_table_name("task_runs", conn)
	tasks_table <- get_table_name("tasks", conn)
	process_metrics_table <- get_table_name("process_metrics", conn)
	process_metrics_retention_table <- get_table_name("process_metrics_retention", conn)

	cutoff_sql <- if (driver == "sqlite") {
		"datetime('now', '-' || ? || ' days')"
	} else {
		"NOW() - INTERVAL '1 day' * ?"
	}

	metrics_deleted_false_sql <- if (driver == "sqlite") "0" else "FALSE"

	eligible_tasks_sql <- glue::glue_sql(
		"SELECT tr.run_id, tr.end_time, t.task_name, COUNT(pm.metric_id) AS metrics_count\n",
		"FROM {task_runs_table} tr\n",
		"JOIN {tasks_table} t ON tr.task_id = t.task_id\n",
		"LEFT JOIN {process_metrics_table} pm ON tr.run_id = pm.run_id\n",
		"LEFT JOIN {process_metrics_retention_table} pr ON tr.run_id = pr.run_id\n",
		"WHERE tr.status IN ('COMPLETED','FAILED','CANCELLED')\n",
		"  AND tr.end_time IS NOT NULL\n",
		"  AND tr.end_time < {DBI::SQL(cutoff_sql)}\n",
		"  AND (pr.metrics_deleted IS NULL OR pr.metrics_deleted = {DBI::SQL(metrics_deleted_false_sql)})\n",
		"GROUP BY tr.run_id, tr.end_time, t.task_name\n",
		"ORDER BY tr.end_time",
		.con = conn
	)

	eligible_tasks <- DBI::dbGetQuery(conn, eligible_tasks_sql, params = list(retention_days))

	if (nrow(eligible_tasks) == 0) {
		if (!quiet) message("[Process Reporter] No old metrics found to cleanup")
		return(data.frame(run_id = character(0), task_name = character(0), metrics_deleted_count = integer(0), completed_at = character(0), deleted_at = character(0), stringsAsFactors = FALSE))
	}

	if (dry_run) {
		return(data.frame(
			run_id = eligible_tasks$run_id,
			task_name = eligible_tasks$task_name,
			metrics_deleted_count = eligible_tasks$metrics_count,
			completed_at = as.character(eligible_tasks$end_time),
			deleted_at = NA_character_,
			stringsAsFactors = FALSE
		))
	}

	result_list <- list()
	for (i in seq_len(nrow(eligible_tasks))) {
		task <- eligible_tasks[i, , drop = FALSE]
		DBI::dbBegin(conn)
		success <- FALSE
		tryCatch({
			delete_sql <- glue::glue_sql("DELETE FROM {process_metrics_table} WHERE run_id = ?", .con = conn)
			deleted_count <- DBI::dbExecute(conn, delete_sql, params = list(task$run_id))

			# record retention (mark as deleted and record deleted_at)
			if (driver == "sqlite") {
				delete_after_val <- as.character(as.POSIXct(task$end_time, tz = "UTC") + as.difftime(retention_days, units = "days"))
				retention_upsert_sql <- glue::glue_sql(
					"INSERT OR REPLACE INTO {process_metrics_retention_table} (run_id, task_completed_at, metrics_delete_after, metrics_deleted, deleted_at, metrics_count) VALUES (?, ?, ?, 1, datetime('now'), ?)",
					.con = conn
				)
				DBI::dbExecute(conn, retention_upsert_sql, params = list(task$run_id, as.character(task$end_time), delete_after_val, deleted_count))
			} else {
				retention_upsert_sql <- glue::glue_sql(
					"INSERT INTO {process_metrics_retention_table} (run_id, task_completed_at, metrics_delete_after, metrics_deleted, deleted_at, metrics_count) VALUES (?, ?, ? + INTERVAL '1 day' * ?, TRUE, NOW(), ?) ON CONFLICT (run_id) DO UPDATE SET metrics_deleted = TRUE, deleted_at = NOW(), metrics_count = EXCLUDED.metrics_count",
					.con = conn
				)
				DBI::dbExecute(conn, retention_upsert_sql, params = list(task$run_id, task$end_time, task$end_time, retention_days, deleted_count))
			}

			DBI::dbCommit(conn)
			success <- TRUE
			result_list[[i]] <- data.frame(run_id = task$run_id, task_name = task$task_name, metrics_deleted_count = deleted_count, completed_at = as.character(task$end_time), deleted_at = as.character(Sys.time()), stringsAsFactors = FALSE)
		}, error = function(e) {
			DBI::dbRollback(conn)
			result_list[[i]] <- data.frame(run_id = task$run_id, task_name = task$task_name, metrics_deleted_count = 0, completed_at = as.character(task$end_time), deleted_at = NA_character_, stringsAsFactors = FALSE)
		})
	}

	result <- do.call(rbind, result_list)
	if (!quiet) message(sprintf("[Process Reporter] Cleanup complete: deleted %d metrics from %d tasks", sum(result$metrics_deleted_count, na.rm = TRUE), nrow(result)))
	return(result)
}


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