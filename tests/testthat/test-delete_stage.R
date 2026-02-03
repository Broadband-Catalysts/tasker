# Tests for delete_stage() function

test_that("delete_stage validates input", {
  skip_on_cran()
  setup_test_db()
  on.exit(cleanup_test_db())
  
  # Missing stage_name
  expect_error(delete_stage(), "stage_name.*must be")
  
  # NULL stage_name
  expect_error(delete_stage(NULL), "stage_name.*must be")
  
  # Empty stage_name
  expect_error(delete_stage(""), "stage_name.*must be")
  
  # Multiple stage names
  expect_error(delete_stage(c("STAGE1", "STAGE2")), "stage_name.*must be")
  
  # Numeric stage_name
  expect_error(delete_stage(123), "stage_name.*must be")
})

test_that("delete_stage handles non-existent stage", {
  skip_on_cran()
  setup_test_db()
  on.exit(cleanup_test_db())
  
  # Try to delete non-existent stage
  result <- delete_stage(
    "NONEXISTENT_STAGE",
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_false(result$stage_deleted)
  expect_equal(result$tasks_deleted, 0)
  expect_equal(result$stage_name, "NONEXISTENT_STAGE")
})

test_that("delete_stage deletes stage with no tasks", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Create a stage with no tasks
  stages_table <- tasker:::get_table_name("stages", con)
  DBI::dbExecute(
    con,
    glue::glue_sql("INSERT INTO {stages_table} (stage_name, stage_order) VALUES ('EMPTY_STAGE', 999)",
                   .con = con)
  )
  
  # Verify stage exists
  stage_count_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table} WHERE stage_name = 'EMPTY_STAGE'",
                   .con = con)
  )$n
  expect_equal(stage_count_before, 1)
  
  # Delete the stage
  result <- delete_stage(
    "EMPTY_STAGE",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_true(result$stage_deleted)
  expect_equal(result$tasks_deleted, 0)
  expect_equal(result$stage_name, "EMPTY_STAGE")
  
  # Verify stage was deleted
  stage_count_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table} WHERE stage_name = 'EMPTY_STAGE'",
                   .con = con)
  )$n
  expect_equal(stage_count_after, 0)
})

test_that("delete_stage deletes stage with tasks", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a stage with tasks
  register_task(stage = "TEST_STAGE", name = "Task 1", type = "R", conn = con)
  register_task(stage = "TEST_STAGE", name = "Task 2", type = "R", conn = con)
  register_task(stage = "TEST_STAGE", name = "Task 3", type = "R", conn = con)
  
  # Verify stage and tasks exist
  stages_table <- tasker:::get_table_name("stages", con)
  tasks_table <- tasker:::get_table_name("tasks", con)
  
  stage_count_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table} WHERE stage_name = 'TEST_STAGE'",
                   .con = con)
  )$n
  expect_equal(stage_count_before, 1)
  
  task_count_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table} t
                    JOIN {stages_table} s ON t.stage_id = s.stage_id
                    WHERE s.stage_name = 'TEST_STAGE'",
                   .con = con)
  )$n
  expect_equal(task_count_before, 3)
  
  # Delete the stage
  result <- delete_stage(
    "TEST_STAGE",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_true(result$stage_deleted)
  expect_equal(result$tasks_deleted, 3)
  expect_equal(result$stage_name, "TEST_STAGE")
  
  # Verify stage was deleted
  stage_count_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table} WHERE stage_name = 'TEST_STAGE'",
                   .con = con)
  )$n
  expect_equal(stage_count_after, 0)
  
  # Verify tasks were deleted
  task_count_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {tasks_table} t
                    LEFT JOIN {stages_table} s ON t.stage_id = s.stage_id
                    WHERE s.stage_name = 'TEST_STAGE' OR s.stage_name IS NULL",
                   .con = con)
  )$n
  expect_equal(task_count_after, 0)
})

test_that("delete_stage preserves execution history", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a stage with tasks
  register_task(stage = "HISTORY_STAGE", name = "Task A", type = "R", conn = con)
  
  # Start and complete a task run
  run_id <- task_start(stage = "HISTORY_STAGE", task = "Task A", conn = con)
  task_complete(run_id = run_id, conn = con)
  
  # Verify task run exists
  task_runs_table <- tasker:::get_table_name("task_runs", con)
  run_count_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {task_runs_table} WHERE run_id = {run_id}",
                   .con = con)
  )$n
  expect_equal(run_count_before, 1)
  
  # Delete the stage
  result <- delete_stage(
    "HISTORY_STAGE",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_true(result$stage_deleted)
  expect_equal(result$tasks_deleted, 1)
  
  # Verify task run still exists (execution history preserved)
  run_count_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {task_runs_table} WHERE run_id = {run_id}",
                   .con = con)
  )$n
  expect_equal(run_count_after, 1)
})

test_that("delete_stage respects confirmation in interactive mode", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a test stage
  register_task(stage = "CONFIRM_STAGE", name = "Task", type = "R", conn = con)
  
  # Non-interactive with confirmation string should error
  expect_error(
    delete_stage(
      "CONFIRM_STAGE",
      conn = con,
      confirmation_string = "DELETE STAGE",
      interactive = FALSE
    ),
    "Non-interactive mode requires confirmation_string = NULL"
  )
  
  # Stage should still exist
  stages_table <- tasker:::get_table_name("stages", con)
  stage_count <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table} WHERE stage_name = 'CONFIRM_STAGE'",
                   .con = con)
  )$n
  expect_equal(stage_count, 1)
})

test_that("delete_stage works in quiet mode", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a test stage
  register_task(stage = "QUIET_STAGE", name = "Task", type = "R", conn = con)
  
  # Capture output
  output <- capture.output({
    result <- delete_stage(
      "QUIET_STAGE",
      conn = con,
      confirmation_string = NULL,
      interactive = FALSE,
      quiet = TRUE
    )
  })
  
  # Should have no output in quiet mode
  expect_length(output, 0)
  
  # But should still delete the stage
  expect_true(result$stage_deleted)
  expect_equal(result$tasks_deleted, 1)
})

test_that("delete_stage doesn't affect other stages", {
  skip_on_cran()
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register multiple stages
  register_task(stage = "KEEP_STAGE_1", name = "Task 1", type = "R", conn = con)
  register_task(stage = "DELETE_STAGE", name = "Task 2", type = "R", conn = con)
  register_task(stage = "KEEP_STAGE_2", name = "Task 3", type = "R", conn = con)
  
  # Count stages before deletion
  stages_table <- tasker:::get_table_name("stages", con)
  stage_count_before <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table}", .con = con)
  )$n
  expect_equal(stage_count_before, 3)
  
  # Delete one stage
  result <- delete_stage(
    "DELETE_STAGE",
    conn = con,
    confirmation_string = NULL,
    interactive = FALSE,
    quiet = TRUE
  )
  
  expect_true(result$stage_deleted)
  
  # Verify other stages still exist
  stage_count_after <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT COUNT(*) as n FROM {stages_table}", .con = con)
  )$n
  expect_equal(stage_count_after, 2)
  
  remaining_stages <- DBI::dbGetQuery(
    con,
    glue::glue_sql("SELECT stage_name FROM {stages_table} ORDER BY stage_name", .con = con)
  )$stage_name
  expect_setequal(remaining_stages, c("KEEP_STAGE_1", "KEEP_STAGE_2"))
})
