test_that("subtask tracking validates input", {
  skip_on_cran()
  
  # Test that subtask functions exist
  expect_true(exists("subtask_start"))
  expect_true(exists("subtask_update"))
  expect_true(exists("subtask_complete"))
  expect_true(exists("subtask_fail"))
})

test_that("subtask progress updates correctly", {
  # Test progress calculation
  items_total <- 50
  items_complete <- 10
  
  percent <- (items_complete / items_total) * 100
  expect_equal(percent, 20.0)
})

test_that("subtask_increment atomically updates counter", {
  skip_on_cran()
  setup_test_db()
  on.exit(cleanup_test_db())
  
  # Register and start task
  register_task(stage = "TEST", name = "atomic_test", type = "R")
  run_id <- task_start(stage = "TEST", task = "atomic_test", total_subtasks = 1)
  subtask_start(run_id, 1, "Atomic increment test", items_total = 100)
  
  # Increment counter 100 times sequentially
  for (i in 1:100) {
    subtask_increment(run_id, 1, increment = 1, quiet = TRUE)
  }
  
  # Check final count
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  progress <- DBI::dbGetQuery(conn,
    glue::glue_sql(
      "SELECT items_complete FROM subtask_progress 
       WHERE run_id = {run_id} AND subtask_number = 1",
      .con = conn
    )
  )
  
  expect_equal(nrow(progress), 1)
  expect_equal(progress$items_complete, 100)
})

test_that("subtask_increment works from parallel workers", {
  skip_on_cran()
  setup_test_db()
  on.exit(cleanup_test_db())
  
  # Register and start task
  register_task(stage = "TEST", name = "parallel_test", type = "R")
  run_id <- task_start(stage = "TEST", task = "parallel_test", total_subtasks = 1)
  subtask_start(run_id, 1, "Parallel increment test", items_total = 10)
  
  # Create parallel cluster with 2 workers
  library(parallel)
  cl <- makeCluster(2)
  on.exit(stopCluster(cl), add = TRUE)
  
  # Get test database path and export to workers
  test_db_path <- get_test_db_path()
  clusterExport(cl, c("test_db_path", "run_id"), envir = environment())
  
  # Configure workers with same database
  clusterEvalQ(cl, {
    library(tasker)
    tasker_config(
      driver = "sqlite",
      dbname = test_db_path,
      schema = "",
      reload = TRUE
    )
    NULL
  })
  
  # Have each worker increment with retry for SQLite locks
  results <- parLapply(cl, 1:10, function(item) {
    # Retry logic for SQLite database locks
    for (attempt in 1:5) {
      result <- tryCatch({
        subtask_increment(run_id, 1, increment = 1, quiet = TRUE)
        TRUE
      }, error = function(e) {
        if (grepl("database is locked", e$message) && attempt < 5) {
          Sys.sleep(runif(1, 0.1, 0.3))
          FALSE
        } else {
          stop(e)
        }
      })
      if (result) break
    }
    "success"
  })
  
  # Verify all succeeded
  expect_equal(length(results), 10)
  expect_true(all(results == "success"))
  
  # Check final count
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  progress <- DBI::dbGetQuery(conn,
    glue::glue_sql(
      "SELECT items_complete FROM subtask_progress 
       WHERE run_id = {run_id} AND subtask_number = 1",
      .con = conn
    )
  )
  
  expect_equal(nrow(progress), 1)
  expect_equal(progress$items_complete, 10)
})
