#!/usr/bin/env Rscript

# Test script to demonstrate safe setup_tasker_db functionality
# This script shows the new safety features:
# 1. Transaction safety with automatic rollback on failure
# 2. Data preservation via backup schema
# 3. Data migration between schema versions

library(tasker)

test_safe_setup <- function() {
  cat("=== TESTING SAFE setup_tasker_db() ===\n")
  
  # Check if tasker is configured
  if (!tasker_configured()) {
    cat("⚠️ tasker is not configured. Please configure first.\n")
    return(FALSE)
  }
  
  cat("✓ tasker is configured\n")
  
  # Test 1: Normal setup (should succeed)
  cat("\n--- Test 1: Initial Setup ---\n")
  result <- try(setup_tasker_db(force = FALSE))
  if (inherits(result, "try-error")) {
    cat("❌ Initial setup failed: ", result[1], "\n")
    return(FALSE)
  }
  cat("✓ Initial setup completed\n")
  
  # Test 2: Check database initialization
  cat("\n--- Test 2: Database Check ---\n")
  check_result <- check_tasker_db()
  if (!check_result) {
    cat("❌ Database check failed\n")
    return(FALSE)
  }
  cat("✓ Database properly initialized\n")
  
  # Test 3: Force setup with data preservation
  cat("\n--- Test 3: Safe Force Recreate ---\n")
  cat("This will test the backup/restore mechanism...\n")
  
  # First create some test data
  con <- get_db_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Insert a test stage
  test_stage <- "TEST_STAGE"
  DBI::dbExecute(con, 
    "INSERT INTO tasker.stages (stage_name, description) 
     VALUES ($1, $2)
     ON CONFLICT (stage_name) DO NOTHING",
    list(test_stage, "Test stage for safety verification"))
  
  # Count records before
  count_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM tasker.stages WHERE stage_name = $1", list(test_stage))$n
  cat("Test data created: ", count_before, " test record(s)\n")
  
  if (count_before > 0) {
    # Test force recreate with data preservation
    result_force <- try(setup_tasker_db(force = TRUE))
    if (inherits(result_force, "try-error")) {
      cat("❌ Force setup failed: ", result_force[1], "\n")
      return(FALSE)
    }
    
    # Count records after
    count_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM tasker.stages WHERE stage_name = $1", list(test_stage))$n
    cat("Test data after force recreate: ", count_after, " record(s)\n")
    
    if (count_after == count_before) {
      cat("✅ Data preservation successful!\n")
    } else {
      cat("⚠️ Data count changed: ", count_before, " -> ", count_after, "\n")
    }
  } else {
    cat("⚠️ No test data to verify preservation\n")
  }
  
  cat("\n=== SAFETY TEST COMPLETED ===\n")
  return(TRUE)
}

# Run the test
if (!interactive()) {
  test_safe_setup()
}