#!/usr/bin/env Rscript
#
# Example: Using tasker to track a data processing pipeline
#

library(tasker)

# Configure tasker (will auto-discover .tasker.yml or use environment variables)
tasker_config()

# Create schema if needed
create_schema()

# Register pipeline tasks
cat("Registering tasks...\n")
register_task(stage = "EXTRACT", name = "Download Data", type = "R",
             description = "Download data from API")
register_task(stage = "TRANSFORM", name = "Clean Data", type = "R",
             description = "Clean and validate data")
register_task(stage = "LOAD", name = "Load to Database", type = "R",
             description = "Load processed data to database")

# Simulate running the "Clean Data" task
cat("\n=== Starting Data Cleaning Task ===\n")
run_id <- task_start("TRANSFORM", "Clean Data", total_subtasks = 3,
                     message = "Beginning data cleaning process")

.Last <- function() {
  if (exists("run_id") && !is.null(run_id)) {
    task_fail(error_message = "Script terminated unexpectedly")
  }
}

# Subtask 1: Validate data
cat("\nSubtask 1: Validating data...\n")
subtask_start(run_id, 1, "Validate Data", items_total = 100)

for (i in 1:100) {
  Sys.sleep(0.02)  # Simulate work
  if (i %% 20 == 0) {
    subtask_update(run_id, 1, "RUNNING",
                  percent = i,
                  items_complete = i,
                  message = sprintf("Validated %d/100 records", i))
  }
}

subtask_complete(run_id, 1, "All records validated")

# Subtask 2: Remove duplicates
cat("\nSubtask 2: Removing duplicates...\n")
subtask_start(run_id, 2, "Remove Duplicates", items_total = 50)

for (i in 1:50) {
  Sys.sleep(0.03)  # Simulate work
  if (i %% 10 == 0) {
    subtask_update(run_id, 2, "RUNNING",
                  percent = (i/50)*100,
                  items_complete = i,
                  message = sprintf("Processed %d/50 groups", i))
  }
}

subtask_complete(run_id, 2, "Duplicates removed")

# Subtask 3: Standardize formats
cat("\nSubtask 3: Standardizing formats...\n")
subtask_start(run_id, 3, "Standardize Formats", items_total = 75)

for (i in 1:75) {
  Sys.sleep(0.02)  # Simulate work
  if (i %% 15 == 0) {
    subtask_update(run_id, 3, "RUNNING",
                  percent = (i/75)*100,
                  items_complete = i,
                  message = sprintf("Standardized %d/75 fields", i))
  }
}

subtask_complete(run_id, 3, "Formats standardized")

# Update overall task progress
task_update(run_id, status = "RUNNING",
           overall_percent = 100,
           message = "All subtasks completed, finalizing")

# Complete the task
Sys.sleep(0.5)

rm(.Last)
task_complete(run_id, "Data cleaning completed successfully")

cat("\n=== Task Completed ===\n")

# Show current status
cat("\nCurrent task status:\n")
print(get_task_status())

cat("\nSubtask details:\n")
print(get_subtask_progress(run_id))

cat("\n=== Example completed ===\n")
