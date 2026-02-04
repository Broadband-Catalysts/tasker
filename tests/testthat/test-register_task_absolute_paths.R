# Test that register_task stores absolute paths

test_that("register_task with explicit relative path preserves it", {
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # When user explicitly provides a relative path, it should be stored as-is
  # (This maintains backward compatibility for users who intentionally use relative paths)
  task_id <- register_task(
    stage_order = 1,
    stage = "TEST",
    name = "Explicit Relative Path",
    type = "R",
    stage_order = 1,
    script_path = "inst/scripts",
    script_filename = "test.R",
    log_path = "inst/scripts",
    log_filename = "test.Rout",
    conn = con
  )
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_data <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT * FROM {tasks_table} WHERE task_id = {task_id}", .con = con)
  )
  
  # When explicitly provided, relative paths are preserved
  expect_equal(task_data$script_path, "inst/scripts")
  expect_equal(task_data$log_path, "inst/scripts")
})

test_that("normalizePath is applied during auto-detection", {
  
  # This test verifies that the code contains normalizePath calls
  # Read the register_task.R source
  register_task_source <- readLines(system.file("../../R/register_task.R", package = "tasker", mustWork = FALSE))
  if (length(register_task_source) == 0) {
    # If not installed, try relative path from test
    register_task_source <- readLines("../../R/register_task.R")
  }
  
  # Verify normalizePath is used in path detection
  has_normalize_call <- any(grepl("normalizePath.*full_path", register_task_source))
  expect_true(has_normalize_call, 
              info = "register_task should call normalizePath on detected paths")
  
  # Verify it's called in the commandArgs section
  commandargs_section <- grep("commandArgs|--file=", register_task_source)
  normalize_section <- grep("normalizePath", register_task_source)
  
  expect_true(any(normalize_section > min(commandargs_section) & 
                  normalize_section < max(commandargs_section) + 10),
              info = "normalizePath should be in commandArgs detection section")
})

