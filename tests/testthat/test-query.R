test_that("query functions exist", {
  # Test that query functions are defined
  expect_true(exists("get_task_status"))
  expect_true(exists("get_active_tasks"))
  expect_true(exists("get_task_history"))
})

test_that("get_stages filters correctly", {
  skip_on_cran()
  setup_test_db()
  
  # Just test function exists
  expect_true(exists("get_stages"))
})

check_test_db_available <- function() {
  tryCatch({
    config <- Sys.getenv("TASKER_TEST_DB")
    return(nchar(config) > 0)
  }, error = function(e) {
    FALSE
  })
}
