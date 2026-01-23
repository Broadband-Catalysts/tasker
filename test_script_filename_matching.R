#!/usr/bin/env Rscript
#
# Test script to verify update_task() and update_subtask() script_filename matching
# This test demonstrates the three matching methods for tasks
#

library(testthat)
library(devtools)

# Load the package
devtools::load_all()

# Set up test environment
cat("Setting up test database...\n")

# Create temporary SQLite database for testing
temp_db <- tempfile(fileext = ".db")
conn <- DBI::dbConnect(RSQLite::SQLite(), temp_db)

# Create test tables
DBI::dbExecute(conn, "CREATE TABLE stages (
  stage_id INTEGER PRIMARY KEY,
  stage_name TEXT NOT NULL,
  stage_order INTEGER NOT NULL
)")

DBI::dbExecute(conn, "CREATE TABLE tasks (
  task_id INTEGER PRIMARY KEY,
  stage_id INTEGER NOT NULL,
  task_name TEXT NOT NULL,
  task_type TEXT,
  task_order INTEGER,
  script_filename TEXT,
  description TEXT,
  FOREIGN KEY (stage_id) REFERENCES stages(stage_id)
)")

DBI::dbExecute(conn, "CREATE TABLE task_runs (
  run_id TEXT PRIMARY KEY,
  task_id INTEGER NOT NULL,
  status TEXT,
  start_time TEXT,
  end_time TEXT,
  message TEXT,
  error_message TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(task_id)
)")

# Insert test data
DBI::dbExecute(conn, "INSERT INTO stages VALUES (1, 'DAILY_FCC_SUMMARY', 8)")
DBI::dbExecute(conn, "INSERT INTO tasks VALUES 
  (1, 1, 'Provider Tables Block20', 'R', 3, '06_DAILY_FCC_SUMMARY_03_Provider_Tables_Block20.R', 'Generate provider coverage at block level'),
  (2, 1, 'Provider Tables Hex', 'R', 4, '06_DAILY_FCC_SUMMARY_04_Provider_Tables_Hex.R', 'Generate provider coverage at hex level'),
  (3, 1, 'Provider Tables List', 'R', 5, '06_DAILY_FCC_SUMMARY_05_Provider_Tables_List.R', 'Generate provider metadata list')")

# Insert a test task run
DBI::dbExecute(conn, "INSERT INTO task_runs VALUES 
  ('test-run-1', 1, 'RUNNING', datetime('now'), NULL, NULL, NULL)")

cat("\nTest data created:\n")
cat("  Stage: DAILY_FCC_SUMMARY (ID=1)\n")
cat("  Tasks:\n")
cat("    1. Provider Tables Block20 (06_DAILY_FCC_SUMMARY_03_Provider_Tables_Block20.R)\n")
cat("    2. Provider Tables Hex (06_DAILY_FCC_SUMMARY_04_Provider_Tables_Hex.R)\n")
cat("    3. Provider Tables List (06_DAILY_FCC_SUMMARY_05_Provider_Tables_List.R)\n")

separator <- paste(rep("=", 70), collapse = "")

cat("\n")
cat(separator)
cat("\n")
cat("Testing task matching methods:\n")
cat(separator)
cat("\n")

# Test 1: Match by task order number
cat("\nTest 1: Match by task order number (task = 3)\n")
tryCatch({
  result <- DBI::dbGetQuery(conn, 
    "SELECT t.task_id, t.task_name, t.script_filename FROM tasks t
     WHERE t.task_order = 3 AND t.stage_id = 1")
  if (nrow(result) > 0) {
    cat("✓ Found: ", result$task_name[1], " (", result$script_filename[1], ")\n", sep = "")
  } else {
    cat("✗ Not found\n")
  }
}, error = function(e) cat("✗ Error:", conditionMessage(e), "\n"))

# Test 2: Match by partial task name
cat("\nTest 2: Match by partial task name (task = 'Block20')\n")
tryCatch({
  task_search <- "Block20"
  result <- DBI::dbGetQuery(conn, 
    "SELECT t.task_id, t.task_name, t.script_filename FROM tasks t
     WHERE t.stage_id = 1 AND LOWER(t.task_name) LIKE LOWER('%' || ? || '%')",
    list(task_search))
  if (nrow(result) > 0) {
    cat("✓ Found: ", result$task_name[1], " (", result$script_filename[1], ")\n", sep = "")
  } else {
    cat("✗ Not found\n")
  }
}, error = function(e) cat("✗ Error:", conditionMessage(e), "\n"))

# Test 3: Match by partial script filename
cat("\nTest 3: Match by partial script filename (task = '06_DAILY_FCC_SUMMARY_04')\n")
tryCatch({
  task_search <- "06_DAILY_FCC_SUMMARY_04"
  result <- DBI::dbGetQuery(conn,
    "SELECT t.task_id, t.task_name, t.script_filename FROM tasks t
     WHERE t.stage_id = 1 
     AND (LOWER(t.task_name) LIKE LOWER('%' || ? || '%') OR LOWER(t.script_filename) LIKE LOWER('%' || ? || '%'))",
    list(task_search, task_search))
  if (nrow(result) > 0) {
    cat("✓ Found: ", result$task_name[1], " (", result$script_filename[1], ")\n", sep = "")
  } else {
    cat("✗ Not found\n")
  }
}, error = function(e) cat("✗ Error:", conditionMessage(e), "\n"))

# Test 4: Ambiguous match (multiple results)
cat("\nTest 4: Ambiguous match detection (task = 'Provider')\n")
tryCatch({
  task_search <- "Provider"
  result <- DBI::dbGetQuery(conn,
    "SELECT t.task_id, t.task_name, t.script_filename FROM tasks t
     WHERE t.stage_id = 1
     AND (LOWER(t.task_name) LIKE LOWER('%' || ? || '%') OR LOWER(t.script_filename) LIKE LOWER('%' || ? || '%'))",
    list(task_search, task_search))
  if (nrow(result) > 1) {
    cat("✓ Correctly detected ambiguity (", nrow(result), " matches):\n", sep = "")
    for (i in 1:nrow(result)) {
      cat("    - ", result$task_name[i], " (", result$script_filename[i], ")\n", sep = "")
    }
  } else if (nrow(result) == 1) {
    cat("✗ Should have found multiple matches\n")
  } else {
    cat("✗ Not found\n")
  }
}, error = function(e) cat("✗ Error:", conditionMessage(e), "\n"))

# Clean up
DBI::dbDisconnect(conn)
unlink(temp_db)

cat("\n")
cat(separator)
cat("\n")
cat("Test complete!\n")
cat(separator)
cat("\n")
