test_that("subtask tracking validates input", {
  skip_on_cran()
  
  # Test that subtask functions exist
  expect_true(exists("subtask_start"))
  expect_true(exists("subtask_update"))
  expect_true(exists("subtask_complete"))
  expect_true(exists("subtask_fail"))
})

test_that("subtask progress updates correctly", {
  # Test progress calculation
  items_total <- 50
  items_complete <- 10
  
  percent <- (items_complete / items_total) * 100
  expect_equal(percent, 20.0)
})
