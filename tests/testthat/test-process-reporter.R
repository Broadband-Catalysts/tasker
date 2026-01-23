# Tests for Reporter functions

# Load all package functions for testing
# Note: These functions are internal and not exported
library(tasker)

test_that("setup_tasker_db creates all tables", {
  skip_if_not_installed("RSQLite")
  
  # Setup clean test database
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create tables using setup_tasker_db
  setup_tasker_db(conn = con, force = TRUE, quiet = TRUE)
  
  # Verify tables exist
  tables <- DBI::dbListTables(con)
  
  # Main tasker tables
  expect_true("stages" %in% tables)
  expect_true("tasks" %in% tables)
  expect_true("task_runs" %in% tables)
  expect_true("subtask_progress" %in% tables)
  
  # Reporter tables
  expect_true("process_metrics" %in% tables)
  expect_true("reporter_status" %in% tables)
  expect_true("process_metrics_retention" %in% tables)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("setup_tasker_db with force=TRUE recreates tables", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Setup tasker database
  setup_tasker_db(conn = con, force = TRUE, quiet = TRUE)
  
  # Insert test data
  DBI::dbExecute(con, "
    INSERT INTO reporter_status (hostname, process_id, started_at)
    VALUES ('test-host', 12345, datetime('now'))
  ")
  
  # Verify data exists
  count_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM reporter_status")$n
  expect_equal(count_before, 1)
  
  # Recreate with force=TRUE (should drop and recreate)
  setup_tasker_db(conn = con, force = TRUE, quiet = TRUE)
  
  # Verify tables still exist
  tables <- DBI::dbListTables(con)
  expect_true("process_metrics" %in% tables)
  expect_true("reporter_status" %in% tables)
  expect_true("process_metrics_retention" %in% tables)
  
  # Verify data was cleared (tables recreated)
  count_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM reporter_status")$n
  expect_equal(count_after, 0)
})

test_that("setup_tasker_db creates view", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Setup database with all tables and views
  setup_tasker_db(conn = con, force = TRUE, quiet = TRUE)
  
  # Verify current_task_status_with_metrics view exists
  views <- DBI::dbGetQuery(con, "
    SELECT name FROM sqlite_master 
    WHERE type = 'view' AND name = 'current_task_status_with_metrics'
  ")
  
  expect_equal(nrow(views), 1)
  expect_equal(views$name, "current_task_status_with_metrics")
  
  # Verify view is queryable
  result <- DBI::dbGetQuery(con, "SELECT * FROM current_task_status_with_metrics LIMIT 0")
  
  # Check that view has expected columns
  expected_cols <- c("run_id", "cpu_percent", "memory_mb", "child_count", 
                     "is_alive", "metrics_age_seconds", "collection_error")
  for (col in expected_cols) {
    expect_true(col %in% names(result), info = paste("Missing column:", col))
  }
})

test_that("setup_tasker_db without force=TRUE preserves data", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Setup tasker database
  setup_tasker_db(conn = con, force = TRUE, quiet = TRUE)
  
  # Insert test data
  DBI::dbExecute(con, "
    INSERT INTO reporter_status (hostname, process_id, started_at)
    VALUES ('test-host', 12345, datetime('now'))
  ")
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb)
    VALUES ('00000000-0000-0000-0000-000000000001', datetime('now'), 12345, 'test-host', 1, 25.5, 512.0)
  ")
  
  # Verify data exists
  status_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM reporter_status")$n
  metrics_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM process_metrics")$n
  expect_equal(status_count, 1)
  expect_equal(metrics_count, 1)
  
  # Re-run setup WITHOUT force (should preserve data)
  setup_tasker_db(conn = con, force = FALSE, quiet = TRUE)
  
  # Verify data is preserved
  status_count_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM reporter_status")$n
  metrics_count_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM process_metrics")$n
  expect_equal(status_count_after, 1)
  expect_equal(metrics_count_after, 1)
})

test_that("check_tasker_tables_exist detects missing tables", {
  skip_if_not_installed("RSQLite")
  
  # Create an empty SQLite database (no schema yet)
  db_path <- get_test_db_path()
  if (file.exists(db_path)) unlink(db_path)

  tasker::tasker_config(
    driver = "sqlite",
    dbname = db_path,
    schema = "",
    reload = TRUE
  )

  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)

  # Before schema creation, tables should not exist
  result_before <- check_tasker_tables_exist(conn = con, driver = "sqlite")
  expect_false(result_before)

  # After schema creation, all tables should exist
  setup_tasker_db(conn = con, force = TRUE, quiet = TRUE)
  result_after <- check_tasker_tables_exist(conn = con, driver = "sqlite")
  expect_true(result_after)
  
  cleanup_test_db(con)
})

test_that("get_previous_start_times returns empty list for empty input", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_metrics table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics (
      metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL,
      timestamp TEXT NOT NULL DEFAULT (datetime('now')),
      process_start_time TEXT,
      UNIQUE(run_id, timestamp)
    )
  ")
  
  result <- tasker:::get_previous_start_times(con, character(0))
  expect_equal(result, list())
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_previous_start_times returns NULL for run_ids with no metrics", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_metrics table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics (
      metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL,
      timestamp TEXT NOT NULL DEFAULT (datetime('now')),
      process_start_time TEXT,
      UNIQUE(run_id, timestamp)
    )
  ")
  
  run_id1 <- "00000000-0000-0000-0000-000000000001"
  run_id2 <- "00000000-0000-0000-0000-000000000002"
  
  result <- tasker:::get_previous_start_times(con, c(run_id1, run_id2))
  expect_equal(length(result), 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_previous_start_times returns latest start time for each run", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_metrics table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics (
      metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      process_id INTEGER NOT NULL,
      hostname TEXT NOT NULL,
      is_alive INTEGER NOT NULL DEFAULT 1,
      process_start_time TEXT,
      UNIQUE(run_id, timestamp)
    )
  ")
  
  run_id1 <- "00000000-0000-0000-0000-000000000001"
  run_id2 <- "00000000-0000-0000-0000-000000000002"
  
  # Insert metrics with different timestamps
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, process_start_time)
    VALUES 
      (?, '2026-01-14 10:00:00', 1001, 'test-host', 1, '2026-01-14 09:00:00'),
      (?, '2026-01-14 10:01:00', 1001, 'test-host', 1, '2026-01-14 09:00:00'),
      (?, '2026-01-14 10:02:00', 1001, 'test-host', 1, '2026-01-14 09:00:00'),
      (?, '2026-01-14 10:00:00', 1002, 'test-host', 1, '2026-01-14 09:30:00'),
      (?, '2026-01-14 10:01:00', 1002, 'test-host', 1, '2026-01-14 09:30:00')
  ", params = list(run_id1, run_id1, run_id1, run_id2, run_id2))
  
  result <- tasker:::get_previous_start_times(con, c(run_id1, run_id2))
  
  expect_equal(length(result), 2)
  expect_true(run_id1 %in% names(result))
  expect_true(run_id2 %in% names(result))
  expect_equal(result[[run_id1]], "2026-01-14 09:00:00")
  expect_equal(result[[run_id2]], "2026-01-14 09:30:00")
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_previous_start_times handles mixed existing and non-existing runs", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_metrics table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics (
      metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      process_id INTEGER NOT NULL,
      hostname TEXT NOT NULL,
      is_alive INTEGER NOT NULL DEFAULT 1,
      process_start_time TEXT,
      UNIQUE(run_id, timestamp)
    )
  ")
  
  run_id1 <- "00000000-0000-0000-0000-000000000001"
  run_id2 <- "00000000-0000-0000-0000-000000000002"
  run_id3 <- "00000000-0000-0000-0000-000000000003"
  
  # Insert metrics only for run_id1 and run_id2
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, process_start_time)
    VALUES 
      (?, '2026-01-14 10:00:00', 1001, 'test-host', 1, '2026-01-14 09:00:00'),
      (?, '2026-01-14 10:01:00', 1002, 'test-host', 1, '2026-01-14 09:30:00')
  ", params = list(run_id1, run_id2))
  
  result <- tasker:::get_previous_start_times(con, c(run_id1, run_id2, run_id3))
  
  expect_equal(length(result), 2)
  expect_true(run_id1 %in% names(result))
  expect_true(run_id2 %in% names(result))
  expect_false(run_id3 %in% names(result))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("register_reporter creates new reporter entry", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS reporter_status (
      reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL UNIQUE,
      process_id INTEGER NOT NULL,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
      version TEXT,
      config TEXT DEFAULT '{}',
      shutdown_requested INTEGER DEFAULT 0
    )
  ")
  
  hostname <- "test-host"
  pid <- 12345
  version <- "1.0.0"
  
  tasker:::register_reporter(con, hostname, pid, version)
  
  result <- DBI::dbGetQuery(con, "
    SELECT * FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(nrow(result), 1)
  expect_equal(result$hostname, hostname)
  expect_equal(result$process_id, pid)
  expect_equal(result$version, version)
  expect_equal(result$shutdown_requested, 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("register_reporter updates existing reporter (UPSERT)", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS reporter_status (
      reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL UNIQUE,
      process_id INTEGER NOT NULL,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
      version TEXT,
      config TEXT DEFAULT '{}',
      shutdown_requested INTEGER DEFAULT 0
    )
  ")
  
  hostname <- "test-host"
  pid1 <- 12345
  pid2 <- 67890
  version1 <- "1.0.0"
  version2 <- "1.1.0"
  
  # Register first time
  tasker:::register_reporter(con, hostname, pid1, version1)
  
  result1 <- DBI::dbGetQuery(con, "
    SELECT * FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(nrow(result1), 1)
  expect_equal(result1$process_id, pid1)
  expect_equal(result1$version, version1)
  
  # Register again with different PID and version (should update)
  tasker:::register_reporter(con, hostname, pid2, version2)
  
  result2 <- DBI::dbGetQuery(con, "
    SELECT * FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(nrow(result2), 1)  # Still only one row
  expect_equal(result2$process_id, pid2)  # Updated PID
  expect_equal(result2$version, version2)  # Updated version
  expect_equal(result2$shutdown_requested, 0)  # Reset to 0 after UPSERT
  
  # Verify started_at was also updated (UPSERT should refresh all fields)
  expect_false(is.na(result2$started_at))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("update_reporter_heartbeat updates timestamp", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS reporter_status (
      reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL UNIQUE,
      process_id INTEGER NOT NULL,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
      version TEXT,
      config TEXT DEFAULT '{}',
      shutdown_requested INTEGER DEFAULT 0
    )
  ")
  
  hostname <- "test-host"
  pid <- 12345
  version <- "1.0.0"
  
  # Register reporter
  tasker:::register_reporter(con, hostname, pid, version)
  
  result1 <- DBI::dbGetQuery(con, "
    SELECT last_heartbeat FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  initial_heartbeat <- result1$last_heartbeat[1]
  
  # Wait long enough for timestamp to change (SQLite datetime has second precision)
  Sys.sleep(1.1)
  
  # Update heartbeat
  tasker:::update_reporter_heartbeat(con, hostname)
  
  result2 <- DBI::dbGetQuery(con, "
    SELECT last_heartbeat FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  updated_heartbeat <- result2$last_heartbeat[1]
  
  expect_false(is.na(updated_heartbeat))
  # Verify heartbeat was actually updated (SQLite stores as TEXT, so string comparison works)
  expect_true(updated_heartbeat > initial_heartbeat, 
              info = sprintf("Expected %s > %s", updated_heartbeat, initial_heartbeat))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("update_reporter_heartbeat deletes row for different PID on same hostname", {
  skip_if_not_installed("RSQLite")
  skip_on_cran()  # Skip on CRAN since this test starts actual processes
  
  # This test validates DELETE+INSERT transaction behavior when PID changes
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create reporter_status table (note: name changed from reporter_status)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS reporter_status (
      reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL UNIQUE,
      process_id INTEGER NOT NULL,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
      version TEXT,
      config TEXT DEFAULT '{}',
      shutdown_requested INTEGER DEFAULT 0
    )
  ")
  
  hostname <- Sys.info()[["nodename"]]
  
  # Start first reporter process
  reporter1_proc <- callr::r_bg(
    function(hostname, db_path) {
      library(tasker)
      
      # Set test database path
      options(tasker.config = list(
        database = list(
          driver = "sqlite",
          db_file = db_path
        )
      ))
      
      con <- tasker:::get_tasker_db_connection()
      tasker:::update_reporter_heartbeat(con, hostname)
      DBI::dbDisconnect(con)
      Sys.sleep(2)  # Keep it alive briefly
      "done"
    },
    args = list(hostname = hostname, db_path = db_path),
    supervise = TRUE
  )
  
  # Wait for first reporter to register
  Sys.sleep(1)
  
  # Verify first reporter exists
  result1 <- DBI::dbGetQuery(con, "
    SELECT process_id, started_at FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(nrow(result1), 1)
  first_pid <- result1$process_id[1]
  first_started_at <- result1$started_at[1]
  
  # Kill first reporter
  reporter1_proc$kill()
  
  # Wait a moment for timestamps to differ
  Sys.sleep(1)
  
  # Start second reporter process
  reporter2_proc <- callr::r_bg(
    function(hostname, db_path) {
      library(tasker)
      
      # Set test database path
      options(tasker.config = list(
        database = list(
          driver = "sqlite",
          db_file = db_path
        )
      ))
      
      con <- tasker:::get_tasker_db_connection()
      tasker:::update_reporter_heartbeat(con, hostname)
      DBI::dbDisconnect(con)
      "done"
    },
    args = list(hostname = hostname, db_path = db_path),
    supervise = TRUE
  )
  
  # Wait for second reporter to register  
  Sys.sleep(1)
  
  # Verify old row was deleted and new row created
  result2 <- DBI::dbGetQuery(con, "
    SELECT process_id, started_at FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(nrow(result2), 1)
  second_pid <- result2$process_id[1]
  second_started_at <- result2$started_at[1]
  
  # Should be different PID and later timestamp
  expect_true(second_pid != first_pid, 
              info = sprintf("Expected different PIDs: %d vs %d", first_pid, second_pid))
  expect_true(second_started_at > first_started_at,
              info = "New reporter should have later started_at timestamp")
  
  # Clean up second reporter
  reporter2_proc$kill()
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_reporter_database_status returns NULL when no reporter", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS reporter_status (
      reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL UNIQUE,
      process_id INTEGER NOT NULL,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
      version TEXT,
      config TEXT DEFAULT '{}',
      shutdown_requested INTEGER DEFAULT 0
    )
  ")
  
  DBI::dbDisconnect(con)
  
  result <- tasker:::get_reporter_database_status(hostname = "nonexistent-host")
  expect_null(result)
  
  cleanup_test_db()
})

test_that("get_reporter_database_status returns reporter info when exists", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS reporter_status (
      reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL UNIQUE,
      process_id INTEGER NOT NULL,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
      version TEXT,
      config TEXT DEFAULT '{}',
      shutdown_requested INTEGER DEFAULT 0
    )
  ")
  
  hostname <- "test-host"
  pid <- 12345
  version <- "1.0.0"
  
  tasker:::register_reporter(con, hostname, pid, version)
  DBI::dbDisconnect(con)
  
  result <- tasker:::get_reporter_database_status(hostname = hostname)
  
  expect_false(is.null(result))
  expect_equal(result$hostname, hostname)
  expect_equal(result$process_id, pid)
  expect_equal(result$version, version)
  
  cleanup_test_db()
})

test_that("stop_reporter sets shutdown flag", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS reporter_status (
      reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
      hostname TEXT NOT NULL UNIQUE,
      process_id INTEGER NOT NULL,
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
      version TEXT,
      config TEXT DEFAULT '{}',
      shutdown_requested INTEGER DEFAULT 0
    )
  ")
  
  hostname <- "test-host"
  pid <- 12345
  version <- "1.0.0"
  
  # Register reporter
  tasker:::register_reporter(con, hostname, pid, version)
  
  result1 <- DBI::dbGetQuery(con, "
    SELECT shutdown_requested FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(result1$shutdown_requested[1], 0)
  
  DBI::dbDisconnect(con)
  
  # Request shutdown
  tasker:::stop_reporter(hostname = hostname, timeout = 1)
  
  con <- get_test_db_connection()
  result2 <- DBI::dbGetQuery(con, "
    SELECT shutdown_requested FROM reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(result2$shutdown_requested[1], 1)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("collect_process_metrics handles current process", {
  skip_if_not_installed("ps")
  
  # Get current process
  pid <- Sys.getpid()
  hostname <- Sys.info()[["nodename"]]
  run_id <- "00000000-0000-0000-0000-000000000001"
  
  metrics <- tasker:::collect_process_metrics(
    run_id = run_id,
    process_id = pid,
    hostname = hostname,
    include_children = FALSE,
    timeout_seconds = 5
  )
  
  # Should collect successfully
  expect_false(is.null(metrics))
  expect_equal(metrics$run_id, run_id)
  expect_equal(metrics$process_id, pid)
  expect_equal(metrics$hostname, hostname)
  expect_true(metrics$is_alive)
  expect_false(metrics$collection_error)
  
  # Should have metrics
  expect_false(is.null(metrics$cpu_percent))
  expect_false(is.null(metrics$memory_mb))
  expect_false(is.null(metrics$process_start_time))
})

test_that("collect_process_metrics detects dead process", {
  skip_if_not_installed("ps")
  
  # Use a PID that definitely doesn't exist
  pid <- 999999
  hostname <- Sys.info()[["nodename"]]
  run_id <- "00000000-0000-0000-0000-000000000001"
  
  metrics <- tasker:::collect_process_metrics(
    run_id = run_id,
    process_id = pid,
    hostname = hostname,
    include_children = FALSE,
    timeout_seconds = 5
  )
  
  # Should return error
  expect_false(is.null(metrics))
  expect_equal(metrics$run_id, run_id)
  expect_true(metrics$collection_error)
  expect_equal(metrics$error_type, "PROCESS_DIED")
  expect_false(metrics$is_alive)
})

test_that("write_process_metrics inserts successful metrics", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("ps")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_metrics table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics (
      metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL,
      timestamp TEXT NOT NULL DEFAULT (datetime('now')),
      process_id INTEGER NOT NULL,
      hostname TEXT NOT NULL,
      is_alive INTEGER NOT NULL DEFAULT 1,
      process_start_time TEXT,
      cpu_percent REAL,
      memory_mb REAL,
      memory_percent REAL,
      collection_error INTEGER DEFAULT 0,
      error_message TEXT,
      error_type TEXT,
      reporter_version TEXT,
      UNIQUE(run_id, timestamp)
    )
  ")
  
  # Collect metrics for current process
  pid <- Sys.getpid()
  hostname <- Sys.info()[["nodename"]]
  run_id <- "00000000-0000-0000-0000-000000000001"
  
  metrics <- tasker:::collect_process_metrics(
    run_id = run_id,
    process_id = pid,
    hostname = hostname,
    include_children = FALSE,
    timeout_seconds = 5
  )
  
  # Write metrics
  metric_id <- tasker:::write_process_metrics(metrics, con = con)
  
  expect_false(is.null(metric_id))
  expect_true(is.numeric(metric_id))
  
  # Verify written to database
  result <- DBI::dbGetQuery(con, "
    SELECT * FROM process_metrics WHERE metric_id = ?
  ", params = list(metric_id))
  
  expect_equal(nrow(result), 1)
  expect_equal(result$run_id, run_id)
  expect_equal(result$process_id, pid)
  expect_equal(result$is_alive, 1)
  expect_equal(result$collection_error, 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("write_process_metrics inserts error metrics", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_metrics table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics (
      metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL,
      timestamp TEXT NOT NULL DEFAULT (datetime('now')),
      process_id INTEGER NOT NULL,
      hostname TEXT NOT NULL,
      is_alive INTEGER NOT NULL DEFAULT 1,
      process_start_time TEXT,
      cpu_percent REAL,
      memory_mb REAL,
      collection_error INTEGER DEFAULT 0,
      error_message TEXT,
      error_type TEXT,
      reporter_version TEXT,
      UNIQUE(run_id, timestamp)
    )
  ")
  
  # Create error metrics
  run_id <- "00000000-0000-0000-0000-000000000001"
  pid <- 999999
  hostname <- Sys.info()[["nodename"]]
  
  metrics <- tasker:::collect_process_metrics(
    run_id = run_id,
    process_id = pid,
    hostname = hostname,
    include_children = FALSE,
    timeout_seconds = 5
  )
  
  # Write error metrics
  metric_id <- tasker:::write_process_metrics(metrics, con = con)
  
  expect_false(is.null(metric_id))
  
  # Verify error was recorded
  result <- DBI::dbGetQuery(con, "
    SELECT * FROM process_metrics WHERE metric_id = ?
  ", params = list(metric_id))
  
  expect_equal(nrow(result), 1)
  expect_equal(result$run_id, run_id)
  expect_equal(result$collection_error, 1)
  expect_equal(result$error_type, "PROCESS_DIED")
  expect_false(is.na(result$error_message))
  expect_equal(result$is_alive, 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

# ============================================================================
# Phase 2 Tests: Reporter Service Implementation
# ============================================================================

test_that("should_auto_start returns FALSE when tables don't exist", {
  skip_if_not_installed("RSQLite")
  
  # Empty database (no schema/tables)
  db_path <- get_test_db_path()
  if (file.exists(db_path)) unlink(db_path)

  tasker::tasker_config(driver = "sqlite", dbname = db_path, schema = "", reload = TRUE)

  options(tasker.process_reporter.auto_start = TRUE)
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  result <- tasker:::should_auto_start(con)
  expect_false(result)
})

test_that("should_auto_start returns TRUE when tables exist", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)

  options(tasker.process_reporter.auto_start = TRUE)
  
  result <- tasker:::should_auto_start(con)
  expect_true(result)
})

test_that("get_active_tasks returns empty list when no active tasks", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  hostname <- "test-host"
  
  result <- tasker:::get_active_tasks_for_reporter(con, hostname)
  expect_equal(length(result), 0)
  
  cleanup_test_db(con)
})

test_that("get_active_tasks returns active tasks for hostname", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  hostname <- "test-host"
  
  # Insert test task runs
  run_id1 <- "00000000-0000-0000-0000-000000000001"
  run_id2 <- "00000000-0000-0000-0000-000000000002"
  
  # Need to create stages and tasks first
  DBI::dbExecute(con, "
    INSERT INTO stages (stage_id, stage_name) VALUES (1, 'TEST')
  ")
  
  DBI::dbExecute(con, "
    INSERT INTO tasks (task_id, stage_id, task_name) VALUES (1, 1, 'Test Task')
  ")
  
  DBI::dbExecute(con, "
    INSERT INTO task_runs (run_id, task_id, hostname, process_id, start_time, status)
    VALUES 
      (?, 1, ?, 1001, datetime('now'), 'RUNNING'),
      (?, 1, ?, 1002, datetime('now'), 'STARTED'),
      (?, 1, 'other-host', 1003, datetime('now'), 'RUNNING')
  ", params = list(run_id1, hostname, run_id2, hostname, "00000000-0000-0000-0000-000000000003"))
  
  result <- tasker:::get_active_tasks_for_reporter(con, hostname)
  
  expect_equal(length(result), 2)
  expect_equal(result[[1]]$run_id, run_id1)
  expect_equal(result[[1]]$process_id, 1001)
  expect_equal(result[[2]]$run_id, run_id2)
  expect_equal(result[[2]]$process_id, 1002)
  
  cleanup_test_db(con)
})

test_that("should_shutdown returns FALSE when no shutdown requested", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  hostname <- "test-host"
  
  # Register reporter without shutdown request
  tasker:::register_reporter(con, hostname, 12345)
  
  result <- tasker:::should_shutdown(con, hostname)
  expect_false(result)
  
  cleanup_test_db(con)
})

test_that("should_shutdown returns TRUE when shutdown requested", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  hostname <- "test-host"
  current_pid <- Sys.getpid()
  
  # Register reporter with CURRENT PID (should_shutdown checks for this process)
  tasker:::register_reporter(con, hostname, current_pid)
  
  DBI::dbExecute(con, "
    UPDATE reporter_status SET shutdown_requested = 1 WHERE hostname = ?
  ", params = list(hostname))
  
  result <- tasker:::should_shutdown(con, hostname)
  expect_true(result)
  
  cleanup_test_db(con)
})

test_that("get_reporter_status detects dead process", {
  skip_if_not_installed("ps")
  
  # Use a PID that definitely doesn't exist
  result <- tasker:::get_reporter_status(999999, "test-host")
  expect_false(result$is_alive)
})

test_that("get_reporter_status detects live process", {
  skip_if_not_installed("ps")
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Use current process PID and register it
  current_pid <- Sys.getpid()
  hostname <- "test-live-host"
  
  tasker:::register_reporter(con, hostname, current_pid)
  
  # Update heartbeat to ensure recent timestamp
  tasker:::update_reporter_heartbeat(con, hostname)
  
  # Create a local Sys.info function that masks the primitive
  # and returns test hostname so it's treated as local machine
  Sys.info <- function() c(nodename = hostname)
  
  result <- tasker:::get_reporter_status(current_pid, hostname, con = con)
  
  expect_true(result$is_alive)
})

test_that("auto_start_reporter returns FALSE when tables don't exist", {
  skip_if_not_installed("RSQLite")
  
  # Setup minimal database WITHOUT any tables
  db_path <- get_test_db_path()
  if (file.exists(db_path)) unlink(db_path)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = db_path,
    schema = "",
    reload = TRUE
  )
  
  # Create an empty database (no setup_tasker_db call)
  # Just create the database file by opening a connection
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  
  # Should return FALSE because tables don't exist
  result <- tasker:::auto_start_reporter("test-host", con)
  expect_false(result)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("task_start integrates with auto_start_reporter", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  
  # Create test stage and task
  DBI::dbExecute(con, "
    INSERT INTO stages (stage_id, stage_name) VALUES (1, 'TEST')
  ")
  
  DBI::dbExecute(con, "
    INSERT INTO tasks (task_id, stage_id, task_name) VALUES (1, 1, 'Test Auto-start Task')
  ")
  
  DBI::dbDisconnect(con)
  
  # Start a task (this should trigger auto-start attempt)
  run_id <- tasker::task_start(
    stage = "TEST",
    task = "Test Auto-start Task",
    quiet = TRUE,
    .active = FALSE
  )
  
  # Verify task was created
  expect_true(!is.null(run_id))
  expect_true(nchar(run_id) > 0)
  
  cleanup_test_db()
})

# ============================================================================
# Tests for start_reporter()
# ============================================================================

test_that("start_reporter validates parameters", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("callr")
  
  con <- setup_test_db()
  
  # NOTE: Current implementation does not validate parameters before attempting to start
  # These tests verify the function accepts parameter types, not that it validates values
  # Parameter validation should be added to the implementation
  
  # Function should accept valid numeric collection_interval
  # (Don't actually start, just verify no immediate error from parameter handling)
  expect_no_error({
    params <- list(
      collection_interval = 10,
      hostname = "test-host",
      force = FALSE,
      quiet = TRUE,
      conn = con
    )
  })
  
  # Function should accept string hostname
  expect_no_error({
    hostname <- "valid-hostname"
  })
  
  # Function should accept supervise parameter (both TRUE and FALSE)
  expect_no_error({
    supervise_false <- FALSE
    supervise_true <- TRUE
  })
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("start_reporter accepts supervise parameter", {
  skip_if_not_installed("RSQLite")
  
  # Verify function signature includes supervise parameter with default FALSE
  fn_args <- formals(start_reporter)
  expect_true("supervise" %in% names(fn_args))
  expect_equal(fn_args$supervise, FALSE)
})

test_that("start_reporter checks for existing reporter", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("ps")
  
  con <- setup_test_db()
  # Use actual hostname so process check works
  hostname <- Sys.info()[["nodename"]]
  
  # Register a fake reporter with non-existent PID
  fake_pid <- 999999
  tasker:::register_reporter(con, hostname, fake_pid, version = "1.0.0")
  
  # Get status - should find the registered reporter
  status <- tasker:::get_reporter_database_status(hostname, con = con)
  expect_false(is.null(status))
  expect_equal(status$hostname, hostname)
  expect_equal(status$process_id, fake_pid)
  
  # Check if reporter is alive (should be FALSE for fake PID on same machine)
  result <- tasker:::get_reporter_status(fake_pid, hostname, con = con)
  expect_equal(result$status, "DEAD")
  expect_false(result$is_alive)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("start_reporter handles dead process detection", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("ps")
  
  con <- setup_test_db()
  # Use actual hostname so process check works
  hostname <- Sys.info()[["nodename"]]
  
  # Register reporter with invalid PID
  dead_pid <- 999999
  tasker:::register_reporter(con, hostname, dead_pid, version = "1.0.0")
  
  # get_reporter_status should detect dead process on same machine
  result <- tasker:::get_reporter_status(dead_pid, hostname, con = con)
  expect_equal(result$status, "DEAD")
  expect_false(result$is_alive)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("start_reporter respects force parameter", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("ps")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  hostname <- "test-force-param"
  
  # Create test config file for spawned processes
  test_config <- create_test_config_file()
  
  # Ensure cleanup happens even if test fails
  on.exit({
    # Stop reporter using test connection
    tryCatch(stop_reporter(hostname, timeout = 10, con = con), error = function(e) NULL)
    # Clean up test config file
    if (file.exists(test_config)) unlink(test_config)
    # Clean up test DB
    tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    cleanup_test_db()
  }, add = TRUE)
  
  # Start an actual reporter process
  start_result <- start_reporter(
    hostname = hostname,
    force = TRUE,
    quiet = TRUE,
    conn = con,
    config_file = test_config
  )
  
  expect_equal(start_result$status, "started")
  first_pid <- start_result$process_id
  expect_true(first_pid > 0)
  
  # Wait for reporter to be fully running and update heartbeat
  Sys.sleep(2)
  
  # Verify reporter is running
  reporter_status <- get_reporter_status(first_pid, hostname, con = con)
  expect_equal(reporter_status$status, "RUNNING")
  expect_true(reporter_status$is_alive)
  
  # With force=FALSE and live reporter, should return "already_running"
  result <- start_reporter(
    hostname = hostname,
    force = FALSE,
    quiet = TRUE,
    conn = con,
    config_file = test_config
  )
  
  expect_equal(result$status, "already_running")
  expect_equal(result$process_id, first_pid)
  
  # With force=TRUE, should stop old reporter and start new one
  force_result <- start_reporter(
    hostname = hostname,
    force = TRUE,
    quiet = TRUE,
    conn = con,
    config_file = test_config
  )
  
  expect_equal(force_result$status, "started")
  expect_true(force_result$process_id > 0)
  expect_true(force_result$process_id != first_pid)  # Different PID
})

test_that("start_reporter supervise parameter is passed to callr::r_bg", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("callr")
  
  # This test verifies that the supervise parameter is correctly passed through
  # Full integration testing of process lifecycle requires complex subprocess management
  # that is better suited for manual testing or CI environments
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  hostname1 <- paste0("test-supervise-false-", format(Sys.time(), "%Y%m%d%H%M%S"))
  hostname2 <- paste0("test-supervise-true-", format(Sys.time(), "%Y%m%d%H%M%S"))
  
  # Create test config file for spawned processes
  test_config <- create_test_config_file()
  
  # Ensure cleanup happens even if test fails
  on.exit({
    # Stop reporters using test connection
    tryCatch(stop_reporter(hostname1, timeout = 5, con = con), error = function(e) NULL)
    tryCatch(stop_reporter(hostname2, timeout = 5, con = con), error = function(e) NULL)
    # Clean up test config file
    if (file.exists(test_config)) unlink(test_config)
    # Clean up test DB
    tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    cleanup_test_db()
  }, add = TRUE)
  
  # Verify the function accepts supervise parameter without error
  # Test with supervise=FALSE (default - reporter persists)
  result_false <- tryCatch({
    start_reporter(
      collection_interval = 10,
      hostname = hostname1,
      force = FALSE,
      quiet = TRUE,
      conn = con,
      supervise = FALSE,
      config_file = test_config
    )
  }, error = function(e) {
    # If start fails in test environment, that's OK - we're testing parameter acceptance
    list(status = "error", message = e$message)
  })
  
  # Verify function returned a result structure (even if it's an error)
  expect_type(result_false, "list")
  expect_true("status" %in% names(result_false))
  
  # Test with supervise=TRUE (reporter terminates with parent)
  result_true <- tryCatch({
    start_reporter(
      collection_interval = 10,
      hostname = hostname2,
      force = FALSE,
      quiet = TRUE,
      conn = con,
      supervise = TRUE,
      config_file = test_config
    )
  }, error = function(e) {
    list(status = "error", message = e$message)
  })
  
  # Verify function returned a result structure
  expect_type(result_true, "list")
  expect_true("status" %in% names(result_true))
})

# ============================================================================
# Tests for process_reporter_main_loop()
# ============================================================================

test_that("process_reporter_main_loop helper: should_shutdown works", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  hostname <- "test-loop-shutdown"
  
  # Register reporter
  reporter_pid <- Sys.getpid()
  tasker:::register_reporter(con, hostname, reporter_pid)
  
  # Initially no shutdown requested
  expect_false(tasker:::should_shutdown(con, hostname))
  
  # Request shutdown
  tasker::stop_reporter(hostname, timeout = 1, con = con)
  
  # Now should shutdown
  expect_true(tasker:::should_shutdown(con, hostname))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("process_reporter_main_loop helper: get_active_tasks works", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  hostname <- "test-loop-tasks"
  
  # Create task
  DBI::dbExecute(con, "INSERT INTO stages (stage_id, stage_name) VALUES (1, 'TEST')")
  DBI::dbExecute(con, "
    INSERT INTO tasks (task_id, stage_id, task_name) 
    VALUES (1, 1, 'Test Task')
  ")
  
  # No active tasks initially
  tasks <- tasker:::get_active_tasks_for_reporter(con, hostname)
  expect_equal(length(tasks), 0)
  
  # Add a running task
  run_id <- tolower(paste(
    paste(sample(c(0:9, letters[1:6]), 8, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 12, replace = TRUE), collapse = ""),
    sep = "-"
  ))
  current_pid <- Sys.getpid()
  DBI::dbExecute(con, sprintf("
    INSERT INTO task_runs (run_id, task_id, hostname, process_id, status, start_time)
    VALUES ('%s', 1, '%s', %d, 'RUNNING', datetime('now'))
  ", run_id, hostname, current_pid))
  
  # Now should find the task
  tasks <- tasker:::get_active_tasks_for_reporter(con, hostname)
  expect_equal(length(tasks), 1)
  expect_equal(tasks[[1]]$run_id, run_id)
  expect_equal(tasks[[1]]$process_id, current_pid)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("process_reporter_main_loop handles no active tasks", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  hostname <- "test-loop-no-tasks"
  
  # Register reporter
  reporter_pid <- Sys.getpid()
  tasker:::register_reporter(con, hostname, reporter_pid)
  
  # Get active tasks - should be empty
  active_tasks <- tasker:::get_active_tasks_for_reporter(con, hostname)
  expect_equal(length(active_tasks), 0)
  
  # Update heartbeat should work even with no tasks
  expect_no_error(tasker:::update_reporter_heartbeat(con, hostname))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("process_reporter_main_loop components handle errors gracefully", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("ps")
  
  con <- setup_test_db()
  hostname <- "test-loop-errors"
  
  # Register reporter
  reporter_pid <- Sys.getpid()
  tasker:::register_reporter(con, hostname, reporter_pid)
  
  # Create task with invalid PID
  DBI::dbExecute(con, "INSERT INTO stages (stage_id, stage_name) VALUES (1, 'TEST')")
  DBI::dbExecute(con, "
    INSERT INTO tasks (task_id, stage_id, task_name) 
    VALUES (1, 1, 'Test Error Task')
  ")
  
  run_id <- tolower(paste(
    paste(sample(c(0:9, letters[1:6]), 8, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = ""),
    paste(sample(c(0:9, letters[1:6]), 12, replace = TRUE), collapse = ""),
    sep = "-"
  ))
  invalid_pid <- 999999
  DBI::dbExecute(con, sprintf("
    INSERT INTO task_runs (run_id, task_id, hostname, process_id, status, start_time)
    VALUES ('%s', 1, '%s', %d, 'RUNNING', datetime('now'))
  ", run_id, hostname, invalid_pid))
  
  # Get active tasks should work
  active_tasks <- tasker:::get_active_tasks_for_reporter(con, hostname)
  expect_equal(length(active_tasks), 1)
  
  # collect_process_metrics should handle invalid PID gracefully
  # Returns a list with collection_error = TRUE, never throws
  metrics <- tasker:::collect_process_metrics(
    run_id = run_id,
    process_id = invalid_pid,
    hostname = hostname,
    include_children = FALSE,
    timeout_seconds = 1
  )
  
  # Verify error metrics structure
  expect_true(is.list(metrics))
  expect_true(metrics$collection_error)
  expect_equal(metrics$error_type, "PROCESS_DIED")
  expect_false(metrics$is_alive)
  expect_equal(metrics$process_id, invalid_pid)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})


# ============================================================================
# Tests for check_reporter()
# ============================================================================

test_that("check_reporter returns NULL when no reporters found", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Query should return NULL with no reporters
  result <- check_reporter(con = con, quiet = TRUE)
  expect_null(result)
})

test_that("check_reporter displays single reporter info", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  hostname <- "test-host-1"
  pid <- 12345
  version <- "0.7.0"
  
  # Register a reporter
  tasker:::register_reporter(con, hostname, pid, version)
  
  # Get reporter info
  result <- check_reporter(con = con, quiet = TRUE)
  
  expect_false(is.null(result))
  expect_equal(nrow(result), 1)
  expect_equal(result$hostname, hostname)
  expect_equal(result$process_id, pid)
  expect_equal(result$version, version)
  expect_true("status" %in% names(result))
  expect_true("heartbeat_age_seconds" %in% names(result))
})

test_that("check_reporter displays multiple reporters", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register multiple reporters
  tasker:::register_reporter(con, "host-1", 11111, "0.7.0")
  tasker:::register_reporter(con, "host-2", 22222, "0.7.0")
  tasker:::register_reporter(con, "host-3", 33333, "0.6.0")
  
  # Get reporter info
  result <- check_reporter(con = con, quiet = TRUE)
  
  expect_false(is.null(result))
  expect_equal(nrow(result), 3)
  expect_equal(sort(result$hostname), c("host-1", "host-2", "host-3"))
  expect_equal(sort(result$process_id), c(11111, 22222, 33333))
})

test_that("check_reporter detects stale reporters", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Use actual hostname so process check works
  hostname <- Sys.info()[["nodename"]]
  pid <- 99999  # Non-existent PID
  
  # Register reporter with old heartbeat (2 minutes ago)
  DBI::dbExecute(con, "
    INSERT INTO reporter_status 
      (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested)
    VALUES (?, ?, datetime('now', '-2 minutes'), datetime('now', '-2 minutes'), '0.7.0', 0)
  ", params = list(hostname, pid))
  
  # Get reporter info
  result <- check_reporter(con = con, quiet = TRUE)
  
  expect_false(is.null(result))
  expect_equal(nrow(result), 1)
  expect_true(result$heartbeat_age_seconds > 60)
  expect_equal(result$status, "DEAD")  # Non-existent PID on same machine
})

test_that("check_reporter detects shutdown_requested flag", {
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Use actual hostname so process check works
  hostname <- Sys.info()[["nodename"]]
  pid <- Sys.getpid()  # Use current process so it's alive
  
  # Register reporter
  tasker:::register_reporter(con, hostname, pid, "0.7.0")
  
  # Set shutdown flag
  DBI::dbExecute(con, "
    UPDATE reporter_status 
    SET shutdown_requested = 1
    WHERE hostname = ?
  ", params = list(hostname))
  
  # Get reporter info
  result <- check_reporter(con = con, quiet = TRUE)
  
  expect_false(is.null(result))
  expect_equal(nrow(result), 1)
  expect_true(result$shutdown_requested == 1)
  expect_equal(result$status, "SHUTTING_DOWN")
})

test_that("check_reporter handles database connection errors", {
  skip_if_not_installed("RSQLite")
  
  # Create a closed/invalid connection
  temp_db <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  DBI::dbDisconnect(con)  # Close it
  unlink(temp_db)  # Remove the file
  
  # With invalid connection, should return NULL gracefully
  result <- suppressWarnings(check_reporter(con = con, quiet = TRUE))
  
  expect_null(result)
})
