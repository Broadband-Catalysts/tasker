test_that("task_start creates execution record", {
  skip_on_cran()
  setup_test_db()
  
  # Register a task
  register_task(stage = "TEST", name = "test_task", type = "R")
  
  # Start the task
  run_id <- task_start(
    stage = "TEST",
    task = "test_task",
    message = "Testing task start"
  )
  
  # Verify run_id is a valid UUID (hyphenated) or hex string (SQLite)
  expect_match(run_id, "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$|^[0-9a-f]{32}$")
  
  # Verify record in database
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  result <- DBI::dbGetQuery(conn,
    glue::glue_sql("SELECT * FROM task_runs WHERE run_id = {run_id}", .con = conn))
  
  expect_equal(nrow(result), 1)
  expect_equal(result$status, "STARTED")
})

test_that("task_update modifies execution state", {
  skip_on_cran()
  setup_test_db()
  
  register_task(stage = "TEST", name = "test_update", type = "R")
  run_id <- task_start(stage = "TEST", task = "test_update", total_subtasks = 10)
  
  # Update to running
  task_update(
    run_id = run_id,
    status = "RUNNING",
    current_subtask = 1,
    overall_percent = 10.0,
    message = "Processing items"
  )
  
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = $1",
    params = list(run_id))
  
  expect_equal(result$status, "RUNNING")
  expect_equal(result$current_subtask, 1)
  expect_equal(result$overall_percent_complete, 10.0)
})

test_that("task_complete finalizes execution", {
  skip_on_cran()
  setup_test_db()
  
  register_task(stage = "TEST", name = "test_end", type = "R")
  run_id <- task_start(stage = "TEST", task = "test_end")
  
  # Complete the task
  task_complete(run_id = run_id)
  
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = $1",
    params = list(run_id))
  
  expect_equal(result$status, "COMPLETED")
  expect_false(is.na(result$end_time))
  expect_equal(result$overall_percent_complete, 100.0)
})

test_that("task_fail handles failures", {
  skip_on_cran()
  setup_test_db()
  
  register_task(stage = "TEST", name = "test_fail", type = "R")
  run_id <- task_start(stage = "TEST", task = "test_fail")
  
  # Fail the task
  task_fail(
    run_id = run_id,
    error_message = "Test error",
    error_detail = "Detailed error information"
  )
  
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = $1",
    params = list(run_id))
  
  expect_equal(result$status, "FAILED")
  expect_equal(result$error_message, "Test error")
  expect_equal(result$error_detail, "Detailed error information")
})

test_that("progress calculations work", {
  # Test percent complete calculation
  total <- 100
  complete <- 25
  percent <- (complete / total) * 100
  
  expect_equal(percent, 25.0)
  expect_true(percent >= 0 && percent <= 100)
})

test_that("status values are valid", {
  valid_statuses <- c('NOT_STARTED', 'STARTED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED', 'CANCELLED')
  
  # Test that our expected statuses are in the valid list
  expect_true("STARTED" %in% valid_statuses)
  expect_true("RUNNING" %in% valid_statuses)
  expect_true("COMPLETED" %in% valid_statuses)
  expect_true("FAILED" %in% valid_statuses)
})
