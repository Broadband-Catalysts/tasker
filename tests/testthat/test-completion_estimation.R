test_that("format_duration_seconds formats correctly", {
  # Zero and negative
  expect_equal(format_duration_seconds(0), "0s")
  expect_equal(format_duration_seconds(-5), "0s")
  expect_equal(format_duration_seconds(NA), "0s")
  expect_equal(format_duration_seconds(NULL), "0s")
  
  # Seconds only
  expect_equal(format_duration_seconds(1), "1s")
  expect_equal(format_duration_seconds(45), "45s")
  expect_equal(format_duration_seconds(59), "59s")
  
  # Minutes
  expect_equal(format_duration_seconds(60), "1m")
  expect_equal(format_duration_seconds(90), "1m")
  expect_equal(format_duration_seconds(120), "2m")
  expect_equal(format_duration_seconds(3599), "59m")
  
  # Hours
  expect_equal(format_duration_seconds(3600), "1h")
  expect_equal(format_duration_seconds(3660), "1h 1m")
  expect_equal(format_duration_seconds(7200), "2h")
  expect_equal(format_duration_seconds(7260), "2h 1m")
  expect_equal(format_duration_seconds(86399), "23h 59m")
  
  # Days
  expect_equal(format_duration_seconds(86400), "1d")
  expect_equal(format_duration_seconds(90000), "1d 1h")
  expect_equal(format_duration_seconds(172800), "2d")
  expect_equal(format_duration_seconds(176400), "2d 1h")
})

test_that("get_completion_estimate returns NULL with insufficient data", {
  env <- new.env(parent = emptyenv())
  
  # No data
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  expect_null(result)
  
  # Only 1 snapshot
  assign("run_test_run_subtask_1", list(
    list(timestamp = Sys.time(), items_complete = 10, items_total = 100)
  ), envir = env)
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  expect_null(result)
  
  # Only 2 snapshots
  assign("run_test_run_subtask_1", list(
    list(timestamp = Sys.time() - 10, items_complete = 10, items_total = 100),
    list(timestamp = Sys.time(), items_complete = 20, items_total = 100)
  ), envir = env)
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  expect_null(result)
})

test_that("get_completion_estimate calculates with valid data", {
  env <- new.env(parent = emptyenv())
  
  # Create snapshots with consistent progress - 50% complete
  base_time <- Sys.time()
  snapshots <- list()
  for (i in 1:10) {
    snapshots[[i]] <- list(
      timestamp = base_time + (i - 1) * 5,  # Every 5 seconds
      items_complete = i * 5,  # 5 items per snapshot, reaching 50 items
      items_total = 100
    )
  }
  assign("run_test_run_subtask_1", snapshots, envir = env)
  
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  
  expect_type(result, "list")
  expect_named(result, c("eta", "confidence_interval", "confidence", "rate", "items_remaining"))
  expect_type(result$eta, "double")
  expect_length(result$confidence_interval, 2)
  expect_true(result$confidence_interval[1] <= result$confidence_interval[2])
  expect_true(result$eta > 0)  # Still work remaining
  expect_true(result$rate > 0)
  expect_equal(result$items_remaining, 50)  # 50 items complete out of 100
  expect_equal(result$confidence, "medium")  # 9 rates (10 snapshots - 1), need >=10 for "high"
})

test_that("get_completion_estimate handles no progress", {
  env <- new.env(parent = emptyenv())
  
  # Create snapshots with NO progress (items_complete doesn't change)
  base_time <- Sys.time()
  snapshots <- list()
  for (i in 1:10) {
    snapshots[[i]] <- list(
      timestamp = base_time + (i - 1) * 5,
      items_complete = 50,  # No change
      items_total = 100
    )
  }
  assign("run_test_run_subtask_1", snapshots, envir = env)
  
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  
  # Should return NULL because no valid rates (all rates are 0)
  expect_null(result)
})

test_that("get_completion_estimate confidence levels are correct", {
  env <- new.env(parent = emptyenv())
  base_time <- Sys.time()
  
  # Test low confidence (< 5 rates)
  snapshots <- list()
  for (i in 1:4) {
    snapshots[[i]] <- list(
      timestamp = base_time + (i - 1) * 5,
      items_complete = i * 10,
      items_total = 100
    )
  }
  assign("run_test_run_subtask_1", snapshots, envir = env)
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  expect_equal(result$confidence, "low")
  
  # Test medium confidence (5-9 rates)
  snapshots <- list()
  for (i in 1:7) {
    snapshots[[i]] <- list(
      timestamp = base_time + (i - 1) * 5,
      items_complete = i * 10,
      items_total = 100
    )
  }
  assign("run_test_run_subtask_1", snapshots, envir = env)
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  expect_equal(result$confidence, "medium")
  
  # Test high confidence (>= 10 rates)
  snapshots <- list()
  for (i in 1:12) {
    snapshots[[i]] <- list(
      timestamp = base_time + (i - 1) * 5,
      items_complete = i * 5,
      items_total = 100
    )
  }
  assign("run_test_run_subtask_1", snapshots, envir = env)
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  expect_equal(result$confidence, "high")
})

test_that("format_completion_with_ci formats correctly", {
  # NULL estimate
  result <- format_completion_with_ci(NULL)
  expect_equal(result, "Computing...")
  
  # Valid estimate
  estimate <- list(
    eta = 3665,  # 1h 1m 5s
    confidence_interval = c(3600, 7200),  # 1h to 2h
    confidence = "high",
    rate = 1.5,
    items_remaining = 50
  )
  result <- format_completion_with_ci(estimate)
  expect_match(result, "1h 1m")
  expect_match(result, "●")  # High confidence indicator
  expect_match(result, "95% CI:")
  expect_match(result, "1h")
  expect_match(result, "2h")
  
  # Medium confidence
  estimate$confidence <- "medium"
  result <- format_completion_with_ci(estimate)
  expect_match(result, "◐")  # Medium confidence indicator
  
  # Low confidence
  estimate$confidence <- "low"
  result <- format_completion_with_ci(estimate)
  expect_match(result, "○")  # Low confidence indicator
})

test_that("get_completion_estimate handles varying rates", {
  env <- new.env(parent = emptyenv())
  base_time <- Sys.time()
  
  # Create snapshots with varying progress rates
  snapshots <- list(
    list(timestamp = base_time, items_complete = 0, items_total = 100),
    list(timestamp = base_time + 5, items_complete = 10, items_total = 100),  # rate = 2/sec
    list(timestamp = base_time + 10, items_complete = 15, items_total = 100), # rate = 1/sec
    list(timestamp = base_time + 15, items_complete = 25, items_total = 100), # rate = 2/sec
    list(timestamp = base_time + 20, items_complete = 30, items_total = 100)  # rate = 1/sec
  )
  assign("run_test_run_subtask_1", snapshots, envir = env)
  
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  
  expect_type(result, "list")
  expect_true(result$rate > 0)
  expect_equal(result$items_remaining, 70)
  # Average rate should be (2+1+2+1)/4 = 1.5 items/sec
  expect_equal(result$rate, 1.5)
})

test_that("get_completion_estimate limits to 50 recent snapshots", {
  env <- new.env(parent = emptyenv())
  base_time <- Sys.time()
  
  # Create 100 snapshots
  snapshots <- list()
  for (i in 1:100) {
    snapshots[[i]] <- list(
      timestamp = base_time + (i - 1) * 2,
      items_complete = i,
      items_total = 200
    )
  }
  assign("run_test_run_subtask_1", snapshots, envir = env)
  
  result <- get_completion_estimate(env, "test_run", 1, quiet = TRUE)
  
  # Should use only last 50 snapshots, giving 49 rates
  expect_type(result, "list")
  # With 50 snapshots we get 49 rates, all should be 0.5 items/sec
  expect_equal(result$rate, 0.5)
  expect_equal(result$items_remaining, 100)  # 200 - 100 items complete
})
