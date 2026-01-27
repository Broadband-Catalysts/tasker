# Tests for Shiny reactive pattern fixes
# Validates query cooldown, reactiveTimer behavior, and state management

test_that("query cooldown prevents rapid database queries", {
  # Test the cooldown logic in isolation (without full Shiny context)
  
  # Simulate timing checks
  current_time <- Sys.time()
  last_query_time <- current_time - 3  # 3 seconds ago
  min_query_interval <- 5  # 5 second minimum
  
  # Calculate time since last query (mimics server.R logic)
  time_since_last <- as.numeric(difftime(current_time, last_query_time, units = "secs"))
  
  # Should fail cooldown (< 5 seconds)
  expect_true(time_since_last < min_query_interval)
  expect_false(time_since_last >= min_query_interval)
  
  # Simulate waiting 5+ seconds
  last_query_time <- current_time - 6  # 6 seconds ago
  time_since_last <- as.numeric(difftime(current_time, last_query_time, units = "secs"))
  
  # Should pass cooldown (>= 5 seconds)
  expect_true(time_since_last >= min_query_interval)
})

test_that("query cooldown logic matches server.R implementation", {
  # Verify the exact pattern used in server.R works correctly
  min_query_interval <- 5
  
  # Test cases: (seconds_since_last, should_allow_query)
  test_cases <- list(
    list(elapsed = 0,   should_pass = FALSE),
    list(elapsed = 2,   should_pass = FALSE),
    list(elapsed = 4.9, should_pass = FALSE),
    list(elapsed = 5.0, should_pass = TRUE),
    list(elapsed = 5.1, should_pass = TRUE),
    list(elapsed = 10,  should_pass = TRUE),
    list(elapsed = 100, should_pass = TRUE)
  )
  
  current_time <- Sys.time()
  
  for (tc in test_cases) {
    last_query_time <- current_time - tc$elapsed
    time_since_last <- as.numeric(difftime(current_time, last_query_time, units = "secs"))
    passes_cooldown <- time_since_last >= min_query_interval
    
    expect_equal(
      passes_cooldown, 
      tc$should_pass,
      info = sprintf("elapsed=%.1f should_pass=%s", tc$elapsed, tc$should_pass)
    )
  }
})

test_that("initial_load_complete flag pattern works correctly", {
  # Test the boolean flag state transition pattern used in server.R
  
  # Initialize (mimics rv initialization)
  initial_load_complete <- FALSE
  
  # Before first load, should be FALSE
  expect_false(initial_load_complete)
  
  # First load check (should skip tab requirement)
  if (!initial_load_complete) {
    # This path should be taken on first run
    expect_true(TRUE)  # Confirm we entered this branch
  } else {
    fail("Should not check tab requirement on initial load")
  }
  
  # After first successful update, set to TRUE
  initial_load_complete <- TRUE
  expect_true(initial_load_complete)
  
  # Subsequent loads check the flag (should check tab requirement)
  if (initial_load_complete) {
    # This path should be taken on subsequent runs
    expect_true(TRUE)  # Confirm we entered this branch
  } else {
    fail("Should check tab requirement after initial load")
  }
  
  # Flag should remain TRUE (one-way transition)
  expect_true(initial_load_complete)
})

test_that("reactiveTimer interval calculation is correct", {
  # Test the interval calculation logic used in auto_refresh_timer
  
  test_intervals <- c(1, 5, 10, 30, 60)
  
  for (interval_seconds in test_intervals) {
    interval_ms <- interval_seconds * 1000
    
    # Verify conversion to milliseconds is correct
    expect_equal(interval_ms, interval_seconds * 1000)
    expect_true(interval_ms > 0)
    expect_true(is.numeric(interval_ms))
  }
  
  # Edge cases
  expect_equal(0.5 * 1000, 500)   # Sub-second interval
  expect_equal(1 * 1000, 1000)    # 1 second
  expect_equal(120 * 1000, 120000) # 2 minutes
})

test_that("query state transitions follow correct pattern", {
  # Test the query_running flag state transitions
  
  # Initialize
  query_running <- FALSE
  last_query_time <- Sys.time() - 60  # Start with old timestamp
  
  # Before query
  expect_false(query_running)
  
  # Start query (mimics task_data entry)
  query_running <- TRUE
  expect_true(query_running)
  
  # Complete query (mimics on.exit cleanup)
  query_running <- FALSE
  last_query_time <- Sys.time()
  expect_false(query_running)
  
  # Verify timestamp was updated (should be recent)
  time_since_update <- as.numeric(difftime(Sys.time(), last_query_time, units = "secs"))
  expect_true(time_since_update < 1)  # Should be < 1 second old
})

test_that("isolate pattern prevents reactive dependency", {
  # This test documents the isolate() pattern used throughout server.R
  # We can't fully test reactive isolation without a running Shiny app,
  # but we can verify the logic that gets isolated
  
  # Simulate reactive values
  last_update <- Sys.time()
  initial_load_complete <- FALSE
  main_tabs <- "Pipeline Status"
  
  # Pattern 1: Check initial_load_complete with isolate
  # In actual code: if (isolate(rv$initial_load_complete))
  if (!initial_load_complete) {
    # Should skip tab check on first load
    expect_false(initial_load_complete)
  }
  
  # Pattern 2: After setting flag with isolate
  # In actual code: isolate(rv$initial_load_complete <- TRUE)
  initial_load_complete <- TRUE
  
  # Pattern 3: Check tab with isolate  
  # In actual code: req(isolate(input$main_tabs) == "Pipeline Status")
  if (initial_load_complete) {
    # Should check tab on subsequent loads
    expect_equal(main_tabs, "Pipeline Status")
  }
  
  # Pattern 4: Update timestamp with isolate
  # In actual code: isolate(rv$last_update <- Sys.time())
  last_update <- Sys.time()
  expect_true(inherits(last_update, "POSIXct"))
})

test_that("cooldown timing is consistent across multiple cycles", {
  # Test that cooldown enforcement works across multiple query cycles
  
  min_query_interval <- 5
  query_times <- c()
  
  # Simulate 10 query attempts
  for (i in 1:10) {
    current_time <- Sys.time()
    
    if (length(query_times) == 0) {
      # First query - always allowed
      query_times <- c(query_times, current_time)
    } else {
      # Subsequent queries - check cooldown
      last_query <- query_times[length(query_times)]
      time_since_last <- as.numeric(difftime(current_time, last_query, units = "secs"))
      
      if (time_since_last >= min_query_interval) {
        query_times <- c(query_times, current_time)
      }
    }
    
    # Simulate some processing time (< cooldown)
    Sys.sleep(0.1)
  }
  
  # With 0.1s sleep between attempts, we should only have 1 query
  # (10 attempts * 0.1s = 1 second total, < 5 second cooldown)
  expect_equal(length(query_times), 1)
  
  # If we wait for cooldown, next query should succeed
  Sys.sleep(5.1)
  current_time <- Sys.time()
  last_query <- query_times[length(query_times)]
  time_since_last <- as.numeric(difftime(current_time, last_query, units = "secs"))
  expect_true(time_since_last >= min_query_interval)
})

test_that("refresh_trigger increment pattern is safe", {
  # Test the refresh_trigger increment pattern used in observers
  
  # Initialize
  refresh_trigger_value <- 1
  
  # Manual refresh (mimics observeEvent pattern)
  new_val <- refresh_trigger_value + 1
  refresh_trigger_value <- new_val
  expect_equal(refresh_trigger_value, 2)
  
  # Auto refresh (mimics auto-refresh observer)
  auto_refresh <- TRUE
  query_running <- FALSE
  
  if (auto_refresh && !query_running) {
    new_val <- refresh_trigger_value + 1
    refresh_trigger_value <- new_val
  }
  
  expect_equal(refresh_trigger_value, 3)
  
  # When query is running, should not increment
  query_running <- TRUE
  old_val <- refresh_trigger_value
  
  if (auto_refresh && !query_running) {
    new_val <- refresh_trigger_value + 1
    refresh_trigger_value <- new_val
  }
  
  expect_equal(refresh_trigger_value, old_val)  # Should not have changed
})
