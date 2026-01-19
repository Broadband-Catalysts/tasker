# Helper to create temporary SQLite database for testing
setup_test_db <- function() {
  temp_db <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  
  # Create tasker schema tables
  DBI::dbExecute(con, "CREATE TABLE stages (
    stage_id INTEGER PRIMARY KEY AUTOINCREMENT,
    stage_name TEXT NOT NULL UNIQUE,
    stage_order INTEGER
  )")
  
  DBI::dbExecute(con, "CREATE TABLE tasks (
    task_id INTEGER PRIMARY KEY AUTOINCREMENT,
    stage_id INTEGER NOT NULL,
    task_name TEXT NOT NULL,
    task_type TEXT,
    task_order INTEGER,
    script_filename TEXT,
    description TEXT,
    FOREIGN KEY (stage_id) REFERENCES stages(stage_id)
  )")
  
  DBI::dbExecute(con, "CREATE TABLE task_runs (
    run_id TEXT PRIMARY KEY DEFAULT (
        lower(
            substr(hex(randomblob(16)), 1, 8) || '-' ||
            substr(hex(randomblob(16)), 9, 4) || '-' ||
            substr(hex(randomblob(16)), 13, 4) || '-' ||
            substr(hex(randomblob(16)), 17, 4) || '-' ||
            substr(hex(randomblob(16)), 21, 12)
        )
    ),
    task_id INTEGER NOT NULL REFERENCES tasks(task_id),
    hostname TEXT NOT NULL,
    process_id INTEGER NOT NULL,
    parent_pid INTEGER,
    start_time TEXT,
    end_time TEXT,
    last_update TEXT NOT NULL DEFAULT (datetime('now')),
    status TEXT NOT NULL,
    total_subtasks INTEGER,
    current_subtask INTEGER,
    overall_percent_complete REAL,
    overall_progress_message TEXT,
    memory_mb INTEGER,
    cpu_percent REAL,
    error_message TEXT,
    error_detail TEXT,
    version TEXT,
    git_commit TEXT,
    user_name TEXT,
    environment TEXT,
    CHECK (status IN ('NOT_STARTED', 'STARTED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED', 'CANCELLED'))
  )")
  
  # Configure tasker to use this SQLite database
  config <- list(
    database = list(
      driver = "sqlite",
      dbname = temp_db
    ),
    schema = list(
      use_schema = FALSE,
      schema_name = NULL
    )
  )
  options(tasker.config = config)
  
  return(list(conn = con, db_file = temp_db))
}

test_that("task_start auto-detects script and looks up task", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock tasker functions
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    get_script_filename = function() "auto_detect_test.R",
    .package = "tasker"
  )
  
  # Insert test stage and task
  DBI::dbExecute(db$conn,
    "INSERT INTO stages (stage_name, stage_order) VALUES ('AUTODETECT_TEST', 1)")
  stage_id <- DBI::dbGetQuery(db$conn,
    "SELECT stage_id FROM stages WHERE stage_name = 'AUTODETECT_TEST'")$stage_id[1]
  
  DBI::dbExecute(db$conn,
    sprintf("INSERT INTO tasks (stage_id, task_name, task_type, script_filename) 
             VALUES (%d, 'Auto Detect Test', 'R', 'auto_detect_test.R')", stage_id))
  
  # Call task_start without parameters - should auto-detect
  run_id <- task_start(conn = db$conn, quiet = TRUE, .active = FALSE)
  
  expect_true(is.character(run_id))
  expect_true(nchar(run_id) > 0)
  
  # Verify the task was started correctly
  result <- DBI::dbGetQuery(db$conn,
    sprintf("SELECT t.task_name, s.stage_name 
             FROM task_runs tr
             JOIN tasks t ON tr.task_id = t.task_id
             JOIN stages s ON t.stage_id = s.stage_id
             WHERE tr.run_id = '%s'", run_id))
  
  expect_equal(result$stage_name[1], "AUTODETECT_TEST")
  expect_equal(result$task_name[1], "Auto Detect Test")
})

test_that("task_start fails gracefully when script not registered", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock tasker functions
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    get_script_filename = function() "unregistered_script.R",
    .package = "tasker"
  )
  
  expect_error(
    task_start(conn = db$conn, quiet = TRUE),
    "Could not auto-detect stage/task"
  )
})

test_that("task_start fails when cannot detect script and no parameters", {
  # Mock get_script_filename to return NULL (interactive session)
  local_mocked_bindings(
    get_script_filename = function() NULL,
    .package = "tasker"
  )
  
  expect_error(
    task_start(quiet = TRUE),
    "Could not auto-detect script filename"
  )
})

test_that("task_start still works with explicit parameters", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock get_table_name to return plain table names
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    .package = "tasker"
  )
  
  # Insert test stage and task
  DBI::dbExecute(db$conn,
    "INSERT INTO stages (stage_name, stage_order) VALUES ('EXPLICIT_TEST', 1)")
  stage_id <- DBI::dbGetQuery(db$conn,
    "SELECT stage_id FROM stages WHERE stage_name = 'EXPLICIT_TEST'")$stage_id[1]
  
  DBI::dbExecute(db$conn,
    sprintf("INSERT INTO tasks (stage_id, task_name, task_type) 
             VALUES (%d, 'Explicit Param Test', 'R')", stage_id))
  
  # Call with explicit parameters (old way)
  run_id <- task_start(
    stage = "EXPLICIT_TEST",
    task = "Explicit Param Test",
    conn = db$conn,
    quiet = TRUE,
    .active = FALSE
  )
  
  expect_true(is.character(run_id))
  
  # Verify
  result <- DBI::dbGetQuery(db$conn,
    sprintf("SELECT t.task_name, s.stage_name 
             FROM task_runs tr
             JOIN tasks t ON tr.task_id = t.task_id
             JOIN stages s ON t.stage_id = s.stage_id
             WHERE tr.run_id = '%s'", run_id))
  
  expect_equal(result$stage_name[1], "EXPLICIT_TEST")
  expect_equal(result$task_name[1], "Explicit Param Test")
})

test_that("task_start allows partial auto-detection", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock tasker functions
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    get_script_filename = function() "partial_test.R",
    .package = "tasker"
  )
  
  # Insert test stage and task
  DBI::dbExecute(db$conn,
    "INSERT INTO stages (stage_name, stage_order) VALUES ('PARTIAL_TEST', 1)")
  stage_id <- DBI::dbGetQuery(db$conn,
    "SELECT stage_id FROM stages WHERE stage_name = 'PARTIAL_TEST'")$stage_id[1]
  
  DBI::dbExecute(db$conn,
    sprintf("INSERT INTO tasks (stage_id, task_name, task_type, script_filename) 
             VALUES (%d, 'Partial Test', 'R', 'partial_test.R')", stage_id))
  
  # Provide explicit stage but let task auto-detect
  run_id <- task_start(
    stage = "PARTIAL_TEST",
    conn = db$conn,
    quiet = TRUE,
    .active = FALSE
  )
  
  expect_true(is.character(run_id))
  
  result <- DBI::dbGetQuery(db$conn,
    sprintf("SELECT t.task_name 
             FROM task_runs tr
             JOIN tasks t ON tr.task_id = t.task_id
             WHERE tr.run_id = '%s'", run_id))
  
  expect_equal(result$task_name[1], "Partial Test")
})

test_that("task_start validates input even after auto-detection", {
  skip_on_cran()
  
  # Mock to return valid script but with invalid stage/task in DB
  local_mocked_bindings(
    get_script_filename = function() "test.R",
    lookup_task_by_script = function(...) list(stage = "", task = "Valid"),
    .package = "tasker"
  )
  
  expect_error(
    task_start(quiet = TRUE),
    "stage.*must be a non-empty"
  )
  
  # Mock to return valid stage but invalid task
  local_mocked_bindings(
    lookup_task_by_script = function(...) list(stage = "VALID", task = ""),
    .package = "tasker"
  )
  
  expect_error(
    task_start(quiet = TRUE),
    "task.*must be a non-empty"
  )
})
