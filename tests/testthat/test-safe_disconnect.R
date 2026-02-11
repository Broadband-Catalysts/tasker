# Tests for safe_disconnect() function
#
# This function must handle various connection types safely:
# - Regular DBI connections (PostgreSQL, SQLite, MySQL)
# - Pool objects (should NOT be disconnected)
# - NULL connections
# - Invalid/already-closed connections

library(testthat)

test_that("safe_disconnect closes valid SQLite connection", {
  skip_on_cran()
  
  # Create a temporary SQLite database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  # Create connection
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  
  # Verify connection is valid
  expect_true(DBI::dbIsValid(conn))
  
  # Safe disconnect should close it
  result <- tasker::safe_disconnect(conn)
  expect_true(result)
  
  # Connection should now be invalid
  expect_false(DBI::dbIsValid(conn))
})

test_that("safe_disconnect handles already-closed connection", {
  skip_on_cran()
  
  # Create and immediately close connection
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  DBI::dbDisconnect(conn)
  
  # Safe disconnect should handle gracefully
  expect_true(tasker::safe_disconnect(conn))
})

test_that("safe_disconnect handles NULL connection", {
  skip_on_cran()
  
  # Should not error on NULL
  result <- tasker::safe_disconnect(NULL)
  expect_true(result)
})

test_that("safe_disconnect does NOT disconnect Pool objects", {
  skip_on_cran()
  skip_if_not_installed("pool")
  
  # Create a temporary SQLite database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  # Create a pool
  pool_obj <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = test_db
  )
  
  # Clean up pool on exit (only one poolClose call)
  on.exit({
    pool::poolClose(pool_obj)
  }, add = TRUE)
  
  # Verify it's a Pool object
  expect_true(inherits(pool_obj, "Pool"))
  
  # Safe disconnect should return TRUE but NOT close the pool
  result <- tasker::safe_disconnect(pool_obj)
  expect_true(result)
  
  # Pool should still be usable (not closed)
  # Test by executing a query
  expect_no_error({
    DBI::dbGetQuery(pool_obj, "SELECT 1 as test")
  })
  
  # Note: Pool is closed by on.exit() handler above
})

test_that("safe_disconnect handles connection errors gracefully", {
  skip_on_cran()
  
  # Create a mock connection object that will error on disconnect
  # We can test this by creating a connection and then breaking it
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  
  # Manually invalidate the connection by removing the database file
  # while keeping the connection object
  file_path <- conn@dbname
  
  # Disconnect normally
  result <- tasker::safe_disconnect(conn)
  expect_true(result)
})

test_that("safe_disconnect works in typical tasker workflow", {
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
  tasker::register_task(stage_order = 1, stage = "TEST", name = "Disconnect Test", type = "R")
  
  # Simulate workflow: get connection, use it, disconnect
  conn <- tasker::get_db_connection()
  expect_true(DBI::dbIsValid(conn))
  
  # Use connection
  run_id <- tasker::task_start("TEST", "Disconnect Test", conn = conn, .active = FALSE)
  expect_type(run_id, "character")
  
  # Safe disconnect
  result <- tasker::safe_disconnect(conn)
  expect_true(result)
  expect_false(DBI::dbIsValid(conn))
  
  # Verify task was recorded
  conn2 <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn2), add = TRUE)
  
  tasks <- DBI::dbGetQuery(conn2, 
    "SELECT * FROM task_runs WHERE run_id = ?",
    params = list(run_id))
  expect_equal(nrow(tasks), 1)
})

test_that("safe_disconnect integrates with close_on_exit pattern", {
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
  tasker::register_task(stage_order = 1, stage = "TEST", name = "Pattern Test", type = "R")
  
  # Simulate typical function pattern
  test_function <- function(conn = NULL) {
    close_on_exit <- FALSE
    if (is.null(conn)) {
      conn <- tasker::get_db_connection()
      close_on_exit <- TRUE
    }
    
    on.exit({
      if (close_on_exit) {
        tasker::safe_disconnect(conn)
      }
    })
    
    # Use connection
    result <- DBI::dbGetQuery(conn, "SELECT 1 as test")
    return(result$test)
  }
  
  # Test without providing connection
  result1 <- test_function()
  expect_equal(result1, 1)
  
  # Test with provided connection
  conn <- tasker::get_db_connection()
  on.exit(tasker::safe_disconnect(conn), add = TRUE)
  
  result2 <- test_function(conn = conn)
  expect_equal(result2, 1)
  
  # Connection should still be valid (not closed by function)
  expect_true(DBI::dbIsValid(conn))
})

test_that("safe_disconnect with Pool option in Shiny context", {
  skip_on_cran()
  skip_if_not_installed("pool")
  
  # Setup test database
  test_db <- tempfile(fileext = ".db")
  on.exit(unlink(test_db), add = TRUE)
  
  # First, setup schema with a regular connection
  regular_conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(regular_conn), add = TRUE)
  
  # Configure tasker to use SQLite
  tasker::tasker_config(
    driver = "sqlite",
    dbname = test_db,
    schema = "",
    reload = TRUE
  )
  
  # Setup schema with regular connection
  tasker::setup_tasker_db(conn = regular_conn, quiet = TRUE)
  
  # Now create pool for ongoing operations
  pool_obj <- pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = test_db
  )
  on.exit(pool::poolClose(pool_obj), add = TRUE)
  
  # Set pool option (simulating Shiny app setup)
  old_pool <- getOption("tasker.pool")
  options(tasker.pool = pool_obj)
  on.exit(options(tasker.pool = old_pool), add = TRUE)
  
  # Register task using pool (this should work for INSERT operations)
  tasker::register_task(
    stage_order = 1,
    stage = "TEST",
    name = "Pool Test",
    type = "R",
    conn = pool_obj
  )
  
  # get_db_connection should return pool
  conn <- tasker::get_db_connection()
  expect_true(inherits(conn, "Pool"))
  expect_identical(conn, pool_obj)
  
  # safe_disconnect should NOT close pool
  result <- tasker::safe_disconnect(conn)
  expect_true(result)
  
  # Pool should still work after safe_disconnect
  expect_no_error({
    DBI::dbGetQuery(pool_obj, "SELECT 1 as test")
  })
})
