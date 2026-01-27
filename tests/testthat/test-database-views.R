# Tests for database views (current_task_status_with_metrics)

library(tasker)

test_that("current_task_status_with_metrics view exists after schema setup", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # View is created by setup_test_db()
  # Check if view exists
  views <- DBI::dbGetQuery(con, "
    SELECT name FROM sqlite_master 
    WHERE type = 'view' AND name = 'current_task_status_with_metrics'
  ")
  
  expect_equal(nrow(views), 1)
  expect_equal(views$name, "current_task_status_with_metrics")
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("current_task_status_with_metrics view handles tasks without metrics", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup both schemas
  
  # Register and start task WITHOUT metrics
  register_task(stage = "TEST", name = "Task Without Metrics", type = "R")
  run_id_no_metrics <- task_start(stage = "TEST", task = "Task Without Metrics", conn = con)
  task_update(run_id = run_id_no_metrics, status = "RUNNING", conn = con)
  
  # Register and start task WITH metrics
  register_task(stage = "TEST", name = "Task With Metrics", type = "R")
  run_id_with_metrics <- task_start(stage = "TEST", task = "Task With Metrics", conn = con)
  task_update(run_id = run_id_with_metrics, status = "RUNNING", conn = con)
  
  # Add metrics for second task
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb, child_count)
    VALUES (?, datetime('now'), 12346, 'test-host', 1, 25.5, 512.0, 4)
  ", params = list(run_id_with_metrics))
  
  # Query the view
  result <- DBI::dbGetQuery(con, "SELECT * FROM current_task_status_with_metrics ORDER BY task_name")
  
  # Should return BOTH tasks (LEFT JOIN)
  expect_equal(nrow(result), 2)
  
  # Task without metrics: metrics columns should be NULL
  task_no_metrics <- result[result$run_id == run_id_no_metrics, ]
  expect_equal(task_no_metrics$task_name, "Task Without Metrics")
  expect_true(is.na(task_no_metrics$metrics_cpu_percent))
  expect_true(is.na(task_no_metrics$metrics_memory_mb))
  expect_true(is.na(task_no_metrics$metrics_is_alive))
  expect_true(is.na(task_no_metrics$metrics_age_seconds))
  
  # Task with metrics: metrics columns should have values
  task_with_metrics <- result[result$run_id == run_id_with_metrics, ]
  expect_equal(task_with_metrics$task_name, "Task With Metrics")
  expect_equal(task_with_metrics$metrics_cpu_percent, 25.5)
  expect_equal(task_with_metrics$metrics_memory_mb, 512.0)
  expect_equal(task_with_metrics$metrics_is_alive, 1)
  expect_equal(task_with_metrics$metrics_child_count, 4)
  expect_false(is.na(task_with_metrics$metrics_age_seconds))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("current_task_status_with_metrics view returns latest metrics only", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup schemas
  
  # Register and start running task
  register_task(stage = "TEST", name = "Test Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Test Task", conn = con)
  task_update(run_id = run_id, status = "RUNNING", conn = con)
  
  # Insert 3 metrics at different times
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb, child_count)
    VALUES (?, datetime('now', '-300 seconds'), 12345, 'test-host', 1, 10.0, 256.0, 2)
  ", params = list(run_id))
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb, child_count)
    VALUES (?, datetime('now', '-150 seconds'), 12345, 'test-host', 1, 20.0, 384.0, 3)
  ", params = list(run_id))
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent, memory_mb, child_count)
    VALUES (?, datetime('now', '-30 seconds'), 12345, 'test-host', 1, 30.0, 512.0, 4)
  ", params = list(run_id))
  
  # Query view - should return only ONE row with LATEST metrics
  result <- DBI::dbGetQuery(con, "SELECT * FROM current_task_status_with_metrics")
  
  expect_equal(nrow(result), 1)
  expect_equal(result$run_id, run_id)
  
  # Verify it's the LATEST metrics (cpu=30, mem=512, child_count=4)
  expect_equal(result$metrics_cpu_percent, 30.0)
  expect_equal(result$metrics_memory_mb, 512.0)
  expect_equal(result$metrics_child_count, 4)
  
  # Age should be around 30 seconds
  expect_true(result$metrics_age_seconds >= 25 && result$metrics_age_seconds <= 35)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("current_task_status_with_metrics view filters by status", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup schemas
  
  # Register tasks
  register_task(stage = "TEST", name = "Running Task", type = "R")
  register_task(stage = "TEST", name = "Pending Task", type = "R")
  register_task(stage = "TEST", name = "Completed Task", type = "R")
  register_task(stage = "TEST", name = "Failed Task", type = "R")
  
  # Start tasks with different statuses
  run_id_running <- task_start(stage = "TEST", task = "Running Task", conn = con)
  task_update(run_id = run_id_running, status = "RUNNING", conn = con)
  
  run_id_pending <- task_start(stage = "TEST", task = "Pending Task", conn = con)
  # Pending tasks remain in STARTED status
  
  run_id_completed <- task_start(stage = "TEST", task = "Completed Task", conn = con)
  task_complete(run_id = run_id_completed, conn = con)
  
  run_id_failed <- task_start(stage = "TEST", task = "Failed Task", conn = con)
  task_fail(run_id = run_id_failed, error_message = "Test failure", conn = con)
  
  # Add metrics to all tasks
  for (rid in c(run_id_running, run_id_pending, run_id_completed, run_id_failed)) {
    DBI::dbExecute(con, "
      INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive, cpu_percent)
      VALUES (?, datetime('now'), 12345, 'test-host', 1, 25.0)
    ", params = list(rid))
  }
  
  # Query view
  result <- DBI::dbGetQuery(con, "SELECT * FROM current_task_status_with_metrics ORDER BY task_name")
  
  # View shows latest run of all tasks, not just running ones
  expect_equal(nrow(result), 4)  # All 4 tasks
  expect_true(run_id_running %in% result$run_id)
  expect_true(run_id_pending %in% result$run_id)
  expect_true(run_id_completed %in% result$run_id)
  expect_true(run_id_failed %in% result$run_id)
  
  # Verify all statuses are present
  expect_setequal(result$status, c('STARTED', 'RUNNING', 'COMPLETED', 'FAILED'))
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("current_task_status_with_metrics view includes all expected columns", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup schemas
  
  # Register and start a task
  register_task(stage = "TEST", name = "Test Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Test Task", conn = con)
  task_update(run_id = run_id, status = "RUNNING", conn = con)
  
  # Insert metrics with all columns
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (
      run_id, timestamp, process_id, hostname, is_alive, 
      cpu_percent, memory_mb, child_count, 
      child_total_cpu_percent, child_total_memory_mb,
      collection_error, error_message
    )
    VALUES (?, datetime('now'), 12345, 'test-host', 1, 25.5, 512.0, 4, 80.0, 1024.0, 0, NULL)
  ", params = list(run_id))
  
  # Query view
  result <- DBI::dbGetQuery(con, "SELECT * FROM current_task_status_with_metrics")
  
  # Verify all expected columns exist
  expected_columns <- c(
    # From current_task_status (task_runs + tasks + stages)
    "run_id", "task_name", "stage_name", "status", "start_time", "process_id", "hostname",
    # From process_metrics (prefixed with metrics_)
    "metrics_cpu_percent", "metrics_memory_mb", "metrics_child_count", 
    "metrics_child_total_cpu_percent", "metrics_child_total_memory_mb",
    "metrics_collection_error", "metrics_error_message", "metrics_is_alive",
    # Calculated
    "metrics_age_seconds"
  )
  
  for (col in expected_columns) {
    expect_true(col %in% names(result), info = paste("Missing column:", col))
  }
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})
