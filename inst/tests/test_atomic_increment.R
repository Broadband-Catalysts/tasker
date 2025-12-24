#!/usr/bin/env Rscript

# Test atomic increment functionality
# This script verifies that subtask_increment() works correctly in parallel
#
# NOTE: This test should be run from a directory with tasker configured
# (e.g., /home/warnes/src/fccData)

# Load latest tasker code
devtools::load_all('/home/warnes/src/tasker')

library(parallel)

cat("Testing subtask_increment() with parallel workers...\n")
cat("Working directory:", getwd(), "\n")

# Register test stage and task if not already present
conn <- get_db_connection()
on.exit(DBI::dbDisconnect(conn), add = TRUE)

# Check if TEST stage exists
test_stage <- DBI::dbGetQuery(conn, 
  "SELECT stage_id FROM tasker.stages WHERE stage_name = 'TEST'")

if (nrow(test_stage) == 0) {
  cat("Creating TEST stage...\n")
  DBI::dbExecute(conn,
    "INSERT INTO tasker.stages (stage_name, stage_order, description)
     VALUES ('TEST', 999, 'Test stage for unit tests')
     ON CONFLICT (stage_name) DO NOTHING")
}

# Check if test task exists
test_task <- DBI::dbGetQuery(conn,
  "SELECT task_id FROM tasker.tasks t
   JOIN tasker.stages s ON t.stage_id = s.stage_id
   WHERE s.stage_name = 'TEST' AND t.task_name = 'Atomic Increment Test'")

if (nrow(test_task) == 0) {
  cat("Registering test task...\n")
  register_task(
    stage = "TEST",
    name = "Atomic Increment Test",
    type = "R",
    description = "Tests parallel atomic counter increments",
    script_path = "inst/tests",
    script_filename = "test_atomic_increment.R",
    task_order = 1
  )
}

# Start a test task
run_id <- task_start("TEST", "Atomic Increment Test", 
                     total_subtasks = 1,
                     quiet = FALSE)

cat("Run ID:", run_id, "\n")

# Start subtask
subtask_start(run_id, 1, "Parallel increment test", items_total = 100)

# Worker function that increments counter
increment_worker <- function(i, run_id) {
  # Simulate some work
  Sys.sleep(runif(1, 0.01, 0.05))
  
  # Atomically increment counter
  tasker::subtask_increment(run_id, 1, increment = 1, quiet = TRUE)
  
  return(i)
}

# Test with parallel workers
n_workers <- 4
n_items <- 100

cat(sprintf("Starting %d workers to process %d items...\n", n_workers, n_items))

cl <- makeCluster(n_workers)
clusterExport(cl, c("run_id"), envir = environment())
clusterEvalQ(cl, {
  devtools::load_all("/home/warnes/src/tasker")
  NULL  # Prevent serialization
})

# Process items in parallel
results <- parLapply(cl, 1:n_items, increment_worker, run_id = run_id)

stopCluster(cl)

# Check final count
progress <- get_subtask_progress(run_id)
final_count <- progress$items_complete[1]

cat(sprintf("\nExpected count: %d\n", n_items))
cat(sprintf("Actual count: %d\n", final_count))

# Complete subtask
subtask_complete(run_id, 1, message = sprintf("Processed %d items", final_count))

# End task
task_complete(run_id, message = sprintf("Test %s", 
                                        if (final_count == n_items) "PASSED ✅" else "FAILED ❌"))

# Verify result
if (final_count == n_items) {
  cat("\n✅ TEST PASSED: Atomic increment works correctly!\n")
  cat(sprintf("   All %d increments were properly counted.\n", n_items))
  quit(status = 0)
} else {
  cat("\n❌ TEST FAILED: Race condition detected!\n")
  cat(sprintf("   Expected %d but got %d (lost %d increments)\n", 
              n_items, final_count, n_items - final_count))
  quit(status = 1)
}
