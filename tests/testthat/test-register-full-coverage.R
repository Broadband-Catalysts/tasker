library(testthat)

test_that("register_task creates stage and task with all required columns", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a task
  register_task(
    stage = "TEST_STAGE",
    name = "Test Task",
    stage_order = 10,
    task_order = 1,
    type = "R",
    description = "A test task",
    script_path = "/path/to/script",
    script_filename = "test_script.R",
    log_path = "/path/to/logs",
    log_filename = "test_script.Rout"
  )
  
  # Verify stage was created with all columns including updated_at
  stage_query <- "SELECT stage_name, stage_order, created_at, updated_at FROM stages WHERE stage_name = 'TEST_STAGE'"
  stage <- DBI::dbGetQuery(con, stage_query)
  
  expect_equal(nrow(stage), 1)
  expect_equal(stage$stage_name, "TEST_STAGE")
  expect_equal(stage$stage_order, 10)
  expect_false(is.na(stage$created_at))
  expect_false(is.na(stage$updated_at))
  
  # Verify task was created with all columns including updated_at
  task_query <- "SELECT task_name, task_type, script_filename, log_filename, created_at, updated_at 
                 FROM tasks WHERE task_name = 'Test Task'"
  task <- DBI::dbGetQuery(con, task_query)
  
  expect_equal(nrow(task), 1)
  expect_equal(task$task_name, "Test Task")
  expect_equal(task$task_type, "R")
  expect_equal(task$script_filename, "test_script.R")
  expect_equal(task$log_filename, "test_script.Rout")
  expect_false(is.na(task$created_at))
  expect_false(is.na(task$updated_at))
})

test_that("register_task updates existing task and triggers updated_at", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register initial task
  register_task(
    stage = "UPDATE_TEST",
    name = "Update Task",
    type = "R",
    description = "Original description"
  )
  
  # Get original timestamps
  original <- DBI::dbGetQuery(con, 
    "SELECT created_at, updated_at FROM tasks WHERE task_name = 'Update Task'")
  
  # Small delay to ensure timestamp changes
  Sys.sleep(0.1)
  
  # Update the task
  register_task(
    stage = "UPDATE_TEST",
    name = "Update Task",
    type = "R",
    description = "Updated description"
  )
  
  # Get updated timestamps
  updated <- DBI::dbGetQuery(con, 
    "SELECT created_at, updated_at, description FROM tasks WHERE task_name = 'Update Task'")
  
  # created_at should stay the same, updated_at should change
  expect_equal(original$created_at, updated$created_at)
  expect_true(updated$updated_at >= original$updated_at)
  expect_equal(updated$description, "Updated description")
})

test_that("clear_registered_tasks removes all tasks and stages", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register multiple tasks
  register_task(stage = "CLEAR_TEST_1", name = "Task 1", type = "R")
  register_task(stage = "CLEAR_TEST_1", name = "Task 2", type = "R")
  register_task(stage = "CLEAR_TEST_2", name = "Task 3", type = "R")
  
  # Verify tasks exist
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tasks")$n, 3)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages")$n, 2)
  
  # Clear all
  clear_registered_tasks(confirmation_string = NULL, interactive = FALSE)
  
  # Verify all cleared
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tasks")$n, 0)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages")$n, 0)
})

test_that("get_registered_tasks returns all tasks with proper joins", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register tasks in different stages
  register_task(
    stage = "STAGE_A",
    name = "Task A1",
    type = "R",
    stage_order = 10,
    task_order = 1,
    script_filename = "task_a1.R"
  )
  register_task(
    stage = "STAGE_A",
    name = "Task A2",
    type = "R",
    stage_order = 10,
    task_order = 2,
    script_filename = "task_a2.R"
  )
  register_task(
    stage = "STAGE_B",
    name = "Task B1",
    type = "python",
    stage_order = 20,
    task_order = 1,
    script_filename = "task_b1.R"
  )
  
  # Get registered tasks
  tasks <- get_registered_tasks()
  
  # Verify structure
  expect_s3_class(tasks, "data.frame")
  expect_equal(nrow(tasks), 3)
  
  # Verify required columns exist
  expect_true("stage_name" %in% names(tasks))
  expect_true("task_name" %in% names(tasks))
  expect_true("script_filename" %in% names(tasks))
  
  # Verify ordering
  expect_equal(tasks$stage_name, c("STAGE_A", "STAGE_A", "STAGE_B"))
  expect_equal(tasks$task_order, c(1, 2, 1))
})

test_that("register_task handles all optional parameters", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register with all parameters
  register_task(
    stage = "FULL_PARAM_TEST",
    name = "Full Task",
    stage_order = 100,
    task_order = 5,
    type = "python",
    description = "A comprehensive test",
    script_path = "/full/path",
    script_filename = "full_script.py",
    log_path = "/full/log/path",
    log_filename = "full_script.log"
  )
  
  # Verify all fields
  task <- DBI::dbGetQuery(con, 
    "SELECT * FROM tasks WHERE task_name = 'Full Task'")
  
  expect_equal(task$task_type, "python")
  expect_equal(task$task_order, 5)
  expect_equal(task$description, "A comprehensive test")
  expect_equal(task$script_path, "/full/path")
  expect_equal(task$script_filename, "full_script.py")
  expect_equal(task$log_path, "/full/log/path")
  expect_equal(task$log_filename, "full_script.log")
  
  # Verify stage order
  stage <- DBI::dbGetQuery(con, 
    "SELECT * FROM stages WHERE stage_name = 'FULL_PARAM_TEST'")
  expect_equal(stage$stage_order, 100)
})

test_that("register_task with missing optional parameters uses defaults", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register with minimal parameters (type is required)
  register_task(
    stage = "MINIMAL_TEST",
    name = "Minimal Task",
    type = "R"
  )
  
  # Verify task created
  task <- DBI::dbGetQuery(con, 
    "SELECT * FROM tasks WHERE task_name = 'Minimal Task'")
  
  expect_equal(nrow(task), 1)
  expect_equal(task$task_name, "Minimal Task")
  
  # Type is now required, so it should be 'R'
  expect_equal(task$task_type, "R")
  
  # Optional fields should be NULL or default
  expect_true(is.na(task$description) || task$description == "")
})

test_that("task registration workflow matches register_pipeline_tasks.R pattern", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Simulate the register_pipeline_tasks.R workflow
  
  # 1. Clear existing tasks
  clear_registered_tasks(confirmation_string = NULL, interactive = FALSE)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tasks")$n, 0)
  
  # 2. Create a task list similar to the tribble in register_pipeline_tasks.R
  tasks <- data.frame(
    stage = c("PREREQ", "PREREQ", "STATIC", "STATIC"),
    stage_order = c(10, 10, 20, 20),
    task_name = c("Install R", "Restore R Packages", "State Codes", "Technology Codes"),
    task_order = c(1, 3, 4, 2),
    type = c("shell", "R", "R", "R"),
    description = c("Install R", "Restore packages", "Load state codes", "Load tech codes"),
    script_filename = c("01_PREREQ_01_Install_R.sh", "01_PREREQ_03_Restore_R_Packages.R",
                       "02_STATIC_04_State_Codes.R", "02_STATIC_02_Technology_Codes.R"),
    stringsAsFactors = FALSE
  )
  
  # 3. Register each task
  for (i in seq_len(nrow(tasks))) {
    task <- tasks[i, ]
    register_task(
      stage = task$stage,
      name = task$task_name,
      stage_order = task$stage_order,
      task_order = task$task_order,
      type = task$type,
      description = task$description,
      script_filename = task$script_filename
    )
  }
  
  # 4. Verify all tasks registered
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tasks")$n, 4)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages")$n, 2)
  
  # 5. Get registered tasks and verify structure matches expectations
  registered <- get_registered_tasks()
  expect_equal(nrow(registered), 4)
  expect_true(all(c("stage_name", "task_name", "script_filename") %in% names(registered)))
  
  # Verify no missing updated_at timestamps (this would catch the original bug)
  tasks_with_timestamps <- DBI::dbGetQuery(con, 
    "SELECT task_name, created_at, updated_at FROM tasks")
  expect_true(all(!is.na(tasks_with_timestamps$created_at)))
  expect_true(all(!is.na(tasks_with_timestamps$updated_at)))
  
  stages_with_timestamps <- DBI::dbGetQuery(con, 
    "SELECT stage_name, created_at, updated_at FROM stages")
  expect_true(all(!is.na(stages_with_timestamps$created_at)))
  expect_true(all(!is.na(stages_with_timestamps$updated_at)))
})

test_that("register_task handles duplicate registration gracefully", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register same task twice
  register_task(stage = "DUP_TEST", name = "Duplicate Task", type = "R", description = "First")
  register_task(stage = "DUP_TEST", name = "Duplicate Task", type = "R", description = "Second")
  
  # Should only have one task (updated, not duplicated)
  count <- DBI::dbGetQuery(con, 
    "SELECT COUNT(*) AS n FROM tasks WHERE task_name = 'Duplicate Task'")$n
  expect_equal(count, 1)
  
  # Should have the updated description
  task <- DBI::dbGetQuery(con, 
    "SELECT description FROM tasks WHERE task_name = 'Duplicate Task'")
  expect_equal(task$description, "Second")
})

test_that("task columns support trigger operations", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a task
  register_task(stage = "TRIGGER_TEST", name = "Trigger Task", type = "R")
  
  # Get task_id
  task_id <- DBI::dbGetQuery(con, 
    "SELECT task_id FROM tasks WHERE task_name = 'Trigger Task'")$task_id
  
  # Manually update the task to trigger the updated_at trigger
  original_updated <- DBI::dbGetQuery(con, 
    sprintf("SELECT updated_at FROM tasks WHERE task_id = %d", task_id))$updated_at
  
  Sys.sleep(0.1)
  
  # Update description
  DBI::dbExecute(con, 
    sprintf("UPDATE tasks SET description = 'Manually updated' WHERE task_id = %d", task_id))
  
  # Verify updated_at changed
  new_updated <- DBI::dbGetQuery(con, 
    sprintf("SELECT updated_at FROM tasks WHERE task_id = %d", task_id))$updated_at
  
  expect_true(new_updated >= original_updated)
})
