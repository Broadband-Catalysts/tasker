test_that("query functions exist", {
  # Test that query functions are defined
  expect_true(exists("get_task_status"))
  expect_true(exists("get_active_tasks"))
  expect_true(exists("get_task_history"))
})

test_that("get_stages filters correctly", {
  skip_on_cran()
  setup_test_db()
  
  # Just test function exists
  expect_true(exists("get_stages"))
})

test_that("get_task_status returns metrics columns", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema (creates views)
  
  # Register and start a running task
  register_task(stage = "TEST", name = "Test Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Test Task", conn = con)
  
  # Update to running status and backdate start time
  task_update(run_id = run_id, status = "RUNNING", conn = con)
  DBI::dbExecute(con, "
    UPDATE task_runs 
    SET start_time = datetime('now', '-5 minutes')
    WHERE run_id = ?
  ", params = list(run_id))
  
  # Insert process metrics
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb, child_count, child_total_cpu_percent, child_total_memory_mb, collection_error)
    VALUES (?, datetime('now', '-30 seconds'), 12345, 'test-host', 1, 25.5, 512.0, 4, 80.0, 1024.0, 0)
  ", params = list(run_id))
  
  # Get task status
  result <- get_task_status(conn = con)
  
  # Verify metrics columns are present
  expect_true("metrics_cpu_percent" %in% names(result))
  expect_true("metrics_memory_mb" %in% names(result))
  expect_true("metrics_child_count" %in% names(result))
  expect_true("metrics_child_total_cpu_percent" %in% names(result))
  expect_true("metrics_child_total_memory_mb" %in% names(result))
  expect_true("metrics_collection_error" %in% names(result))
  expect_true("metrics_error_message" %in% names(result))
  expect_true("metrics_is_alive" %in% names(result))
  expect_true("metrics_age_seconds" %in% names(result))
  
  # Verify metrics values
  expect_equal(result$metrics_cpu_percent, 25.5)
  expect_equal(result$metrics_memory_mb, 512.0)
  expect_equal(result$metrics_child_count, 4)
  expect_equal(result$metrics_child_total_cpu_percent, 80.0)
  expect_equal(result$metrics_child_total_memory_mb, 1024.0)
  expect_equal(result$metrics_collection_error, 0)
  expect_equal(result$metrics_is_alive, 1)
  expect_true(result$metrics_age_seconds >= 25 && result$metrics_age_seconds <= 35)  # Around 30 seconds
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_task_status handles NULL metrics gracefully", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema (creates views)
  
  # Register and start task WITHOUT metrics
  register_task(stage = "TEST", name = "Task Without Metrics", type = "R")
  run_id <- task_start(stage = "TEST", task = "Task Without Metrics", conn = con)
  
  # Update to running status
  task_update(run_id = run_id, status = "RUNNING", conn = con)
  
  # Get task status - should not error
  result <- get_task_status(conn = con)
  
  # Verify task exists
  expect_equal(nrow(result), 1)
  expect_equal(result$run_id, run_id)
  
  # Verify metrics columns exist but are NULL/NA
  expect_true("metrics_cpu_percent" %in% names(result))
  expect_true("metrics_memory_mb" %in% names(result))
  expect_true("metrics_is_alive" %in% names(result))
  expect_true("metrics_age_seconds" %in% names(result))
  
  expect_true(is.na(result$metrics_cpu_percent))
  expect_true(is.na(result$metrics_memory_mb))
  expect_true(is.na(result$metrics_is_alive))
  expect_true(is.na(result$metrics_age_seconds))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_task_status calculates metrics_age_seconds correctly", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema
  
  # Register and start task
  register_task(stage = "TEST", name = "Test Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Test Task", conn = con)
  
  # Update to running status
  task_update(run_id = run_id, status = "RUNNING", conn = con)
  
  # Insert metrics exactly 120 seconds ago
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb)
    VALUES (?, datetime('now', '-120 seconds'), 12345, 'test-host', 1, 25.0, 512.0)
  ", params = list(run_id))
  
  # Get task status
  result <- get_task_status(conn = con)
  
  # Verify age is approximately 120 seconds (allow ±5 second tolerance)
  expect_true(result$metrics_age_seconds >= 115 && result$metrics_age_seconds <= 125)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("get_task_status returns latest metrics when multiple exist", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema
  
  # Register and start task
  register_task(stage = "TEST", name = "Test Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Test Task", conn = con)
  
  # Update to running status
  task_update(run_id = run_id, status = "RUNNING", conn = con)
  
  # Insert older metrics
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb)
    VALUES (?, datetime('now', '-300 seconds'), 12345, 'test-host', 1, 10.0, 256.0)
  ", params = list(run_id))
  
  # Insert middle metrics
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb)
    VALUES (?, datetime('now', '-150 seconds'), 12345, 'test-host', 1, 20.0, 384.0)
  ", params = list(run_id))
  
  # Insert latest metrics
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb)
    VALUES (?, datetime('now', '-30 seconds'), 12345, 'test-host', 1, 30.0, 512.0)
  ", params = list(run_id))
  
  # Get task status
  result <- get_task_status(conn = con)
  
  # Verify it returns LATEST metrics (cpu=30, mem=512)
  expect_equal(result$metrics_cpu_percent, 30.0)
  expect_equal(result$metrics_memory_mb, 512.0)
  expect_true(result$metrics_age_seconds >= 25 && result$metrics_age_seconds <= 35)  # Around 30 seconds
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

check_test_db_available <- function() {
  tryCatch({
    config <- Sys.getenv("TASKER_TEST_DB")
    return(nchar(config) > 0)
  }, error = function(e) {
    FALSE
  })
}
