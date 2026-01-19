# Manual test script for Reporter Monitor Integration
# Run this to verify the monitor integration works correctly

library(tasker)

# This script tests the complete flow:
# 1. Setup reporter schema (if not already done)
# 2. Create a test task
# 3. Start reporter
# 4. Verify monitor can read metrics

message("=== Testing Reporter Monitor Integration ===\n")

# Step 1: Ensure reporter schema exists
message("1. Setting up reporter schema...")
tryCatch({
  tasker::setup_process_reporter_schema()
  message("   ✓ Schema setup complete\n")
}, error = function(e) {
  message("   Note: ", e$message, "\n")
})

# Step 2: Get connection and verify views exist
message("2. Verifying database views...")
con <- tasker::get_db_connection()

# Check for current_task_status_with_metrics view
config <- getOption("tasker.config")
driver <- config$database$driver

if (driver == "postgresql") {
  schema <- config$database$schema %||% "tasker"
  views <- DBI::dbGetQuery(con, sprintf(
    "SELECT table_name FROM information_schema.views WHERE table_schema = '%s'",
    schema
  ))
  
  has_metrics_view <- "current_task_status_with_metrics" %in% views$table_name
  has_reporter_tables <- DBI::dbExistsTable(con, DBI::Id(schema = schema, table = "process_metrics"))
  
} else {
  views <- DBI::dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type='view'")
  has_metrics_view <- "current_task_status_with_metrics" %in% views$name
  has_reporter_tables <- DBI::dbExistsTable(con, "process_metrics")
}

if (has_metrics_view) {
  message("   ✓ current_task_status_with_metrics view exists")
} else {
  message("   ✗ current_task_status_with_metrics view MISSING")
  message("   Run: tasker::setup_tasker_db(force = TRUE)")
}

if (has_reporter_tables) {
  message("   ✓ process_metrics table exists")
} else {
  message("   ✗ process_metrics table MISSING")
  message("   Run: tasker::setup_process_reporter_schema()")
}

message("")

# Step 3: Test get_task_status() returns metrics columns
message("3. Testing get_task_status() with metrics...")
tryCatch({
  status <- tasker::get_task_status()
  
  # Check for metrics columns
  metrics_cols <- c("cpu_percent", "memory_mb", "child_count", 
                    "collection_error", "metrics_age_seconds")
  has_cols <- metrics_cols %in% names(status)
  
  if (all(has_cols)) {
    message("   ✓ All metrics columns present in get_task_status()")
    message("   Columns: ", paste(metrics_cols[has_cols], collapse = ", "))
  } else {
    message("   ⚠ Some metrics columns missing:")
    message("   Missing: ", paste(metrics_cols[!has_cols], collapse = ", "))
  }
  
  # Show sample if we have running tasks with metrics
  running_with_metrics <- status[status$status %in% c("RUNNING", "STARTED") & 
                                  !is.na(status$cpu_percent), ]
  
  if (nrow(running_with_metrics) > 0) {
    message("\n   Sample running task metrics:")
    task <- running_with_metrics[1, ]
    message(sprintf("   - Task: %s/%s", task$stage_name, task$task_name))
    message(sprintf("   - CPU: %.1f%%", task$cpu_percent))
    message(sprintf("   - Memory: %.1f MB", task$memory_mb))
    message(sprintf("   - Children: %d", task$child_count %||% 0))
    message(sprintf("   - Metrics age: %d seconds", task$metrics_age_seconds %||% -1))
  }
  
}, error = function(e) {
  message("   ✗ Error: ", e$message)
})

message("")

# Step 4: Check reporter status
message("4. Checking reporter status...")
reporter_status <- tasker::get_reporter_status()

if (!is.null(reporter_status) && nrow(reporter_status) > 0) {
  message(sprintf("   ✓ Process reporter running on %s (PID: %d)", 
                  reporter_status$hostname, reporter_status$process_id))
  
  # Check heartbeat age
  heartbeat_age <- as.numeric(difftime(Sys.time(), reporter_status$last_heartbeat, units = "secs"))
  if (heartbeat_age < 30) {
    message(sprintf("   ✓ Heartbeat is fresh (%.0f seconds ago)", heartbeat_age))
  } else {
    message(sprintf("   ⚠ Heartbeat is stale (%.0f seconds ago)", heartbeat_age))
  }
} else {
  message("   ⚠ Process reporter not running")
  message("   To start: tasker::start_process_reporter()")
}

message("")

# Cleanup
DBI::dbDisconnect(con)

message("=== Test Complete ===")
message("\nTo test the Shiny monitor UI:")
message("  1. Start a task: tasker::task_start('TEST', 'Sample Task')")
message("  2. Launch monitor: tasker::run_monitor()")
message("  3. Check that metrics are displayed in the Process Info pane")
message("  4. Verify warning banners appear for stale/missing metrics")
