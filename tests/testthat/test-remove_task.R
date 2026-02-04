# Tests for remove_task() function

test_that("remove_task validates input", {
  skip_on_cran()
  setup_test_db()
  on.exit(cleanup_test_db())
  

  # Missing script_filename
  expect_error(remove_task(), "script_filename.*must be")
  
  # NULL script_filename
  expect_error(remove_task(NULL), "script_filename.*must be")
  
  # Empty script_filename
  expect_error(remove_task(""), "script_filename.*must be")
  
  # Multiple script_filenames
  expect_error(remove_task(c("script1.R", "script2.R")), "script_filename.*must be")
  
  # Numeric script_filename
  expect_error(remove_task(123), "script_filename.*must be")
})

test_that("remove_task handles non-existent task", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Try to remove non-existent task
  result <- remove_task(
    "nonexistent_script.R",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_false(result$task_removed)
  expect_true(is.na(result$task_name))
  expect_equal(result$script_filename, "nonexistent_script.R")
})

test_that("remove_task removes task with no runs", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a task
  register_task(
    stage_order = 1,
    stage = "TEST_STAGE",
    name = "Test Task",
    type = "R",
    script_filename = "test_script.R",
    conn = con
  )
  
  # Verify task exists
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_count_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table} WHERE script_filename = 'test_script.R'",
                   .con = con)
  )$n
  expect_equal(task_count_before, 1)
  
  # Remove the task
  result <- remove_task(
    "test_script.R",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_true(result$task_removed)
  expect_equal(result$task_name, "Test Task")
  expect_equal(result$script_filename, "test_script.R")
  
  # Verify task was removed
  task_count_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table} WHERE script_filename = 'test_script.R'",
                   .con = con)
  )$n
  expect_equal(task_count_after, 0)
})

test_that("remove_task preserves execution history when task_runs exist", {

  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a task
  register_task(
    stage_order = 1,
    stage = "HISTORY_STAGE",
    name = "Task With Runs",
    type = "R",
    script_filename = "task_with_runs.R",
    conn = con
  )
  
  # Start and complete a task run
  run_id <- task_start(stage = "HISTORY_STAGE", task = "Task With Runs", conn = con)
  task_complete(run_id = run_id, conn = con)
  
  # Verify task run exists with task_id set
  task_runs_table <- tasker:::get_table_name("task_runs", con)
  run_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT run_id, task_id FROM {task_runs_table} WHERE run_id = {run_id}",
                   .con = con)
  )
  expect_equal(nrow(run_before), 1)
  expect_false(is.na(run_before$task_id))
  
  # Remove the task (this was failing with FK constraint before the fix)
  result <- remove_task(
    "task_with_runs.R",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_true(result$task_removed)
  expect_equal(result$task_name, "Task With Runs")
  
  # Verify task was removed
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_count <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table} WHERE script_filename = 'task_with_runs.R'",
                   .con = con)
  )$n
  expect_equal(task_count, 0)
  
  # Verify task run still exists (execution history preserved)
  run_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT run_id, task_id FROM {task_runs_table} WHERE run_id = {run_id}",
                   .con = con)
  )
  expect_equal(nrow(run_after), 1)
  # task_id should now be NULL (FK broken but history preserved)
  expect_true(is.na(run_after$task_id))
})

test_that("remove_task respects confirmation in interactive mode", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a test task
  register_task(
    stage_order = 1,
    stage = "CONFIRM_STAGE",
    name = "Confirm Task",
    type = "R",
    script_filename = "confirm_script.R",
    conn = con
  )
  
  # Non-interactive with confirmation string should error
  expect_error(
    remove_task(
      "confirm_script.R",
      conn = con,
      confirmation_string = "REMOVE TASK",
      interactive = FALSE
    ),
    "non-interactive mode"
  )
  
  # Task should still exist
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_count <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table} WHERE script_filename = 'confirm_script.R'",
                   .con = con)
  )$n
  expect_equal(task_count, 1)
})

test_that("remove_task works in quiet mode", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a test task
  register_task(
    stage_order = 1,
    stage = "QUIET_STAGE",
    name = "Quiet Task",
    type = "R",
    script_filename = "quiet_script.R",
    conn = con
  )
  
  # Capture output
  output <- capture.output({
    result <- remove_task(
      "quiet_script.R",
      conn = con,
      confirmation_string = NULL,
      interactive = FALSE,
      quiet = TRUE
    )
  })
  
  # Should have no output in quiet mode
  expect_length(output, 0)
  
  # But should still remove the task
  expect_true(result$task_removed)
  expect_equal(result$task_name, "Quiet Task")
})

test_that("remove_task doesn't affect other tasks", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register multiple tasks
  register_task(stage = "MULTI_STAGE", name = "Keep Task 1", type = "R", 
                script_filename = "keep1.R", stage_order = 1, conn = con)
  register_task(stage = "MULTI_STAGE", name = "Delete Task", type = "R", 
                script_filename = "delete.R", stage_order = 1, task_order = 2, conn = con)
  register_task(stage = "MULTI_STAGE", name = "Keep Task 2", type = "R", 
                script_filename = "keep2.R", stage_order = 1, task_order = 3, conn = con)
  
  # Count tasks before removal
  tasks_table <- tasker:::get_table_name("tasks", con)
  task_count_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table}", .con = con)
  )$n
  expect_equal(task_count_before, 3)
  
  # Remove one task
  result <- remove_task(
    "delete.R",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_true(result$task_removed)
  
  # Verify other tasks still exist
  task_count_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table}", .con = con)
  )$n
  expect_equal(task_count_after, 2)
  
  remaining_tasks <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT script_filename FROM {tasks_table} ORDER BY script_filename", .con = con)
  )$script_filename
  expect_setequal(remaining_tasks, c("keep1.R", "keep2.R"))
})
