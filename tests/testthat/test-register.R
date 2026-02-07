test_that("task registration validates input", {
  skip_on_cran()
  setup_test_db()
  
  # Should require stage and name
  expect_error(
    register_task(name = "test"),
    "'stage' must be a non-empty character string"
  )
  
  expect_error(
    register_task(stage = "TEST"),
    "'name' must be a non-empty character string"
  )
})

test_that("register_tasks handles data.frame input", {
  skip_on_cran()
  setup_test_db()
  on.exit(cleanup_test_db())
  
  tasks_df <- data.frame(
    stage = c("TEST", "TEST"),
    name = c("Task 1", "Task 2"),
    type = c("R", "sh"),
    stage_order = c(1, 1),
    stringsAsFactors = FALSE
  )
  
  # Should succeed with proper data.frame
  result <- register_tasks(tasks_df, conn = NULL)
  expect_true(length(result) == 2)
  expect_true(all(result > 0))  # Should return task IDs
  
  # Verify tasks were registered with correct values
  con <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  tasks_table <- tasker:::get_table_name("tasks", con)
  registered <- DBI::dbGetQuery(con, 
    glue::glue_sql("SELECT task_name, task_type FROM {tasks_table} WHERE task_name IN ('Task 1', 'Task 2') ORDER BY task_name", .con = con)
  )
  
  expect_equal(nrow(registered), 2)
  expect_equal(registered$task_name, c("Task 1", "Task 2"))
  expect_equal(registered$task_type, c("R", "sh"))
})


# Helper to check if test database is available
check_test_db_available <- function() {
  tryCatch({
    config <- Sys.getenv("TASKER_TEST_DB")
    return(nchar(config) > 0)
  }, error = function(e) {
    FALSE
  })
}
