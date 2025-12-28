test_that("subtask_increment works in parallel workers", {
  skip_on_cran()
  setup_test_db()
  
  # Register a task
  register_task(stage = "TEST", name = "parallel_test", type = "R")
  
  # Start the task with subtasks
  run_id <- task_start(
    stage = "TEST",
    task = "parallel_test",
    total_subtasks = 1
  )
  
  # Start a subtask with items
  subtask_start(run_id, 1, "Process items in parallel", items_total = 10)
  
  # Simulate parallel processing with 2 workers
  library(parallel)
  cl <- makeCluster(2)
  on.exit(stopCluster(cl), add = TRUE)
  
  # Export necessary objects to workers
  clusterExport(cl, c("run_id"), envir = environment())
  
  # Load tasker in workers and initialize config
  clusterEvalQ(cl, {
    library(tasker)
    # Workers need to connect to the same test database
    # Get the config from the main process
    NULL
  })
  
  # Copy config to workers by exporting the db path
  test_db_path <- get_test_db_path()
  clusterExport(cl, c("test_db_path"), envir = environment())
  
  # Load tasker in workers and configure
  clusterEvalQ(cl, {
    library(tasker)
    
    # Configure workers to use the same test database
    tasker_config(
      driver = "sqlite",
      dbname = test_db_path,
      schema = "",
      reload = TRUE
    )
    NULL
  })
  
  # Define worker function that increments counter
  worker_func <- function(item, run_id) {
    # Simulate some work
    Sys.sleep(runif(1, min = 0.05, max = 0.15))
    
    # Increment the subtask counter with retry for SQLite locks
    max_attempts <- 5
    for (attempt in 1:max_attempts) {
      result <- tryCatch({
        tasker::subtask_increment(run_id, 1, increment = 1, quiet = TRUE)
        TRUE
      }, error = function(e) {
        if (grepl("database is locked", e$message) && attempt < max_attempts) {
          Sys.sleep(runif(1, 0.1, 0.3))  # Random backoff
          FALSE
        } else {
          stop(e)
        }
      })
      if (result) break
    }
    
    return(paste0("Processed item ", item))
  }
  
  # Process items in parallel
  items <- 1:10
  results <- parSapply(cl, items, worker_func, run_id = run_id)
  
  # Verify all items were processed
  expect_equal(length(results), 10)
  
  # Check database for final count
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  subtask_result <- DBI::dbGetQuery(conn,
    "SELECT items_complete FROM subtask_progress WHERE run_id = $1 AND subtask_number = 1",
    params = list(run_id))
  
  expect_equal(nrow(subtask_result), 1)
  expect_equal(subtask_result$items_complete, 10)
  
  cleanup_test_db()
})

test_that("tasker config works in parallel workers", {
  skip_on_cran()
  setup_test_db()
  
  library(parallel)
  cl <- makeCluster(2)
  on.exit(stopCluster(cl), add = TRUE)
  
  test_db_path <- get_test_db_path()
  clusterExport(cl, c("test_db_path"), envir = environment())
  
  # Test that workers can load and configure tasker
  results <- clusterEvalQ(cl, {
    library(tasker)
    tasker_config(
      driver = "sqlite",
      dbname = test_db_path,
      schema = "",
      reload = TRUE
    )
    
    # Try to get a connection
    conn <- get_db_connection()
    success <- DBI::dbIsValid(conn)
    DBI::dbDisconnect(conn)
    success
  })
  
  # Both workers should have successfully connected
  expect_equal(length(results), 2)
  expect_true(all(unlist(results)))
  
  cleanup_test_db()
})
