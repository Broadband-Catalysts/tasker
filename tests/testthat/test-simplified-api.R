# Quick test of the simplified API
library(testthat)

test_that("Context-based API works", {
  skip_on_cran()
  
  # Set up test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  # Configure with SQLite
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  # Create schema
  tasker::setup_tasker_db()
  
  # Register a test task
  tasker::register_task("TEST", "Simplified API Test", "R")
  
  # Test context-based workflow
  tasker::task_start("TEST", "Simplified API Test")
  
  # Check context is set
  expect_true(!is.null(tasker::tasker_context()))
  
  # Test auto-numbered subtasks
  tasker::subtask_start("First subtask")
  tasker::subtask_complete()
  
  tasker::subtask_start("Second subtask")
  tasker::subtask_complete()
  
  # Test completion without parameters
  tasker::task_complete()
  
  # Verify in database
  status <- tasker::get_task_status()
  expect_equal(nrow(status), 1)
  expect_equal(status$status, "COMPLETED")
})

test_that("Backward compatibility maintained", {
  skip_on_cran()
  
  # Set up test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  # Configure with SQLite
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  # Create schema
  tasker::setup_tasker_db()
  
  # Register a test task
  tasker::register_task("TEST", "Old API Test", "R")
  
  # Test old-style API (explicit parameters)
  run_id <- tasker::task_start("TEST", "Old API Test", .active = FALSE)
  
  tasker::subtask_start("Explicit subtask", run_id = run_id, subtask_number = 1)
  tasker::subtask_complete(run_id = run_id, subtask_number = 1)
  
  tasker::task_complete(run_id = run_id)
  
  # Verify in database
  status <- tasker::get_task_status()
  expect_equal(nrow(status), 1)
  expect_equal(status$status, "COMPLETED")
})

test_that("tasker_cluster helper works", {
  skip_on_cran()
  skip_if_not(requireNamespace("parallel", quietly = TRUE))
  
  # Set up test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  # Configure
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  tasker::setup_tasker_db()
  tasker::register_task("TEST", "Parallel Test", "R")
  
  # Start task
  tasker::task_start("TEST", "Parallel Test")
  tasker::subtask_start("Parallel work", items_total = 10)
  
  # Create cluster with load_all for dev package
  cl <- tasker::tasker_cluster(ncores = 2, load_all = TRUE)
  expect_true(!is.null(cl))
  expect_true(!is.null(attr(cl, "tasker_managed")))
  
  # Simple parallel work
  results <- parallel::parLapply(cl, 1:10, function(x) {
    tasker::subtask_increment(increment = 1, quiet = TRUE)
    x * 2
  })
  
  # Stop cluster
  tasker::stop_tasker_cluster(cl)
  
  expect_equal(length(results), 10)
  expect_equal(results[[5]], 10)
  
  # Verify counter was actually incremented in database
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  subtask_result <- DBI::dbGetQuery(conn,
    "SELECT items_complete FROM subtask_progress WHERE subtask_number = 1")
  
  expect_equal(nrow(subtask_result), 1)
  expect_equal(subtask_result$items_complete, 10,
               info = sprintf("Expected 10 items incremented, got %d", subtask_result$items_complete))
  
  # Complete
  tasker::subtask_complete()
  tasker::task_complete()
})
