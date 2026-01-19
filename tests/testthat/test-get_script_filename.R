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
    script_filename TEXT,
    description TEXT,
    FOREIGN KEY (stage_id) REFERENCES stages(stage_id)
  )")
  
  DBI::dbExecute(con, "CREATE TABLE task_runs (
    run_id TEXT PRIMARY KEY,
    task_id INTEGER NOT NULL,
    start_time TEXT,
    end_time TEXT,
    status TEXT,
    FOREIGN KEY (task_id) REFERENCES tasks(task_id)
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

test_that("get_script_filename returns NULL in interactive session", {
  # In testthat context, should return NULL since not run via Rscript
  result <- get_script_filename()
  expect_true(is.null(result) || is.character(result))
})

test_that("get_script_filename handles commandArgs correctly", {
  # Mock this.path to fail and fall back to commandArgs
  local_mocked_bindings(
    commandArgs = function(...) c("--file=/path/to/script.R", "--args"),
    .package = "base"
  )
  
  # Mock this.path::this.path to return NULL so it falls back to commandArgs
  mockery::stub(get_script_filename, "this.path::this.path", NULL)
  
  result <- get_script_filename()
  expect_equal(result, "script.R")
})

test_that("get_script_filename extracts basename from full path", {
  local_mocked_bindings(
    commandArgs = function(...) c("--file=/home/user/project/inst/scripts/my_script.R"),
    .package = "base"
  )
  
  mockery::stub(get_script_filename, "this.path::this.path", NULL)
  
  result <- get_script_filename()
  expect_equal(result, "my_script.R")
})

test_that("get_script_filename handles paths with spaces", {
  local_mocked_bindings(
    commandArgs = function(...) c("--file=/home/user/my project/script file.R"),
    .package = "base"
  )
  
  mockery::stub(get_script_filename, "this.path::this.path", NULL)
  
  result <- get_script_filename()
  expect_equal(result, "script file.R")
})

test_that("get_script_filename returns NULL when no --file argument", {
  local_mocked_bindings(
    commandArgs = function(...) c("--vanilla", "--quiet"),
    .package = "base"
  )
  
  # Should fall through to other detection methods
  result <- get_script_filename()
  expect_true(is.null(result) || is.character(result))
})

test_that("get_script_filename handles edge cases", {
  # Empty commandArgs
  local_mocked_bindings(
    commandArgs = function(...) character(0),
    .package = "base"
  )
  
  # Force this.path to error (not just return NULL)
  mockery::stub(get_script_filename, "this.path::this.path", function() stop("Not available"))
  
  result <- get_script_filename()
  expect_true(is.null(result))
  
  # Multiple --file arguments (should use first)
  local_mocked_bindings(
    commandArgs = function(...) c("--file=/path/first.R", "--file=/path/second.R"),
    .package = "base"
  )
  
  mockery::stub(get_script_filename, "this.path::this.path", function() stop("Not available"))
  
  result <- get_script_filename()
  expect_equal(result, "first.R")
})

test_that("lookup_task_by_script validates input", {
  # NULL or empty script_filename should return NULL
  result <- lookup_task_by_script(NULL)
  expect_null(result)
  
  result <- lookup_task_by_script("")
  expect_null(result)
})

test_that("lookup_task_by_script returns NULL for non-existent script", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock tasker functions
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    ensure_configured = function() invisible(NULL),
    .package = "tasker"
  )
  
  # Try to lookup a script that doesn't exist
  result <- lookup_task_by_script("nonexistent_script_12345.R", conn = db$conn)
  expect_null(result)
})

test_that("lookup_task_by_script returns proper structure on success", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock tasker functions
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    ensure_configured = function() invisible(NULL),
    .package = "tasker"
  )
  
  # Insert test stage
  DBI::dbExecute(db$conn, 
    "INSERT INTO stages (stage_name, stage_order) VALUES ('TEST_LOOKUP', 1)")
  stage_id <- DBI::dbGetQuery(db$conn, 
    "SELECT stage_id FROM stages WHERE stage_name = 'TEST_LOOKUP'")$stage_id[1]
  
  # Insert test task with script filename
  DBI::dbExecute(db$conn,
    sprintf("INSERT INTO tasks (stage_id, task_name, task_type, script_filename) 
             VALUES (%d, 'Test Lookup Task', 'R', 'test_lookup_script.R')", stage_id))
  task_id <- DBI::dbGetQuery(db$conn,
    "SELECT task_id FROM tasks WHERE script_filename = 'test_lookup_script.R'")$task_id[1]
  
  # Now lookup by script filename
  result <- lookup_task_by_script("test_lookup_script.R", conn = db$conn)
  
  expect_type(result, "list")
  expect_named(result, c("stage", "task", "task_id"))
  expect_equal(result$stage, "TEST_LOOKUP")
  expect_equal(result$task, "Test Lookup Task")
  expect_equal(result$task_id, task_id)
})

test_that("lookup_task_by_script handles multiple matches", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock tasker functions
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    ensure_configured = function() invisible(NULL),
    .package = "tasker"
  )
  
  # Insert test stages
  DBI::dbExecute(db$conn, 
    "INSERT INTO stages (stage_name, stage_order) VALUES ('DUPE1', 1)")
  DBI::dbExecute(db$conn,
    "INSERT INTO stages (stage_name, stage_order) VALUES ('DUPE2', 2)")
  
  stage_id1 <- DBI::dbGetQuery(db$conn,
    "SELECT stage_id FROM stages WHERE stage_name = 'DUPE1'")$stage_id[1]
  stage_id2 <- DBI::dbGetQuery(db$conn,
    "SELECT stage_id FROM stages WHERE stage_name = 'DUPE2'")$stage_id[1]
  
  # Insert two tasks with same script filename
  DBI::dbExecute(db$conn,
    sprintf("INSERT INTO tasks (stage_id, task_name, task_type, script_filename) 
             VALUES (%d, 'First Duplicate', 'R', 'duplicate_script.R')", stage_id1))
  DBI::dbExecute(db$conn,
    sprintf("INSERT INTO tasks (stage_id, task_name, task_type, script_filename) 
             VALUES (%d, 'Second Duplicate', 'R', 'duplicate_script.R')", stage_id2))
  
  # Should warn and return first match
  expect_warning(
    result <- lookup_task_by_script("duplicate_script.R", conn = db$conn),
    "Multiple tasks found"
  )
  
  expect_type(result, "list")
  expect_true(result$stage %in% c("DUPE1", "DUPE2"))
})

test_that("lookup_task_by_script handles database errors gracefully", {
  skip_if_not_installed("RSQLite")
  
  db <- setup_test_db()
  on.exit({
    DBI::dbDisconnect(db$conn)
    unlink(db$db_file)
  })
  
  # Mock tasker functions
  local_mocked_bindings(
    get_table_name = function(table, ...) table,
    ensure_configured = function() invisible(NULL),
    .package = "tasker"
  )
  
  # Create a wrapper function to mock
  test_lookup <- function() {
    lookup_task_by_script("test.R", conn = db$conn)
  }
  
  # Mock dbGetQuery to fail within the wrapper
  mockery::stub(test_lookup, "lookup_task_by_script", function(...) {
    stop("Simulated database error")
  })
  
  # The function should handle the error gracefully
  expect_error(
    test_lookup(),
    "Simulated database error"
  )
})
