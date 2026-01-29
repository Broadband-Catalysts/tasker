# Tests for register_task() automatic default detection

test_that("register_task applies no defaults when all parameters provided", {
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Suppress warnings (we're testing explicit specification)
  task_id <- suppressWarnings(
    register_task(
      stage = "TEST",
      name = "Explicit Task",
      type = "R",
      stage_order = 1,
      script_path = "/explicit/path",
      script_filename = "explicit_script.R",
      log_path = "/explicit/logs",
      log_filename = "explicit.Rout",
      conn = con
    )
  )
  
  # Verify task was created
  expect_true(is.integer(task_id))
  expect_gt(task_id, 0)
  
  # Verify values were stored correctly
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  expect_equal(task_data$script_path, "/explicit/path")
  expect_equal(task_data$script_filename, "explicit_script.R")
  expect_equal(task_data$log_path, "/explicit/logs")
  expect_equal(task_data$log_filename, "explicit.Rout")
})

test_that("register_task extracts script_filename from script_path when only path provided", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  task_id <- register_task(
    stage = "TEST",
    name = "Extract Filename Task",
    type = "R",
    stage_order = 1,
    script_path = "/path/to/my_script.R",
    log_path = "/path/to/logs",
    log_filename = "my_script.Rout",
    conn = con
  )
  
  # Verify script_filename was extracted
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  expect_equal(task_data$script_filename, "my_script.R")
})

test_that("register_task generates log_filename from script_filename for R scripts", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Should warn about deriving log_filename
  expect_warning(
    task_id <- register_task(
      stage = "TEST",
      name = "R Script Task",
      type = "R",
      stage_order = 1,
      script_filename = "my_script.R",
      conn = con
    ),
    "log_filename.*not specified.*using derived value.*my_script.Rout"
  )
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  expect_equal(task_data$log_filename, "my_script.Rout")
})

test_that("register_task generates log_filename from script_filename for shell scripts", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  expect_warning(
    task_id <- register_task(
      stage = "TEST",
      name = "Shell Script Task",
      type = "sh",
      stage_order = 1,
      script_filename = "install.sh",
      conn = con
    ),
    "log_filename.*not specified.*using derived value.*install.log"
  )
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  expect_equal(task_data$log_filename, "install.log")
})

test_that("register_task generates log_filename from script_filename for Python scripts", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  expect_warning(
    task_id <- register_task(
      stage = "TEST",
      name = "Python Script Task",
      type = "python",
      stage_order = 1,
      script_filename = "process.py",
      conn = con
    ),
    "log_filename.*not specified.*using derived value.*process.log"
  )
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  expect_equal(task_data$log_filename, "process.log")
})

test_that("register_task uses .log for unknown file extensions", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  expect_warning(
    task_id <- register_task(
      stage = "TEST",
      name = "Unknown Extension Task",
      type = "other",
      stage_order = 1,
      script_filename = "custom.xyz",
      conn = con
    ),
    "log_filename.*not specified.*using derived value.*custom.xyz.log"
  )
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  expect_equal(task_data$log_filename, "custom.xyz.log")
})

test_that("register_task sets log_path same as script_path when only script_path provided", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Provide script_path but not log_path
  expect_warning(
    task_id <- register_task(
      stage = "TEST",
      name = "Log Path Default Task",
      type = "R",
      stage_order = 1,
      script_path = "/home/scripts",
      script_filename = "task.R",
      log_filename = "task.Rout",
      conn = con
    ),
    "log_path.*not specified.*using same as script_path"
  )
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  expect_equal(task_data$log_path, "/home/scripts")
})

test_that("register_task handles case-insensitive file extensions", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Test uppercase .R
  expect_warning(
    task_id1 <- register_task(
      stage = "TEST",
      name = "Uppercase R",
      type = "R",
      stage_order = 1,
      script_filename = "script.R",
      conn = con
    )
  )
  
  # Test lowercase .r
  expect_warning(
    task_id2 <- register_task(
      stage = "TEST",
      name = "Lowercase r",
      type = "R",
      stage_order = 1,
      script_filename = "script2.r",
      conn = con
    )
  )
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  
  task1_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id1}", .con = con)
  )
  expect_equal(task1_data$log_filename, "script.Rout")
  
  task2_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id2}", .con = con)
  )
  expect_equal(task2_data$log_filename, "script2.Rout")
})

test_that("register_task updates existing tasks preserving defaults", {

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Create task with defaults
  expect_warning(
    task_id1 <- register_task(
      stage = "TEST",
      name = "Update Test",
      type = "R",
      stage_order = 1,
      script_filename = "original.R",
      conn = con
    )
  )
  
  # Update without providing optional fields (should preserve)
  task_id2 <- suppressWarnings(
    register_task(
      stage = "TEST",
      name = "Update Test",  # Same name = update
      type = "R",
      stage_order = 2,  # Different order
      conn = con
    )
  )
  
  # Should return same task_id
  expect_equal(task_id1, task_id2)
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id1}", .con = con)
  )
  
  # Original values should be preserved
  expect_equal(task_data$script_filename, "original.R")
  expect_equal(task_data$log_filename, "original.Rout")
})
