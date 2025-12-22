test_that("task registration validates input", {
  skip_on_cran()
  setup_test_db()
  
  # Should require stage and name
  expect_error(
    register_task(name = "test"),
    "stage.*required"
  )
  
  expect_error(
    register_task(stage = "TEST"),
    "name.*required"
  )
})

test_that("register_tasks handles data.frame input", {
  skip_on_cran()
  setup_test_db()
  
  tasks_df <- data.frame(
    stage = c("TEST", "TEST"),
    name = c("Task 1", "Task 2"),
    type = c("R", "sh"),
    stringsAsFactors = FALSE
  )
  
  # This would need a test database
  # Just test that the function exists and validates
  expect_error(
    register_tasks(tasks_df, conn = NULL),
    NA  # Should not error on structure
  )
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
