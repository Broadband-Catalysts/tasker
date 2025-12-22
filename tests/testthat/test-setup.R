test_that("database setup creates schema and tables", {
  skip_on_cran()
  setup_test_db()
  
  # Clean slate
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  # Drop if exists (handle both PostgreSQL and SQLite)
  config <- getOption("tasker.config")
  if (config$database$driver == "postgresql") {
    DBI::dbExecute(conn, "DROP SCHEMA IF EXISTS tasker CASCADE")
  } else {
    # SQLite: drop tables individually
    tables <- c("subtask_progress", "task_runs", "tasks", "stages")
    for (tbl in tables) {
      try(DBI::dbExecute(conn, paste0("DROP TABLE IF EXISTS ", tbl)), silent = TRUE)
    }
    views <- c("active_tasks", "current_task_status")
    for (v in views) {
      try(DBI::dbExecute(conn, paste0("DROP VIEW IF EXISTS ", v)), silent = TRUE)
    }
  }
  
  # Setup database
  setup_tasker_db(conn)
  
  # Verify schema/tables exists
  if (config$database$driver == "postgresql") {
    schema_exists <- DBI::dbGetQuery(conn, 
      "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'tasker'")
    expect_equal(nrow(schema_exists), 1)
  }
  
  # Verify main tables exist
  config <- getOption("tasker.config")
  if (config$database$driver == "postgresql") {
    tables <- DBI::dbGetQuery(conn,
      "SELECT table_name FROM information_schema.tables 
       WHERE table_schema = 'tasker' 
       ORDER BY table_name")
  } else {
    # SQLite
    tables <- DBI::dbGetQuery(conn,
      "SELECT name as table_name FROM sqlite_master WHERE type = 'table' ORDER BY name")
  }
  
  expect_true("stages" %in% tables$table_name)
  expect_true("task_runs" %in% tables$table_name)
  expect_true("subtask_progress" %in% tables$table_name)
  
  # Verify views exist
  if (config$database$driver == "postgresql") {
    views <- DBI::dbGetQuery(conn,
      "SELECT table_name FROM information_schema.views 
       WHERE table_schema = 'tasker'")
  } else {
    views <- DBI::dbGetQuery(conn,
      "SELECT name as table_name FROM sqlite_master WHERE type = 'view'")
  }
  
  expect_true("current_task_status" %in% views$table_name)
})

test_that("database setup with force drops existing schema", {
  skip_on_cran()
  setup_test_db()
  
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  # Setup first time
  setup_tasker_db(conn)
  
  # Add some data using register_task
  tasker::register_task(stage = "TEST", name = "test_task", type = "R", conn = conn)
  
  # Setup with force
  setup_tasker_db(conn, force = TRUE)
  
  # Verify data is gone
  config <- getOption("tasker.config")
  table_name <- if (config$database$driver == "sqlite") {
    "stages"
  } else {
    "tasker.stages"
  }
  count <- DBI::dbGetQuery(conn, 
    glue::glue("SELECT COUNT(*) as n FROM {table_name}"))
  expect_equal(count$n, 0)
})

test_that("SQL functions and triggers are created", {
  skip_on_cran()
  setup_test_db()
  
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  setup_tasker_db(conn)
  
  # Skip these checks for SQLite as it doesn't have information_schema
  config <- getOption("tasker.config")
  if (config$database$driver == "postgresql") {
    # Check for update_timestamp function
    functions <- DBI::dbGetQuery(conn,
      "SELECT routine_name FROM information_schema.routines 
       WHERE routine_schema = 'tasker' AND routine_type = 'FUNCTION'")
    
    expect_true("update_timestamp" %in% functions$routine_name)
    
    # Verify triggers exist
    triggers <- DBI::dbGetQuery(conn,
      "SELECT trigger_name FROM information_schema.triggers 
       WHERE trigger_schema = 'tasker'")
    
    expect_true(nrow(triggers) > 0)
  } else {
    # For SQLite, just check that triggers exist using sqlite_master
    triggers <- DBI::dbGetQuery(conn,
      "SELECT name FROM sqlite_master WHERE type = 'trigger'")
    
    expect_true(nrow(triggers) > 0)
  }
})

test_that("database constraints are enforced", {
  skip_on_cran()
  setup_test_db()
  
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  setup_tasker_db(conn)
  
  # Test invalid status value  
  expect_error(
    DBI::dbExecute(conn,
      "INSERT INTO task_runs 
       (task_id, run_id, hostname, process_id, status)
       VALUES (1, '12345678-1234-1234-1234-123456789abc', 'test', 1234, 'INVALID_STATUS')"),
    "CHECK constraint failed"
  )
})
