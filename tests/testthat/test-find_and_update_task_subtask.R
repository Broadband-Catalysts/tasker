test_that("update_task requires stage/filename and task parameters", {
  skip_on_cran()
  
  # Missing stage when no filename
  expect_error(
    find_and_update_task(task = "Test", status = "COMPLETED"),
    "Either provide.*filename.*or both.*stage.*and.*task"
  )
  
  # Missing task when no filename
  expect_error(
    find_and_update_task(stage = "STATIC", status = "COMPLETED"),
    "Either provide.*filename.*or both.*stage.*and.*task"
  )
})

test_that("update_task validates status parameter", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  expect_error(
    find_and_update_task(stage = "STATIC", task = "Test", status = "INVALID"),
    "'arg' should be one of"
  )
})

test_that("update_task by filename alone", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register a test task
  register_task(
    stage = "TEST_STAGE",
    name = "Update Task Test",
    type = "R",
    script_filename = "test_update_task.R"
  )
  
  # Run task to create a task_run
  run_id <- task_start("TEST_STAGE", "Update Task Test")
  task_complete(run_id)
  
  # Now update by filename
  result <- find_and_update_task(
    filename = "test_update_task.R",
    status = "COMPLETED",
    message = "Updated by filename"
  )
  
  expect_true(result)
})

test_that("update_task by stage and task number", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register test stage and tasks with explicit task_order
  register_task(
    stage = "NUMBER_TEST_STAGE",
    name = "Task One",
    stage_order = 999,
    task_order = 1,
    type = "R"
  )
  register_task(
    stage = "NUMBER_TEST_STAGE",
    name = "Task Two",
    stage_order = 999,
    task_order = 2,
    type = "R"
  )
  
  # Run task to create a task_run
  run_id <- task_start("NUMBER_TEST_STAGE", "Task Two")
  task_complete(run_id)
  
  # Update by stage name and task name (safer than numbers)
  result <- find_and_update_task("NUMBER_TEST_STAGE", "Task Two", "COMPLETED")
  
  expect_true(result)
})

test_that("update_task by stage name and task name", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Specific Task",
    type = "R"
  )
  
  run_id <- task_start("TEST_STAGE", "Specific Task")
  task_complete(run_id)
  
  result <- find_and_update_task(
    stage = "TEST_STAGE",
    task = "Specific Task",
    status = "COMPLETED",
    message = "Updated by name"
  )
  
  expect_true(result)
})

test_that("update_task handles partial filename matching", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Partial Match Test",
    type = "R",
    script_filename = "01_PREREQ_01_Long_Script_Name.R"
  )
  
  run_id <- task_start("TEST_STAGE", "Partial Match Test")
  task_complete(run_id)
  
  # Partial filename match should work
  result <- find_and_update_task(
    filename = "PREREQ_01",
    status = "COMPLETED"
  )
  
  expect_true(result)
})

test_that("update_task rejects ambiguous filename matches", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register two tasks with similar filenames
  register_task(
    stage = "TEST_STAGE",
    name = "Task A",
    type = "R",
    script_filename = "test_script_01.R"
  )
  register_task(
    stage = "TEST_STAGE",
    name = "Task B",
    type = "R",
    script_filename = "test_script_02.R"
  )
  
  run_id <- task_start("TEST_STAGE", "Task A")
  task_complete(run_id)
  
  # Ambiguous partial match should error
  expect_error(
    find_and_update_task(filename = "test_script", status = "COMPLETED"),
    "ambiguous"
  )
})

test_that("update_task rejects nonexistent filename", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  expect_error(
    find_and_update_task(filename = "nonexistent_file.R", status = "COMPLETED"),
    "not found"
  )
})

test_that("update_task handles all status values", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Status Test",
    type = "R"
  )
  
  for (status in c("RUNNING", "COMPLETED", "FAILED", "SKIPPED", "CANCELLED")) {
    run_id <- task_start("TEST_STAGE", "Status Test")
    
    result <- find_and_update_task(
      stage = "TEST_STAGE",
      task = "Status Test",
      status = status
    )
    
    expect_true(result)
    
    task_complete(run_id)
  }
})

test_that("update_task with optional message and error_message", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Message Test",
    type = "R"
  )
  
  run_id <- task_start("TEST_STAGE", "Message Test")
  
  result <- find_and_update_task(
    stage = "TEST_STAGE",
    task = "Message Test",
    status = "COMPLETED",
    message = "Processing complete",
    error_message = NULL
  )
  
  expect_true(result)
  
  task_complete(run_id)
})

# ============================================================================
# update_subtask tests
# ============================================================================

test_that("update_subtask requires stage, task, and subtask parameters", {
  skip_on_cran()
  
  # Missing all required parameters
  expect_error(
    find_and_update_subtask(),
    "missing"
  )
  
  # Missing subtask
  expect_error(
    find_and_update_subtask(stage = "STATIC", task = "Test"),
    "missing"
  )
  
  # Missing task when no filename - gets helpful message
  expect_error(
    find_and_update_subtask(stage = "STATIC", subtask = 1),
    "Either provide.*filename.*or both.*stage.*and.*task"
  )
  
  # Missing stage when no filename - gets helpful message
  expect_error(
    find_and_update_subtask(task = "Test", subtask = 1),
    "Either provide.*filename.*or both.*stage.*and.*task"
  )
})

test_that("update_subtask validates status parameter", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  expect_error(
    find_and_update_subtask(stage = "STATIC", task = "Test", subtask = 1, status = "INVALID"),
    "'arg' should be one of"
  )
})

test_that("update_subtask by filename with subtask number", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Subtask Test",
    type = "R",
    script_filename = "test_subtask.R"
  )
  
  run_id <- task_start("TEST_STAGE", "Subtask Test")
  subtask_start("Processing", items_total = 100, quiet = TRUE, run_id = run_id, subtask_number = 1)
  
  result <- find_and_update_subtask(
    filename = "test_subtask.R",
    subtask = 1,
    status = "RUNNING",
    items_completed = 50
  )
  
  expect_true(result)
  
  task_complete(run_id)
})

test_that("update_subtask by stage and task names", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Named Subtask Test",
    type = "R"
  )
  
  run_id <- task_start("TEST_STAGE", "Named Subtask Test")
  subtask_start("Processing Part 2", items_total = 50, quiet = TRUE, run_id = run_id, subtask_number = 2)
  
  result <- find_and_update_subtask(
    stage = "TEST_STAGE",
    task = "Named Subtask Test",
    subtask = 2,
    status = "RUNNING",
    items_completed = 25
  )
  
  expect_true(result)
  
  task_complete(run_id)
})

test_that("update_subtask handles all status values", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Status Subtask Test",
    type = "R"
  )
  
  for (status in c("RUNNING", "COMPLETED", "FAILED", "SKIPPED")) {
    run_id <- task_start("TEST_STAGE", "Status Subtask Test")
    subtask_start("Test", quiet = TRUE, run_id = run_id, subtask_number = 1)
    
    result <- find_and_update_subtask(
      stage = "TEST_STAGE",
      task = "Status Subtask Test",
      subtask = 1,
      status = status
    )
    
    expect_true(result)
    
    task_complete(run_id)
  }
})

test_that("update_subtask with percent and items tracking", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Progress Test",
    type = "R"
  )
  
  run_id <- task_start("TEST_STAGE", "Progress Test")
  subtask_start("Processing", items_total = 1000, quiet = TRUE, run_id = run_id, subtask_number = 1)
  
  result <- find_and_update_subtask(
    stage = "TEST_STAGE",
    task = "Progress Test",
    subtask = 1,
    status = "RUNNING",
    percent = 50,
    items_total = 1000,
    items_completed = 500
  )
  
  expect_true(result)
  
  task_complete(run_id)
})

test_that("update_subtask with message and error_message", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Message Subtask Test",
    type = "R"
  )
  
  run_id <- task_start("TEST_STAGE", "Message Subtask Test")
  subtask_start("Test", quiet = TRUE, run_id = run_id, subtask_number = 1)
  
  result <- find_and_update_subtask(
    stage = "TEST_STAGE",
    task = "Message Subtask Test",
    subtask = 1,
    status = "COMPLETED",
    message = "Subtask complete",
    error_message = NULL
  )
  
  expect_true(result)
  
  task_complete(run_id)
})

test_that("update_subtask rejects missing subtask", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Missing Subtask Test",
    type = "R"
  )
  
  run_id <- task_start("TEST_STAGE", "Missing Subtask Test")
  subtask_start("First subtask", quiet = TRUE, run_id = run_id, subtask_number = 1)
  
  # Trying to update subtask 99 which doesn't exist should error
  expect_error(
    find_and_update_subtask(
      stage = "TEST_STAGE",
      task = "Missing Subtask Test",
      subtask = 99,
      status = "COMPLETED"
    ),
    "not found|does not exist"
  )
  
  task_complete(run_id)
})

test_that("update_task and update_subtask work in sequence", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Sequence Test",
    type = "R",
    script_filename = "test_sequence.R"
  )
  
  run_id <- task_start("TEST_STAGE", "Sequence Test")
  subtask_start("Part 1", quiet = TRUE, run_id = run_id, subtask_number = 1)
  subtask_start("Part 2", quiet = TRUE, run_id = run_id, subtask_number = 2)
  
  # Update first subtask
  result1 <- find_and_update_subtask(
    filename = "test_sequence.R",
    subtask = 1,
    status = "COMPLETED"
  )
  expect_true(result1)
  
  # Update second subtask
  result2 <- find_and_update_subtask(
    filename = "test_sequence.R",
    subtask = 2,
    status = "COMPLETED"
  )
  expect_true(result2)
  
  # Update overall task
  result3 <- find_and_update_task(
    filename = "test_sequence.R",
    status = "COMPLETED"
  )
  expect_true(result3)
  
  task_complete(run_id)
})

# ============================================================================
# Numeric Lookup Tests - stage_order, task_order, subtask_number
# ============================================================================

test_that("update_task works with stage_order + task_order", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register task with stage_order and task_order
  register_task(
    stage = "NUMERIC_TEST_STAGE",
    name = "Numeric Task 1",
    type = "R",
    script_filename = "numeric_test.R",
    stage_order = 5,
    task_order = 3
  )
  
  # Start task to create run
  run_id <- task_start("NUMERIC_TEST_STAGE", "Numeric Task 1")
  task_complete(run_id)
  
  # Update using stage_order and task_order
  result <- find_and_update_task(
    stage = 5,
    task = 3,
    status = "RUNNING"
  )
  expect_true(result)
  
  # Verify status was updated
  status <- DBI::dbGetQuery(
    con,
    "SELECT status FROM task_runs WHERE run_id = ?",
    params = list(run_id)
  )$status
  expect_equal(status, "RUNNING")
})

test_that("update_task works with stage_order + task_name", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register task with stage_order and task_order
  register_task(
    stage = "MIXED_LOOKUP_STAGE",
    name = "Mixed Task Name",
    type = "R",
    script_filename = "mixed_test.R",
    stage_order = 7,
    task_order = 2
  )
  
  run_id <- task_start("MIXED_LOOKUP_STAGE", "Mixed Task Name")
  task_complete(run_id)
  
  # Update using stage_order (numeric) and task name (string)
  result <- find_and_update_task(
    stage = 7,
    task = "Mixed Task Name",
    status = "FAILED",
    error_message = "Test failure"
  )
  expect_true(result)
  
  # Verify
  status <- DBI::dbGetQuery(
    con,
    "SELECT status, error_message FROM task_runs WHERE run_id = ?",
    params = list(run_id)
  )
  expect_equal(status$status, "FAILED")
  expect_equal(status$error_message, "Test failure")
})

test_that("update_task works with stage_name + task_order", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register task with stage_order and task_order
  register_task(
    stage = "NAME_ORDER_STAGE",
    name = "Order Task",
    type = "R",
    script_filename = "order_test.R",
    stage_order = 4,
    task_order = 8
  )
  
  run_id <- task_start("NAME_ORDER_STAGE", "Order Task")
  task_complete(run_id)
  
  # Update using stage name (string) and task_order (numeric)
  result <- find_and_update_task(
    stage = "NAME_ORDER_STAGE",
    task = 8,
    status = "SKIPPED",
    message = "Skipped for testing"
  )
  expect_true(result)
  
  # Verify
  run_data <- DBI::dbGetQuery(
    con,
    "SELECT status, overall_progress_message FROM task_runs WHERE run_id = ?",
    params = list(run_id)
  )
  expect_equal(run_data$status, "SKIPPED")
  expect_equal(run_data$overall_progress_message, "Skipped for testing")
})

test_that("update_subtask works with stage_order + task_order + subtask_number", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register task with stage_order and task_order
  register_task(
    stage = "SUBTASK_NUMERIC_STAGE",
    name = "Subtask Numeric Task",
    type = "R",
    script_filename = "subtask_numeric.R",
    stage_order = 6,
    task_order = 5
  )
  
  # Start task and create subtasks
  run_id <- task_start("SUBTASK_NUMERIC_STAGE", "Subtask Numeric Task")
  subtask_start("Process Items", items_total = 100, run_id = run_id, subtask_number = 1)
  subtask_start("Validate Results", items_total = 50, run_id = run_id, subtask_number = 2)
  
  # Update subtask using all numeric parameters
  result <- find_and_update_subtask(
    stage = 6,
    task = 5,
    subtask = 1,
    status = "RUNNING",
    items_completed = 25,
    percent = 25
  )
  expect_true(result)
  
  # Verify
  subtask_data <- DBI::dbGetQuery(
    con,
    "SELECT status, items_complete, percent_complete FROM subtask_progress 
     WHERE run_id = ? AND subtask_number = ?",
    params = list(run_id, 1)
  )
  expect_equal(subtask_data$status, "RUNNING")
  expect_equal(subtask_data$items_complete, 25)
  expect_equal(subtask_data$percent_complete, 25)
  
  task_complete(run_id)
})

test_that("update_subtask works with stage_order + task_name + subtask_name", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register task with stage_order and task_order
  register_task(
    stage = "SUBTASK_MIXED_STAGE",
    name = "Subtask Mixed Task",
    type = "R",
    script_filename = "subtask_mixed.R",
    stage_order = 9,
    task_order = 1
  )
  
  # Start task and create subtasks
  run_id <- task_start("SUBTASK_MIXED_STAGE", "Subtask Mixed Task")
  subtask_start("Load Data", items_total = 1000, run_id = run_id, subtask_number = 1)
  subtask_start("Transform Data", items_total = 1000, run_id = run_id, subtask_number = 2)
  
  # Update using stage_order + task_name + subtask_name
  result <- find_and_update_subtask(
    stage = 9,
    task = "Subtask Mixed Task",
    subtask = "Transform Data",
    status = "COMPLETED",
    items_completed = 1000,
    percent = 100
  )
  expect_true(result)
  
  # Verify
  subtask_data <- DBI::dbGetQuery(
    con,
    "SELECT status, items_complete FROM subtask_progress 
     WHERE run_id = ? AND subtask_number = ?",
    params = list(run_id, 2)
  )
  expect_equal(subtask_data$status, "COMPLETED")
  expect_equal(subtask_data$items_complete, 1000)
  
  task_complete(run_id)
})

# ============================================================================
# force parameter tests
# ============================================================================

test_that("update_task with force=FALSE fails when no run exists", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "No Run Task",
    type = "R",
    script_filename = "no_run.R"
  )
  
  # Don't start a task - no run exists
  # force=FALSE should error
  expect_error(
    find_and_update_task(
      filename = "no_run.R",
      status = "COMPLETED",
      force = FALSE
    ),
    "No task runs found.*force=FALSE"
  )
})

test_that("update_task with force=TRUE creates new run when none exists", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Force Create Task",
    type = "R",
    script_filename = "force_create.R"
  )
  
  # Don't start a task - no run exists
  # force=TRUE should create a new run
  expect_warning(
    result <- find_and_update_task(
      filename = "force_create.R",
      status = "COMPLETED",
      force = TRUE
    ),
    "No existing run found.*Creating new run"
  )
  
  expect_true(result)
  
  # Verify a run was created
  runs <- DBI::dbGetQuery(
    con,
    "SELECT COUNT(*) as count FROM task_runs tr
     JOIN tasks t ON tr.task_id = t.task_id
     WHERE t.task_name = 'Force Create Task'"
  )
  expect_equal(as.integer(runs$count), 1)
})

test_that("update_subtask with force=FALSE fails when no run exists", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "No Run Subtask Task",
    type = "R",
    script_filename = "no_run_subtask.R"
  )
  
  # Don't start a task - no run exists
  # force=FALSE should error
  expect_error(
    find_and_update_subtask(
      filename = "no_run_subtask.R",
      subtask = 1,
      status = "COMPLETED",
      force = FALSE
    ),
    "No task runs found.*force=FALSE"
  )
})

test_that("update_subtask with force=TRUE creates new run and subtask when none exists", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Force Create Subtask Task",
    type = "R",
    script_filename = "force_create_subtask.R"
  )
  
  # Don't start a task - no run exists
  # force=TRUE should create a new run and subtask
  expect_warning(
    result <- find_and_update_subtask(
      filename = "force_create_subtask.R",
      subtask = 1,
      status = "COMPLETED",
      items_total = 100,
      items_completed = 100,
      force = TRUE
    ),
    "No existing run found.*Creating new run"
  )
  
  expect_true(result)
  
  # Verify a run and subtask were created
  runs <- DBI::dbGetQuery(
    con,
    "SELECT COUNT(*) as count FROM task_runs tr
     JOIN tasks t ON tr.task_id = t.task_id
     WHERE t.task_name = 'Force Create Subtask Task'"
  )
  expect_equal(as.integer(runs$count), 1)
  
  # Check subtask was created
  run_id <- DBI::dbGetQuery(
    con,
    "SELECT tr.run_id FROM task_runs tr
     JOIN tasks t ON tr.task_id = t.task_id
     WHERE t.task_name = 'Force Create Subtask Task'"
  )$run_id[1]
  
  subtasks <- DBI::dbGetQuery(
    con,
    "SELECT COUNT(*) as count FROM subtask_progress
     WHERE run_id = ?",
    params = list(run_id)
  )
  expect_equal(as.integer(subtasks$count), 1)
})

# ============================================================================
# filename path stripping tests
# ============================================================================

test_that("update_task strips path from filename parameter", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Path Strip Test",
    type = "R",
    script_filename = "test_script.R"
  )
  
  run_id <- task_start("TEST_STAGE", "Path Strip Test")
  task_complete(run_id)
  
  # Pass full path - should strip to basename and match
  result <- find_and_update_task(
    filename = "/home/user/scripts/test_script.R",
    status = "COMPLETED"
  )
  
  expect_true(result)
})

test_that("update_subtask strips path from filename parameter", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  register_task(
    stage = "TEST_STAGE",
    name = "Subtask Path Strip Test",
    type = "R",
    script_filename = "subtask_script.R"
  )
  
  run_id <- task_start("TEST_STAGE", "Subtask Path Strip Test")
  subtask_start("Processing", items_total = 50, run_id = run_id, subtask_number = 1)
  
  # Pass full path - should strip to basename and match
  result <- find_and_update_subtask(
    filename = "/path/to/scripts/subtask_script.R",
    subtask = 1,
    status = "COMPLETED",
    items_completed = 50
  )
  
  expect_true(result)
  
  task_complete(run_id)
})

test_that("update_subtask works with stage_name + task_order + subtask_number", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # Register task with stage_order and task_order
  register_task(
    stage = "FINAL_COMBO_STAGE",
    name = "Final Combo Task",
    type = "R",
    script_filename = "final_combo.R",
    stage_order = 8,
    task_order = 7
  )
  
  # Start task and create subtasks
  run_id <- task_start("FINAL_COMBO_STAGE", "Final Combo Task")
  subtask_start("First Step", items_total = 200, run_id = run_id, subtask_number = 1)
  subtask_start("Second Step", items_total = 300, run_id = run_id, subtask_number = 2)
  subtask_start("Third Step", items_total = 400, run_id = run_id, subtask_number = 3)
  
  # Update using stage_name + task_order + subtask_number
  result <- find_and_update_subtask(
    stage = "FINAL_COMBO_STAGE",
    task = 7,
    subtask = 3,
    status = "FAILED",
    error_message = "Processing error in third step"
  )
  expect_true(result)
  
  # Verify
  subtask_data <- DBI::dbGetQuery(
    con,
    "SELECT status, error_message FROM subtask_progress 
     WHERE run_id = ? AND subtask_number = ?",
    params = list(run_id, 3)
  )
  expect_equal(subtask_data$status, "FAILED")
  expect_equal(subtask_data$error_message, "Processing error in third step")
  
  task_complete(run_id)
})
