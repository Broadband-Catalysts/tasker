#!/usr/bin/env Rscript
#
# Example: Using tasker with the simplified API (v2.0)
#
# This example demonstrates the new context-based API that reduces
# boilerplate code and makes parallel processing much simpler.
#

library(tasker)

# ============================================================================
# Configuration is now automatic - no need to call tasker_config() explicitly!
# (It will auto-discover .tasker.yml or use environment variables)
# ============================================================================

# Create schema if needed (only needs to be done once)
if (!DBI::dbExistsTable(get_db_connection(), DBI::SQL("tasker.stages"))) {
  create_schema()
}

# Register pipeline tasks
cat("Registering tasks...\n")
register_task(stage = "EXTRACT", name = "Download Data", type = "R",
             description = "Download data from API")
register_task(stage = "TRANSFORM", name = "Clean Data", type = "R",
             description = "Clean and validate data")
register_task(stage = "LOAD", name = "Load to Database", type = "R",
             description = "Load processed data to database")


# ============================================================================
# NEW API: Context-based workflow (no run_id passing!)
# ============================================================================

cat("\n=== Starting Data Cleaning Task (Simplified API) ===\n")

# Start task - it becomes the active context automatically
run_id <- task_start("TRANSFORM", "Clean Data")  # Store run_id for .Last check

.Last <- function() {
  if (exists("run_id") && !is.null(run_id)) {
    task_fail(error_message = "Script terminated unexpectedly")
  }
}

# ---- Subtask 1: Validate data (auto-numbered!) ----
cat("\nSubtask 1: Validating data...\n")
subtask_start("Validate Data", items_total = 100)  # Automatically subtask 1!

for (i in 1:100) {
  Sys.sleep(0.02)  # Simulate work
  if (i %% 20 == 0) {
    subtask_update(
      status = "RUNNING",
      percent = i,
      items_complete = i,
      message = sprintf("Validated %d/100 records", i)
    )  # No run_id or subtask_number needed!
  }
}

subtask_complete("All records validated")  # No parameters needed!

# ---- Subtask 2: Remove duplicates (auto-numbered!) ----
cat("\nSubtask 2: Removing duplicates...\n")
subtask_start("Remove Duplicates", items_total = 50)  # Automatically subtask 2!

for (i in 1:50) {
  Sys.sleep(0.03)  # Simulate work
  if (i %% 10 == 0) {
    subtask_update(
      status = "RUNNING",
      percent = (i/50)*100,
      items_complete = i,
      message = sprintf("Processed %d/50 groups", i)
    )
  }
}

subtask_complete("Duplicates removed")

# ---- Subtask 3: Parallel processing (simplified cluster setup!) ----
cat("\nSubtask 3: Standardizing formats (parallel)...\n")
subtask_start("Standardize Formats", items_total = 75)  # Automatically subtask 3!

# NEW: One-line cluster setup!
cl <- tasker_cluster(ncores = 4)  # Automatically exports context!

# Worker function - no run_id needed, uses context!
process_item <- function(i) {
  Sys.sleep(0.02)  # Simulate work
  
  # Atomic increment - no run_id or subtask_number needed!
  subtask_increment(increment = 1, quiet = TRUE)
  
  return(sprintf("Item %d processed", i))
}

# Process in parallel
results <- parallel::parLapplyLB(cl, 1:75, process_item)

# Clean shutdown
stop_tasker_cluster(cl)

subtask_complete("Formats standardized")

# Update overall task progress
task_update(status = "RUNNING", overall_percent = 100,
           message = "All subtasks completed, finalizing")

# Complete the task
Sys.sleep(0.5)

rm(.Last)
task_complete("Data cleaning completed successfully")

cat("\n=== Task Completed ===\n")


# ============================================================================
# Show current status
# ============================================================================

cat("\nCurrent task status:\n")
print(get_task_status())

cat("\nSubtask details:\n")
print(get_subtask_progress())  # Can omit run_id - uses context!

cat("\n=== Simplified API Example Completed ===\n")


# ============================================================================
# COMPARISON: Old API vs New API
# ============================================================================

cat("\n=== API Comparison ===\n")
cat("\nOLD API (verbose):\n")
cat("  run_id <- task_start('STAGE', 'Task', total_subtasks = 3)\n")
cat("  subtask_start(run_id, 1, 'Load', items_total = 100)\n")
cat("  subtask_update(run_id, 1, 'RUNNING', items_complete = 50)\n")
cat("  subtask_complete(run_id, 1)\n")
cat("  task_complete(run_id)\n")

cat("\nNEW API (clean):\n")
cat("  task_start('STAGE', 'Task')\n")
cat("  subtask_start('Load', items_total = 100)  # Auto-numbered!\n")
cat("  subtask_update(status = 'RUNNING', items_complete = 50)\n")
cat("  subtask_complete()\n")
cat("  task_complete()\n")

cat("\nBOILERPLATE REDUCTION: ~50-70%\n")


# ============================================================================
# PARALLEL PROCESSING COMPARISON
# ============================================================================

cat("\n=== Parallel Processing Comparison ===\n")
cat("\nOLD API (complex):\n")
cat("  cl <- makeCluster(16)\n")
cat("  clusterEvalQ(cl, { library(tasker); devtools::load_all(); NULL })\n")
cat("  clusterExport(cl, c('run_id', 'var1', 'var2'), envir = environment())\n")
cat("  clusterEvalQ(cl, { con <- dbConnectBBC(mode='rw'); NULL })\n")
cat("  results <- parLapply(cl, items, worker_function)\n")
cat("  stopCluster(cl)\n")

cat("\nNEW API (simple):\n")
cat("  cl <- tasker_cluster(ncores = 16, export = c('var1', 'var2'),\n")
cat("                       setup_expr = quote({ devtools::load_all(); con <- dbConnectBBC(mode='rw') }))\n")
cat("  results <- parLapply(cl, items, worker_function)\n")
cat("  stop_tasker_cluster(cl)\n")

cat("\nCLUSTER SETUP REDUCTION: 6 lines -> 1 line\n")


# ============================================================================
# Advanced: Mixing old and new API (backward compatible!)
# ============================================================================

cat("\n=== Backward Compatibility ===\n")
cat("The new API is fully backward compatible!\n")
cat("You can mix old-style explicit parameters with new-style context:\n\n")

# Start a task but get the run_id explicitly
run_id_explicit <- task_start("EXTRACT", "Download Data", .active = FALSE)

# Use explicit run_id
subtask_start(run_id_explicit, 1, "Download files")
subtask_complete(run_id_explicit, 1)
task_complete(run_id_explicit)

cat("✓ Mixed API usage works perfectly!\n")

cat("\n=== Example Complete ===\n")
