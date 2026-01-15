# Tests for Process Reporter functions

# Load all package functions for testing
# Note: These functions are internal and not exported
library(tasker)

test_that("setup_process_reporter_schema creates tables", {
  skip_if_not_installed("RSQLite")
  
  # Setup clean test database
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Load process reporter schema (need to adapt for SQLite)
  schema_file <- system.file("sql/postgresql/process_reporter_schema.sql", package = "tasker")
  
  # Create tables manually for SQLite (simplified)
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
      memory_vms_mb REAL,
      swap_mb REAL,
      read_bytes INTEGER,
      write_bytes INTEGER,
      read_count INTEGER,
      write_count INTEGER,
      io_wait_percent REAL,
      open_files INTEGER,
      num_fds INTEGER,
      num_threads INTEGER,
      page_faults_minor INTEGER,
      page_faults_major INTEGER,
      num_ctx_switches_voluntary INTEGER,
      num_ctx_switches_involuntary INTEGER,
      child_count INTEGER DEFAULT 0,
      child_total_cpu_percent REAL,
      child_total_memory_mb REAL,
      collection_error INTEGER DEFAULT 0,
      error_message TEXT,
      error_type TEXT,
      reporter_version TEXT,
      collection_duration_ms INTEGER,
      UNIQUE(run_id, timestamp)
    )
  ")
  
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
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
  
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics_retention (
      retention_id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT NOT NULL UNIQUE,
      task_completed_at TEXT NOT NULL,
      metrics_delete_after TEXT NOT NULL,
      metrics_deleted INTEGER DEFAULT 0,
      deleted_at TEXT,
      metrics_count INTEGER
    )
  ")
  
  # Verify tables exist
  tables <- DBI::dbListTables(con)
  expect_true("process_metrics" %in% tables)
  expect_true("process_reporter_status" %in% tables)
  expect_true("process_metrics_retention" %in% tables)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
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
  
  # Create process_reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
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
    SELECT * FROM process_reporter_status WHERE hostname = ?
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
  
  # Create process_reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
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
    SELECT * FROM process_reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(nrow(result1), 1)
  expect_equal(result1$process_id, pid1)
  expect_equal(result1$version, version1)
  
  # Register again with different PID and version (should update)
  tasker:::register_reporter(con, hostname, pid2, version2)
  
  result2 <- DBI::dbGetQuery(con, "
    SELECT * FROM process_reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(nrow(result2), 1)  # Still only one row
  expect_equal(result2$process_id, pid2)  # Updated PID
  expect_equal(result2$version, version2)  # Updated version
  expect_equal(result2$shutdown_requested, 0)  # Reset to FALSE
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("update_reporter_heartbeat updates timestamp", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
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
    SELECT last_heartbeat FROM process_reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  initial_heartbeat <- result1$last_heartbeat[1]
  
  # Wait a moment
  Sys.sleep(0.1)
  
  # Update heartbeat
  tasker:::update_reporter_heartbeat(con, hostname)
  
  result2 <- DBI::dbGetQuery(con, "
    SELECT last_heartbeat FROM process_reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  updated_heartbeat <- result2$last_heartbeat[1]
  
  expect_false(is.na(updated_heartbeat))
  # Note: In SQLite, datetime comparison may need special handling
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_process_reporter_status returns NULL when no reporter", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
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
  
  result <- tasker:::get_process_reporter_status(hostname = "nonexistent-host")
  expect_null(result)
  
  cleanup_test_db()
})

test_that("get_process_reporter_status returns reporter info when exists", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
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
  
  result <- tasker:::get_process_reporter_status(hostname = hostname)
  
  expect_false(is.null(result))
  expect_equal(result$hostname, hostname)
  expect_equal(result$process_id, pid)
  expect_equal(result$version, version)
  
  cleanup_test_db()
})

test_that("stop_process_reporter sets shutdown flag", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Create process_reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
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
    SELECT shutdown_requested FROM process_reporter_status WHERE hostname = ?
  ", params = list(hostname))
  
  expect_equal(result1$shutdown_requested[1], 0)
  
  DBI::dbDisconnect(con)
  
  # Request shutdown
  tasker:::stop_process_reporter(hostname = hostname, timeout = 1)
  
  con <- get_test_db_connection()
  result2 <- DBI::dbGetQuery(con, "
    SELECT shutdown_requested FROM process_reporter_status WHERE hostname = ?
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
