# Helper function for exponential backoff with SQLite
retry_with_backoff <- function(expr, max_attempts = 10, initial_wait = 0.01) {
  for (attempt in 1:max_attempts) {
    result <- tryCatch(
      {
        eval(expr)
        return("success")
      },
      error = function(e) {
        if (grepl("database is locked|SQLITE_BUSY", e$message) && attempt < max_attempts) {
          # Exponential backoff with jitter
          wait_time <- initial_wait * (2 ^ (attempt - 1)) + runif(1, 0, 0.01)
          Sys.sleep(min(wait_time, 1))  # Cap at 1 second
          return(NULL)
        } else if (attempt == max_attempts) {
          return(e$message)
        } else {
          return(e$message)
        }
      }
    )
    if (!is.null(result)) {
      return(result)
    }
  }
  return("Max attempts reached")
}


test_that("export_tasker_context exports subtask counter state (single worker)", {
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
  tasker::register_task("TEST", "Context Export Single Worker Test", "R")
  
  # Start task and first subtask
  tasker::task_start("TEST", "Context Export Single Worker Test")
  tasker::subtask_start("First subtask", items_total = 5)
  tasker::subtask_complete()
  
  # Start second subtask (this is subtask #2)
  tasker::subtask_start("Second subtask", items_total = 10)
  
  # Create single-worker cluster to avoid database locking
  cl <- parallel::makeCluster(1)
  on.exit(parallel::stopCluster(cl), add = TRUE)
  
  # Load tasker on worker
  parallel::clusterEvalQ(cl, {
    library(tasker)
    NULL
  })
  
  # Export config to worker
  parallel::clusterExport(cl, "test_db", envir = environment())
  parallel::clusterEvalQ(cl, {
    tasker::tasker_config(
      driver = "sqlite",
      dbname = test_db,
      schema = "",
      reload = TRUE
    )
    NULL
  })
  
  # Export context using export_tasker_context
  tasker::export_tasker_context(cl)
  
  # Verify worker can call subtask_increment without explicit parameters
  results <- parallel::parLapply(cl, 1:10, function(x) {
    # This should work because export_tasker_context exported the subtask counter
    tryCatch({
      tasker::subtask_increment(increment = 1, quiet = TRUE)
      "success"
    }, error = function(e) {
      e$message
    })
  })
  
  # All results should be "success"
  expect_true(all(sapply(results, function(x) x == "success")),
              info = paste("Worker errors:", paste(results[results != "success"], collapse = ", ")))
  
  # Check database for final count
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  subtask_result <- DBI::dbGetQuery(conn,
    "SELECT items_complete FROM subtask_progress WHERE subtask_number = 2")
  
  expect_equal(nrow(subtask_result), 1)
  expect_equal(subtask_result$items_complete, 10,
               info = sprintf("Expected 10 items, got %d", subtask_result$items_complete))
  
  tasker::subtask_complete()
  tasker::task_complete()
})


test_that("export_tasker_context exports subtask counter state (multi-worker with retry)", {
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
  tasker::register_task("TEST", "Context Export Test", "R")
  
  # Start task and first subtask
  tasker::task_start("TEST", "Context Export Test")
  tasker::subtask_start("First subtask", items_total = 5)
  tasker::subtask_complete()
  
  # Start second subtask (this is subtask #2)
  tasker::subtask_start("Second subtask", items_total = 10)
  
  # Create cluster manually (not using tasker_cluster)
  cl <- parallel::makeCluster(2)
  on.exit(parallel::stopCluster(cl), add = TRUE)
  
  # Load tasker on workers
  parallel::clusterEvalQ(cl, {
    library(tasker)
    NULL
  })
  
  # Export config to workers
  parallel::clusterExport(cl, "test_db", envir = environment())
  parallel::clusterEvalQ(cl, {
    tasker::tasker_config(
      driver = "sqlite",
      dbname = test_db,
      schema = "",
      reload = TRUE
    )
    NULL
  })
  
  # Export context using export_tasker_context
  tasker::export_tasker_context(cl)
  
  # Verify workers can call subtask_increment with retry logic for SQLite locking
  results <- parallel::parLapply(cl, 1:10, function(x) {
    # Exponential backoff retry for SQLite locking
    max_attempts <- 10
    for (attempt in 1:max_attempts) {
      result <- tryCatch({
        tasker::subtask_increment(increment = 1, quiet = TRUE)
        return("success")
      }, error = function(e) {
        if (grepl("database is locked|SQLITE_BUSY", e$message) && attempt < max_attempts) {
          wait_time <- 0.01 * (2 ^ (attempt - 1)) + runif(1, 0, 0.01)
          Sys.sleep(min(wait_time, 1))
          return(NULL)
        } else {
          return(e$message)
        }
      })
      if (!is.null(result)) return(result)
    }
    return("max_attempts_reached")
  })
  
  # All results should be "success"
  expect_true(all(sapply(results, function(x) x == "success")),
              info = paste("Worker errors:", paste(results[results != "success"], collapse = ", ")))
  
  # Check database for final count
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  subtask_result <- DBI::dbGetQuery(conn,
    "SELECT items_complete FROM subtask_progress WHERE subtask_number = 2")
  
  expect_equal(nrow(subtask_result), 1)
  expect_equal(subtask_result$items_complete, 10,
               info = sprintf("Expected 10 items, got %d", subtask_result$items_complete))
  
  tasker::subtask_complete()
  tasker::task_complete()
})


test_that("tasker_cluster captures subtask counter at creation time (single worker)", {
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
  tasker::register_task("TEST", "Cluster Timing Test", "R")
  
  # Start task and first subtask
  tasker::task_start("TEST", "Cluster Timing Test")
  tasker::subtask_start("First subtask", items_total = 5)
  
  # Create single-worker cluster with tasker_cluster (captures subtask #1)
  cl <- tasker::tasker_cluster(ncores = 1, load_all = TRUE)
  on.exit(tasker::stop_tasker_cluster(cl), add = TRUE)
  
  # Worker should be able to increment subtask #1
  results <- parallel::parLapply(cl, 1:5, function(x) {
    tryCatch({
      tasker::subtask_increment(increment = 1, quiet = TRUE)
      "success"
    }, error = function(e) {
      e$message
    })
  })
  
  expect_true(all(sapply(results, function(x) x == "success")),
              info = paste("Worker errors:", paste(results[results != "success"], collapse = ", ")))
  
  # Check count
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  subtask_result <- DBI::dbGetQuery(conn,
    "SELECT items_complete FROM subtask_progress WHERE subtask_number = 1")
  expect_equal(subtask_result$items_complete, 5)
  
  tasker::subtask_complete()
  tasker::task_complete()
})


test_that("export_tasker_context after subtask_start updates workers (single worker)", {
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
  tasker::register_task("TEST", "Context Update Test", "R")
  
  # Start task and first subtask
  tasker::task_start("TEST", "Context Update Test")
  tasker::subtask_start("First subtask", items_total = 5)
  
  # Create single-worker cluster with tasker_cluster (captures subtask #1)
  cl <- tasker::tasker_cluster(ncores = 1, load_all = TRUE)
  on.exit(tasker::stop_tasker_cluster(cl), add = TRUE)
  
  # Complete first subtask and start second
  tasker::subtask_complete()
  tasker::subtask_start("Second subtask", items_total = 8)
  
  # Re-export context to update worker with new subtask
  tasker::export_tasker_context(cl)
  
  # Worker should now be able to increment subtask #2
  results <- parallel::parLapply(cl, 1:8, function(x) {
    tryCatch({
      tasker::subtask_increment(increment = 1, quiet = TRUE)
      "success"
    }, error = function(e) {
      e$message
    })
  })
  
  expect_true(all(sapply(results, function(x) x == "success")),
              info = paste("Worker errors:", paste(results[results != "success"], collapse = ", ")))
  
  # Check count for subtask #2
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  subtask_result <- DBI::dbGetQuery(conn,
    "SELECT items_complete FROM subtask_progress WHERE subtask_number = 2")
  expect_equal(subtask_result$items_complete, 8)
  
  tasker::subtask_complete()
  tasker::task_complete()
})


test_that("workers fail gracefully without proper context export", {
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
  tasker::register_task("TEST", "No Context Test", "R")
  
  # Start task and subtask
  tasker::task_start("TEST", "No Context Test")
  tasker::subtask_start("Test subtask", items_total = 3)
  
  # Create cluster but DON'T export context
  cl <- parallel::makeCluster(2)
  on.exit(parallel::stopCluster(cl), add = TRUE)
  
  # Load tasker on workers
  parallel::clusterEvalQ(cl, {
    library(tasker)
    NULL
  })
  
  # Export config but NOT context
  parallel::clusterExport(cl, "test_db", envir = environment())
  parallel::clusterEvalQ(cl, {
    tasker::tasker_config(
      driver = "sqlite",
      dbname = test_db,
      schema = "",
      reload = TRUE
    )
    NULL
  })
  
  # Workers should fail because they don't have context
  results <- parallel::parLapply(cl, 1:3, function(x) {
    tryCatch({
      tasker::subtask_increment(increment = 1, quiet = TRUE)
      "success"
    }, error = function(e) {
      "error"
    })
  })
  
  # All results should be errors
  expect_true(all(sapply(results, function(x) x == "error")),
              info = "Workers should fail without context")
  
  tasker::subtask_complete()
  tasker::task_complete()
})


test_that("multiple subtask transitions with context updates (single worker)", {
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
  tasker::register_task("TEST", "Multi Subtask Test", "R")
  
  # Start task
  tasker::task_start("TEST", "Multi Subtask Test")
  
  # Create single-worker cluster once
  cl <- tasker::tasker_cluster(ncores = 1, load_all = TRUE)
  on.exit(tasker::stop_tasker_cluster(cl), add = TRUE)
  
  # Process three subtasks, updating context each time
  for (i in 1:3) {
    tasker::subtask_start(sprintf("Subtask %d", i), items_total = 4)
    tasker::export_tasker_context(cl)  # Update worker with new subtask
    
    results <- parallel::parLapply(cl, 1:4, function(x) {
      tryCatch({
        tasker::subtask_increment(increment = 1, quiet = TRUE)
        "success"
      }, error = function(e) {
        e$message
      })
    })
    
    expect_true(all(sapply(results, function(x) x == "success")),
                info = sprintf("Subtask %d failed: %s", i, 
                              paste(results[results != "success"], collapse = ", ")))
    
    tasker::subtask_complete()
  }
  
  # Verify all three subtasks have correct counts
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  all_subtasks <- DBI::dbGetQuery(conn,
    "SELECT subtask_number, items_complete FROM subtask_progress ORDER BY subtask_number")
  
  expect_equal(nrow(all_subtasks), 3)
  expect_equal(all_subtasks$items_complete, c(4, 4, 4))
  
  tasker::task_complete()
})


test_that("context export works with tasker_cluster load_all parameter (single worker)", {
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
  tasker::register_task("TEST", "Load All Test", "R")
  
  # Start task and subtask
  tasker::task_start("TEST", "Load All Test")
  tasker::subtask_start("Test with load_all", items_total = 6)
  
  # Test both with and without load_all using single worker
  for (use_load_all in c(TRUE, FALSE)) {
    cl <- tasker::tasker_cluster(ncores = 1, load_all = use_load_all)
    
    results <- parallel::parLapply(cl, 1:3, function(x) {
      tryCatch({
        tasker::subtask_increment(increment = 1, quiet = TRUE)
        "success"
      }, error = function(e) {
        e$message
      })
    })
    
    tasker::stop_tasker_cluster(cl)
    
    expect_true(all(sapply(results, function(x) x == "success")),
                info = sprintf("Failed with load_all=%s: %s", use_load_all,
                              paste(results[results != "success"], collapse = ", ")))
  }
  
  # Should have 6 increments total
  conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  
  subtask_result <- DBI::dbGetQuery(conn,
    "SELECT items_complete FROM subtask_progress WHERE subtask_number = 1")
  expect_equal(subtask_result$items_complete, 6)
  
  tasker::subtask_complete()
  tasker::task_complete()
})
