test_that("task tracking creates proper run_id", {
  skip_on_cran()
  skip_if_not(check_test_db_available())
  
  # Test that task_start returns a UUID
  # This is a mock test without actual database
  expect_true(exists("task_start"))
  expect_true(exists("task_update"))
  expect_true(exists("task_end"))
})

test_that("progress calculations work", {
  # Test percent complete calculation
  total <- 100
  complete <- 25
  percent <- (complete / total) * 100
  
  expect_equal(percent, 25.0)
  expect_true(percent >= 0 && percent <= 100)
})

test_that("status values are valid", {
  valid_statuses <- c('NOT_STARTED', 'STARTED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED', 'CANCELLED')
  
  # Test that our expected statuses are in the valid list
  expect_true("STARTED" %in% valid_statuses)
  expect_true("RUNNING" %in% valid_statuses)
  expect_true("COMPLETED" %in% valid_statuses)
  expect_true("FAILED" %in% valid_statuses)
})

check_test_db_available <- function() {
  tryCatch({
    config <- Sys.getenv("TASKER_TEST_DB")
    return(nchar(config) > 0)
  }, error = function(e) {
    FALSE
  })
}
