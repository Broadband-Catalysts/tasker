# Test that all tasker functions can create their own database connections
# when none exist in the context.
#
# This is a critical edge case that can occur during:
# - Script cleanup (.Last functions)
# - Long-running processes where connections have closed
# - Library functions that don't maintain context

library(testthat)

test_that("task_start creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Connection Test", "R")
  
  # Start task without passing connection - should create its own
  run_id <- tasker::task_start("TEST", "Connection Test", .active = FALSE)
  
  # Verify in database
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = ?",
    params = list(run_id))
  
  expect_equal(nrow(result), 1)
  expect_equal(result$status, "STARTED")
})

test_that("task_update creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Update Test", "R")
  
  # Start task with context
  run_id <- tasker::task_start("TEST", "Update Test", .active = FALSE)
  
  # Update without connection - should create its own
  tasker::task_update(
    status = "RUNNING",
    overall_percent = 50,
    message = "Processing",
    run_id = run_id
  )
  
  # Verify update succeeded
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = ?",
    params = list(run_id))
  
  expect_equal(result$status, "RUNNING")
  expect_equal(result$overall_percent_complete, 50)
})

test_that("task_complete creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Complete Test", "R")
  
  # Start task
  run_id <- tasker::task_start("TEST", "Complete Test", .active = FALSE)
  
  # Complete without connection - should create its own
  tasker::task_complete(message = "All done", run_id = run_id)
  
  # Verify completion
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = ?",
    params = list(run_id))
  
  expect_equal(result$status, "COMPLETED")
  expect_equal(result$overall_percent_complete, 100)
})

test_that("task_fail creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Fail Test", "R")
  
  # Start task
  run_id <- tasker::task_start("TEST", "Fail Test", .active = FALSE)
  
  # Fail without connection - should create its own
  # This is the critical test that would have caught the original bug
  tasker::task_fail(
    error_message = "Test failure",
    error_detail = "Detailed error info",
    run_id = run_id
  )
  
  # Verify failure was recorded
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = ?",
    params = list(run_id))
  
  expect_equal(result$status, "FAILED")
  expect_equal(result$error_message, "Test failure")
  expect_equal(result$error_detail, "Detailed error info")
})

test_that("subtask_start creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Subtask Start Test", "R")
  
  # Start task
  run_id <- tasker::task_start("TEST", "Subtask Start Test", .active = FALSE)
  
  # Start subtask without connection - should create its own
  tasker::subtask_start(
    subtask_name = "Test Subtask",
    items_total = 100,
    run_id = run_id,
    subtask_number = 1
  )
  
  # Verify subtask was created
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM subtask_progress WHERE run_id = ? AND subtask_number = 1",
    params = list(run_id))
  
  expect_equal(nrow(result), 1)
  expect_equal(result$subtask_name, "Test Subtask")
  expect_equal(result$items_total, 100)
})

test_that("subtask_update creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Subtask Update Test", "R")
  
  # Start task and subtask
  run_id <- tasker::task_start("TEST", "Subtask Update Test", .active = FALSE)
  tasker::subtask_start("Test Subtask", run_id = run_id, subtask_number = 1)
  
  # Update subtask without connection - should create its own
  tasker::subtask_update(
    status = "RUNNING",
    percent = 50,
    items_complete = 50,
    run_id = run_id,
    subtask_number = 1
  )
  
  # Verify update
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM subtask_progress WHERE run_id = ? AND subtask_number = 1",
    params = list(run_id))
  
  expect_equal(result$status, "RUNNING")
  expect_equal(result$percent_complete, 50)
  expect_equal(result$items_complete, 50)
})

test_that("subtask_complete creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Subtask Complete Test", "R")
  
  # Start task and subtask
  run_id <- tasker::task_start("TEST", "Subtask Complete Test", .active = FALSE)
  tasker::subtask_start("Test Subtask", run_id = run_id, subtask_number = 1)
  
  # Complete subtask without connection - should create its own
  tasker::subtask_complete(
    items_completed = 100,
    message = "Done",
    run_id = run_id,
    subtask_number = 1
  )
  
  # Verify completion
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM subtask_progress WHERE run_id = ? AND subtask_number = 1",
    params = list(run_id))
  
  expect_equal(result$status, "COMPLETED")
  expect_equal(result$percent_complete, 100)
  expect_equal(result$items_complete, 100)
})

test_that("subtask_increment creates connection when needed", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Subtask Increment Test", "R")
  
  # Start task and subtask
  run_id <- tasker::task_start("TEST", "Subtask Increment Test", .active = FALSE)
  tasker::subtask_start("Test Subtask", items_total = 10, run_id = run_id, subtask_number = 1)
  
  # Increment without connection - should create its own
  # This is critical for parallel workers
  tasker::subtask_increment(increment = 1, run_id = run_id, subtask_number = 1)
  tasker::subtask_increment(increment = 2, run_id = run_id, subtask_number = 1)
  
  # Verify increments
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM subtask_progress WHERE run_id = ? AND subtask_number = 1",
    params = list(run_id))
  
  expect_equal(result$items_complete, 3)  # 1 + 2
})

test_that("task_fail handles already-failed subtasks gracefully", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Subtask Fail Test", "R")
  
  # Start task with subtasks
  run_id <- tasker::task_start("TEST", "Subtask Fail Test", .active = FALSE)
  tasker::subtask_start("Subtask 1", run_id = run_id, subtask_number = 1)
  tasker::subtask_start("Subtask 2", run_id = run_id, subtask_number = 2)
  
  # Complete one subtask
  tasker::subtask_complete(run_id = run_id, subtask_number = 1)
  
  # Fail task - should fail only active subtasks
  tasker::task_fail(
    error_message = "Task failed",
    run_id = run_id
  )
  
  # Verify both task and subtasks
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  task_result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = ?",
    params = list(run_id))
  expect_equal(task_result$status, "FAILED")
  
  subtask_results <- DBI::dbGetQuery(conn,
    "SELECT subtask_number, status FROM subtask_progress WHERE run_id = ? ORDER BY subtask_number",
    params = list(run_id))
  
  expect_equal(nrow(subtask_results), 2)
  expect_equal(subtask_results$status[1], "COMPLETED")  # Already completed
  expect_equal(subtask_results$status[2], "FAILED")      # Was active, now failed
})

test_that("connection creation works in cleanup/error scenarios", {
  skip_on_cran()
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Cleanup Test", "R")
  
  # Simulate a script that encounters an error during cleanup
  run_id <- NULL
  
  # This simulates what happens in .Last during script cleanup
  tryCatch({
    run_id <- tasker::task_start("TEST", "Cleanup Test", .active = FALSE)
    
    # Do some work
    tasker::subtask_start("Work", run_id = run_id, subtask_number = 1)
    
    # Simulate script completion
    tasker::subtask_complete(run_id = run_id, subtask_number = 1)
    tasker::task_complete(run_id = run_id)
    
    # Simulate an error that occurs during .Last cleanup
    # At this point, the task is already complete but we try to fail it
    stop("Simulated cleanup error")
    
  }, error = function(e) {
    # This is where the original bug was triggered
    # task_fail tried to call create_connection() which didn't exist
    if (!is.null(run_id)) {
      tasker::task_fail(
        error_message = conditionMessage(e),
        error_detail = "Error during cleanup",
        run_id = run_id
      )
    }
  })
  
  # Verify the task ended up in FAILED state (not COMPLETED)
  # because task_fail overwrites the previous status
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  result <- DBI::dbGetQuery(conn,
    "SELECT * FROM task_runs WHERE run_id = ?",
    params = list(run_id))
  
  expect_equal(result$status, "FAILED")
  expect_match(result$error_message, "Simulated cleanup error")
})
