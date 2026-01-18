# Tests for cleanup_old_metrics.R

library(tasker)

test_that("cleanup_old_metrics dry_run mode works", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema
  
  # Register and start old task
  register_task(stage = "TEST", name = "Old Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Old Task", conn = con)
  
  # Complete the task 45 days ago (manually update timestamp)
  DBI::dbExecute(con, "
    UPDATE task_runs 
    SET status = 'COMPLETED',
        end_time = datetime('now', '-45 days'),
        start_time = datetime('now', '-45 days', '-1 hour')
    WHERE run_id = ?
  ", params = list(run_id))
  
  # Insert metrics for old task
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, cpu_percent, memory_mb, is_alive)
    VALUES (?, datetime('now', '-45 days'), 12345, 'test-host', 25.5, 512.0, 1)
  ", params = list(run_id))
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, cpu_percent, memory_mb, is_alive)
    VALUES (?, datetime('now', '-44 days'), 12345, 'test-host', 30.0, 520.0, 1)
  ", params = list(run_id))
  
  # Count metrics before cleanup
  metrics_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM process_metrics")$n
  expect_equal(metrics_before, 2)
  
  # Run dry_run cleanup (30 day retention)
  result <- cleanup_old_metrics(retention_days = 30, conn = con, dry_run = TRUE, quiet = TRUE)
  
  # Verify result structure
  expect_true(is.data.frame(result))
  expect_true("run_id" %in% names(result))
  expect_true("task_name" %in% names(result))
  expect_true("metrics_deleted_count" %in% names(result))
  expect_true("completed_at" %in% names(result))
  
  # Verify it identified the old task
  expect_equal(nrow(result), 1)
  expect_equal(result$run_id, run_id)
  # Task name should match
  expect_true(grepl("Old", result$task_name, ignore.case = TRUE))
  expect_equal(result$metrics_deleted_count, 2)
  
  # Verify metrics were NOT deleted (dry run)
  metrics_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM process_metrics")$n
  expect_equal(metrics_after, 2)
  
  # Verify retention record was NOT created (dry run)
  retention_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM process_metrics_retention")$n
  expect_equal(retention_count, 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("cleanup_old_metrics deletes old metrics", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema
  
  # Register and start old task
  register_task(stage = "TEST", name = "Old Task", type = "R")
  old_run_id <- task_start(stage = "TEST", task = "Old Task", conn = con)
  
  # Complete old task 45 days ago
  DBI::dbExecute(con, "
    UPDATE task_runs 
    SET status = 'COMPLETED',
        end_time = datetime('now', '-45 days'),
        start_time = datetime('now', '-45 days', '-1 hour')
    WHERE run_id = ?
  ", params = list(old_run_id))
  
  # Insert metrics for old task
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, cpu_percent, memory_mb, is_alive)
    VALUES (?, datetime('now', '-45 days'), 12345, 'test-host', 25.5, 512.0, 1)
  ", params = list(old_run_id))
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, cpu_percent, memory_mb, is_alive)
    VALUES (?, datetime('now', '-44 days'), 12345, 'test-host', 30.0, 520.0, 1)
  ", params = list(old_run_id))
  
  # Register and start recent task (10 days ago) - should NOT be deleted
  register_task(stage = "TEST", name = "Recent Task", type = "R")
  recent_run_id <- task_start(stage = "TEST", task = "Recent Task", conn = con)
  
  # Complete recent task 10 days ago
  DBI::dbExecute(con, "
    UPDATE task_runs 
    SET status = 'COMPLETED',
        end_time = datetime('now', '-10 days'),
        start_time = datetime('now', '-10 days', '-30 minutes')
    WHERE run_id = ?
  ", params = list(recent_run_id))
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, cpu_percent, memory_mb, is_alive)
    VALUES (?, datetime('now', '-10 days'), 12346, 'test-host', 15.0, 256.0, 1)
  ", params = list(recent_run_id))
  
  # Count metrics before cleanup
  metrics_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM process_metrics")$n
  expect_equal(metrics_before, 3)
  
  # Run actual cleanup (30 day retention)
  result <- cleanup_old_metrics(retention_days = 30, conn = con, dry_run = FALSE, quiet = TRUE)
  
  # Verify it deleted only the old task
  expect_equal(nrow(result), 1)
  expect_equal(result$run_id, old_run_id)
  # Should have deleted 2 metrics
  expect_true(result$metrics_deleted_count >= 2)
  
  # Verify old metrics were deleted
  metrics_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM process_metrics")$n
  expect_equal(metrics_after, 1)
  
  # Verify recent metrics still exist
  recent_metrics <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as n FROM process_metrics WHERE run_id = ?
  ", params = list(recent_run_id))$n
  expect_equal(recent_metrics, 1)
  
  # Verify old metrics are gone
  old_metrics <- DBI::dbGetQuery(con, "
    SELECT COUNT(*) as n FROM process_metrics WHERE run_id = ?
  ", params = list(old_run_id))$n
  expect_equal(old_metrics, 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("cleanup_old_metrics records retention info", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema
  
  # Register and start old task
  register_task(stage = "TEST", name = "Old Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Old Task", conn = con)
  
  # Complete task 45 days ago
  DBI::dbExecute(con, "
    UPDATE task_runs 
    SET status = 'COMPLETED',
        end_time = datetime('now', '-45 days'),
        start_time = datetime('now', '-45 days', '-1 hour')
    WHERE run_id = ?
  ", params = list(run_id))
  
  # Insert metrics
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, cpu_percent, memory_mb, is_alive)
    VALUES (?, datetime('now', '-45 days'), 12345, 'test-host', 25.5, 512.0, 1)
  ", params = list(run_id))
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, cpu_percent, memory_mb, is_alive)
    VALUES (?, datetime('now', '-44 days'), 12345, 'test-host', 30.0, 520.0, 1)
  ", params = list(run_id))
  
  # Run cleanup
  result <- cleanup_old_metrics(retention_days = 30, conn = con, dry_run = FALSE, quiet = TRUE)
  
  # Verify retention record was created
  retention <- DBI::dbGetQuery(con, "
    SELECT * FROM process_metrics_retention WHERE run_id = ?
  ", params = list(run_id))
  
  expect_equal(nrow(retention), 1)
  expect_equal(retention$run_id, run_id)
  expect_equal(retention$metrics_deleted, 1)
  expect_equal(retention$metrics_count, 2)
  expect_false(is.na(retention$deleted_at))
  expect_false(is.na(retention$task_completed_at))
  expect_false(is.na(retention$metrics_delete_after))
  
  # Verify deleted_at is populated
  expect_true(nchar(retention$deleted_at) > 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("schedule_metrics_retention creates retention record", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema to create retention table
  
  # Test schedule_metrics_retention
  run_id <- "test-run-id-12345"
  completed_at <- Sys.time()
  
  # Call internal function
  tasker:::schedule_metrics_retention(
    run_id = run_id,
    completed_at = completed_at,
    retention_days = 30,
    conn = con
  )
  
  # Verify record was created
  retention <- DBI::dbGetQuery(con, "
    SELECT * FROM process_metrics_retention WHERE run_id = ?
  ", params = list(run_id))
  
  expect_equal(nrow(retention), 1)
  expect_equal(retention$run_id, run_id)
  expect_equal(retention$metrics_deleted, 0)  # Not yet deleted
  expect_true(is.na(retention$deleted_at))  # Not yet deleted
  expect_false(is.na(retention$task_completed_at))
  expect_false(is.na(retention$metrics_delete_after))
  
  # Verify metrics_delete_after is ~30 days after completion
  delete_after <- as.POSIXct(retention$metrics_delete_after, tz = "UTC")
  expected_delete <- completed_at + (30 * 24 * 60 * 60)
  time_diff <- abs(as.numeric(difftime(delete_after, expected_delete, units = "hours")))
  expect_true(time_diff < 1)  # Within 1 hour (account for rounding)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("cleanup_old_metrics handles empty database", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema (creates tables but no data)
  
  # Should not error on empty database
  result <- cleanup_old_metrics(retention_days = 30, conn = con, dry_run = FALSE, quiet = TRUE)
  
  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 0)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})

test_that("cleanup_old_metrics respects retention_days parameter", {
  skip_if_not_installed("RSQLite")
  
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  
  # Setup reporter schema
  
  # Register and start task completed 15 days ago
  register_task(stage = "TEST", name = "Medium Old Task", type = "R")
  run_id <- task_start(stage = "TEST", task = "Medium Old Task", conn = con)
  
  # Complete task 15 days ago
  DBI::dbExecute(con, "
    UPDATE task_runs 
    SET status = 'COMPLETED',
        end_time = datetime('now', '-15 days'),
        start_time = datetime('now', '-15 days', '-30 minutes')
    WHERE run_id = ?
  ", params = list(run_id))
  
  DBI::dbExecute(con, "
    INSERT INTO process_metrics (run_id, timestamp, process_id, hostname, is_alive)
    VALUES (?, datetime('now', '-15 days'), 12345, 'test-host', 1)
  ", params = list(run_id))
  
  # With 30 day retention, should NOT be deleted
  result_30 <- cleanup_old_metrics(retention_days = 30, conn = con, dry_run = TRUE, quiet = TRUE)
  expect_equal(nrow(result_30), 0)
  
  # With 7 day retention, SHOULD be deleted
  result_7 <- cleanup_old_metrics(retention_days = 7, conn = con, dry_run = TRUE, quiet = TRUE)
  expect_equal(nrow(result_7), 1)
  expect_equal(result_7$run_id, run_id)
  
  DBI::dbDisconnect(con)
  cleanup_test_db()
})
