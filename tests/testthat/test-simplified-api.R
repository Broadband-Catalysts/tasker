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

test_that("tasker_cluster setup_expr executes on workers", {
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
  
  # Test 1: Basic setup_expr execution
  # Create cluster with setup_expr that sets a variable
  cl <- tasker::tasker_cluster(
    ncores = 1,
    load_all = TRUE,
    setup_expr = quote({
      test_var <- "setup_executed"
      test_value <- 42
      NULL  # Return NULL to avoid serialization
    })
  )
  on.exit(tasker::stop_tasker_cluster(cl), add = TRUE)
  
  # Verify workers can access variables created in setup_expr
  results <- parallel::parLapply(cl, 1:3, function(x) {
    list(var = test_var, value = test_value, input = x)
  })
  
  expect_equal(length(results), 3)
  expect_equal(results[[1]]$var, "setup_executed")
  expect_equal(results[[1]]$value, 42)
  expect_equal(results[[2]]$input, 2)
  
  tasker::stop_tasker_cluster(cl)
  
  # Test 2: Database connection setup (simulating dbConnectBBC pattern)
  # Use SQLite connection as a non-serializable object
  cl2 <- tasker::tasker_cluster(
    ncores = 1,
    load_all = TRUE,
    export = "test_db",  # Export test_db so it's available in setup_expr
    setup_expr = quote({
      # Create a database connection (non-serializable object)
      worker_conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
      NULL  # Important: return NULL to avoid serialization error
    })
  )
  on.exit(tasker::stop_tasker_cluster(cl2), add = TRUE)
  
  # Verify workers can use the connection created in setup_expr
  results2 <- parallel::parLapply(cl2, 1:3, function(x) {
    tryCatch({
      # Check if connection exists and is valid
      if (exists("worker_conn") && DBI::dbIsValid(worker_conn)) {
        # Try to query the database
        tables <- DBI::dbListTables(worker_conn)
        list(success = TRUE, has_tables = length(tables) > 0, input = x)
      } else {
        list(success = FALSE, error = "Connection not found or invalid")
      }
    }, error = function(e) {
      list(success = FALSE, error = e$message)
    })
  })
  
  expect_equal(length(results2), 3)
  expect_true(results2[[1]]$success, 
              info = paste("Worker 1 error:", results2[[1]]$error))
  expect_true(results2[[1]]$has_tables, 
              info = "Worker should have access to database tables")
  
  tasker::stop_tasker_cluster(cl2)
  
  # Test 3: Error handling in setup_expr
  # This should create cluster successfully even if setup_expr fails
  cl3 <- tasker::tasker_cluster(
    ncores = 1,
    load_all = TRUE,
    setup_expr = quote({
      # This will fail but should be caught
      non_existent_function()
      NULL
    })
  )
  on.exit(tasker::stop_tasker_cluster(cl3), add = TRUE)
  
  # Cluster should still be usable despite setup error
  expect_true(!is.null(cl3))
  expect_true(!is.null(attr(cl3, "tasker_managed")))
  
  # Workers should still be able to execute tasks
  results3 <- parallel::parLapply(cl3, 1:2, function(x) x * 2)
  expect_equal(results3, list(2, 4))
  
  tasker::stop_tasker_cluster(cl3)
})

test_that("tasker_cluster setup_expr without NULL return causes no issues", {
  skip_on_cran()
  skip_if_not(requireNamespace("parallel", quietly = TRUE))
  
  # Test that the implementation's forced NULL return prevents serialization errors
  # even when user forgets to return NULL explicitly
  
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  # Setup_expr returns a connection object, but implementation should handle it
  cl <- tasker::tasker_cluster(
    ncores = 1,
    load_all = TRUE,
    setup_expr = quote({
      # User might forget to return NULL
      worker_conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      worker_conn  # This would normally cause serialization error
    })
  )
  on.exit(tasker::stop_tasker_cluster(cl), add = TRUE)
  
  # Should still work because implementation forces NULL return
  expect_true(!is.null(cl))
  
  # Workers should be functional
  results <- parallel::parLapply(cl, 1:2, function(x) x + 1)
  expect_equal(results, list(2, 3))
  
  tasker::stop_tasker_cluster(cl)
})
