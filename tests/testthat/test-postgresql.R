# PostgreSQL-specific tests
# These tests use the real PostgreSQL database with temporary schemas
# Requires BBC_DB_* environment variables to be set (from .Renviron)

test_that("PostgreSQL schema columns exist and have correct types", {
  skip_on_cran()
  skip_if(!postgresql_available(), "PostgreSQL credentials not available")
  
  test_info <- setup_postgresql_test()
  on.exit(cleanup_postgresql_test(test_info))
  
  con <- test_info$con
  schema <- test_info$schema
  
  # Test tasks table columns
  tasks_cols <- DBI::dbGetQuery(con, sprintf("
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_schema = '%s' 
    AND table_name = 'tasks'
    ORDER BY column_name
  ", schema))
  
  expect_true("updated_at" %in% tasks_cols$column_name)
  expect_true("created_at" %in% tasks_cols$column_name)
  expect_true("stage_id" %in% tasks_cols$column_name)
  expect_true("task_name" %in% tasks_cols$column_name)
  
  # Verify updated_at is timestamp with time zone
  updated_at_type <- tasks_cols$data_type[tasks_cols$column_name == "updated_at"]
  expect_equal(updated_at_type, "timestamp with time zone")
  
  # Test task_runs table columns
  runs_cols <- DBI::dbGetQuery(con, sprintf("
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_schema = '%s' 
    AND table_name = 'task_runs'
    ORDER BY column_name
  ", schema))
  
  expect_true("start_time" %in% runs_cols$column_name)
  expect_true("end_time" %in% runs_cols$column_name)
  expect_true("last_update" %in% runs_cols$column_name)
  
  # Verify timestamp types
  end_time_type <- runs_cols$data_type[runs_cols$column_name == "end_time"]
  expect_equal(end_time_type, "timestamp with time zone")
  
  last_update_type <- runs_cols$data_type[runs_cols$column_name == "last_update"]
  expect_equal(last_update_type, "timestamp with time zone")
})

test_that("PostgreSQL triggers automatically update timestamps", {
  skip_on_cran()
  skip_if(!postgresql_available(), "PostgreSQL credentials not available")
  
  test_info <- setup_postgresql_test()
  on.exit(cleanup_postgresql_test(test_info))
  
  con <- test_info$con
  
  # Register a task
  register_task(stage = "TEST", name = "trigger_test", type = "R")
  
  # Get initial updated_at timestamp
  initial <- DBI::dbGetQuery(con, "
    SELECT t.updated_at 
    FROM tasks t
    JOIN stages s ON t.stage_id = s.stage_id
    WHERE s.stage_name = 'TEST' AND t.task_name = 'trigger_test'
  ")
  
  expect_equal(nrow(initial), 1)
  expect_false(is.na(initial$updated_at))
  
  # Wait a moment to ensure timestamp difference
  Sys.sleep(1)
  
  # Update the task (e.g., change description)
  DBI::dbExecute(con, "
    UPDATE tasks t
    SET description = 'Updated description' 
    FROM stages s
    WHERE t.stage_id = s.stage_id
    AND s.stage_name = 'TEST' AND t.task_name = 'trigger_test'
  ")
  
  # Get updated timestamp
  updated <- DBI::dbGetQuery(con, "
    SELECT t.updated_at 
    FROM tasks t
    JOIN stages s ON t.stage_id = s.stage_id
    WHERE s.stage_name = 'TEST' AND t.task_name = 'trigger_test'
  ")
  
  # Trigger should have updated the timestamp
  expect_true(updated$updated_at > initial$updated_at)
})

test_that("PostgreSQL task_runs last_update trigger works", {
  skip_on_cran()
  skip_if(!postgresql_available(), "PostgreSQL credentials not available")
  
  test_info <- setup_postgresql_test()
  on.exit(cleanup_postgresql_test(test_info))
  
  con <- test_info$con
  
  # Register and start task
  register_task(stage = "TEST", name = "last_update_test", type = "R")
  run_id <- task_start(stage = "TEST", task = "last_update_test", total_subtasks = 1)
  
  # Get initial last_update
  initial <- DBI::dbGetQuery(con, sprintf("
    SELECT last_update 
    FROM task_runs 
    WHERE run_id = '%s'
  ", run_id))
  
  expect_equal(nrow(initial), 1)
  expect_false(is.na(initial$last_update))
  
  # Wait to ensure timestamp difference
  Sys.sleep(1)
  
  # Update status
  subtask_start("Test subtask", items_total = 10, run_id = run_id, subtask_number = 1)
  
  # Get updated last_update
  updated <- DBI::dbGetQuery(con, sprintf("
    SELECT last_update 
    FROM task_runs 
    WHERE run_id = '%s'
  ", run_id))
  
  # Trigger should have updated last_update
  expect_true(updated$last_update > initial$last_update)
})

test_that("PostgreSQL task_runs_with_latest_metrics view doesn't have duplicate column names", {
  skip_on_cran()
  skip_if(!postgresql_available(), "PostgreSQL credentials not available")
  
  test_info <- setup_postgresql_test()
  on.exit(cleanup_postgresql_test(test_info))
  
  con <- test_info$con
  schema <- test_info$schema
  
  # Check that task_runs_with_latest_metrics view exists
  view_exists <- DBI::dbGetQuery(con, sprintf("
    SELECT COUNT(*) as count
    FROM information_schema.views
    WHERE table_schema = '%s'
    AND table_name = 'task_runs_with_latest_metrics'
  ", schema))
  
  expect_equal(view_exists$count, 1)
  
  # Try to query the view (this would fail with duplicate column names)
  result <- DBI::dbGetQuery(con, "SELECT * FROM task_runs_with_latest_metrics LIMIT 0")
  
  # Get column names
  cols <- names(result)
  
  # Check for proper aliasing of metrics columns
  metrics_cols <- grep("^metrics_", cols, value = TRUE)
  expect_true(length(metrics_cols) > 0)
  
  # Should not have duplicate column names
  expect_equal(length(cols), length(unique(cols)))
})

test_that("PostgreSQL COUNT() queries work correctly", {
  skip_on_cran()
  skip_if(!postgresql_available(), "PostgreSQL credentials not available")
  
  test_info <- setup_postgresql_test()
  on.exit(cleanup_postgresql_test(test_info))
  
  con <- test_info$con
  
  # Register multiple tasks
  for (i in 1:5) {
    register_task(stage = "TEST", name = paste0("count_test_", i), type = "R")
  }
  
  # Count tasks with explicit INTEGER cast and JOIN to stages table
  count_result <- DBI::dbGetQuery(con, "
    SELECT COUNT(*)::INTEGER as n 
    FROM tasks t
    LEFT JOIN stages s ON t.stage_id = s.stage_id
    WHERE s.stage_name = 'TEST'
  ")
  
  # Verify result is proper integer
  expect_equal(count_result$n, 5)
  expect_true(is.integer(count_result$n) || is.numeric(count_result$n))
  
  # Should not be in scientific notation
  expect_false(grepl("e", as.character(count_result$n), ignore.case = TRUE))
})

test_that("PostgreSQL parallel subtask_increment is atomic", {
  skip_on_cran()
  skip_if(!postgresql_available(), "PostgreSQL credentials not available")
  
  test_info <- setup_postgresql_test()
  on.exit(cleanup_postgresql_test(test_info))
  
  # Register and start task
  register_task(stage = "TEST", name = "atomic_test", type = "R")
  run_id <- task_start(stage = "TEST", task = "atomic_test", total_subtasks = 1)
  subtask_start("Atomic test", items_total = 100, run_id = run_id, subtask_number = 1)
  
  # Create parallel cluster with fewer workers to avoid spawn limits
  library(parallel)
  cl <- makeCluster(2)
  on.exit(stopCluster(cl), add = TRUE)
  
  # Export configuration to workers
  clusterExport(cl, c("run_id"), envir = environment())
  
  # Set schema environment variable BEFORE configuring workers
  test_schema <- test_info$schema
  clusterExport(cl, c("test_schema"), envir = environment())
  
  # Configure workers with PostgreSQL connection
  clusterEvalQ(cl, {
    library(tasker)
    tasker_config(
      driver = "postgresql",
      host = Sys.getenv("BBC_DB_HOST"),
      port = as.integer(Sys.getenv("BBC_DB_PORT", "5432")),
      dbname = Sys.getenv("BBC_DB_DATABASE", "geodb"),
      user = Sys.getenv("BBC_DB_RW_USER"),
      password = Sys.getenv("BBC_DB_RW_PASSWORD"),
      schema = test_schema,
      reload = TRUE
    )
    NULL
  })
  
  # Have workers increment counter in parallel (25 increments each = 100 total)
  results <- parLapply(cl, 1:100, function(i) {
    subtask_increment(increment = 1, run_id = run_id, subtask_number = 1, quiet = TRUE)
    "success"
  })
  
  # Verify all increments succeeded
  expect_true(all(results == "success"))
  
  # Check final count
  con <- test_info$con
  final_count <- DBI::dbGetQuery(con, sprintf("
    SELECT items_complete 
    FROM subtask_progress 
    WHERE run_id = '%s' AND subtask_number = 1
  ", run_id))
  
  # Should be exactly 100 (proving atomicity)
  expect_equal(final_count$items_complete, 100)
})

test_that("PostgreSQL handles concurrent task operations", {
  skip_on_cran()
  skip_if(!postgresql_available(), "PostgreSQL credentials not available")
  
  test_info <- setup_postgresql_test()
  on.exit(cleanup_postgresql_test(test_info))
  
  # Register multiple tasks
  for (i in 1:3) {
    register_task(stage = "CONCURRENT", name = paste0("task", i), type = "R")
  }
  
  # Start all tasks concurrently with fewer workers to avoid spawn limits
  library(parallel)
  cl <- makeCluster(2)
  on.exit(stopCluster(cl), add = TRUE)
  
  # Configure workers - export test schema first
  test_schema <- test_info$schema
  clusterExport(cl, c("test_schema"), envir = environment())
  clusterEvalQ(cl, {
    library(tasker)
    tasker_config(
      driver = "postgresql",
      host = Sys.getenv("BBC_DB_HOST"),
      port = as.integer(Sys.getenv("BBC_DB_PORT", "5432")),
      dbname = Sys.getenv("BBC_DB_DATABASE", "geodb"),
      user = Sys.getenv("BBC_DB_RW_USER"),
      password = Sys.getenv("BBC_DB_RW_PASSWORD"),
      schema = test_schema,
      reload = TRUE
    )
    NULL
  })
  
  Sys.setenv(TASKER_TEST_SCHEMA = test_info$schema)
  
  # Start tasks in parallel
  run_ids <- parLapply(cl, 1:3, function(i) {
    task_start(stage = "CONCURRENT", task = paste0("task", i), total_subtasks = 0)
  })
  
  # Verify all tasks started successfully (run_ids are UUIDs, not numeric)
  expect_equal(length(run_ids), 3)
  expect_true(all(sapply(run_ids, is.character)))
  
  # Verify all run_ids are unique
  expect_equal(length(unique(unlist(run_ids))), 3)
  
  # Check database has all 3 runs
  con <- test_info$con
  db_runs <- DBI::dbGetQuery(con, "
    SELECT tr.run_id, s.stage_name, t.task_name 
    FROM task_runs tr
    JOIN tasks t ON tr.task_id = t.task_id
    JOIN stages s ON t.stage_id = s.stage_id
    WHERE s.stage_name = 'CONCURRENT'
    ORDER BY tr.run_id
  ")
  
  expect_equal(nrow(db_runs), 3)
  expect_true(all(db_runs$stage_name == "CONCURRENT"))
})
