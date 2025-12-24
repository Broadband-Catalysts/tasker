# Parallel Processing with Tasker

## Overview

When using parallel processing (e.g., `parLapply`, `clusterApply`, `mclapply`) with tasker, special care must be taken to avoid race conditions when updating subtask progress.

## The Problem: Race Conditions

### Non-Atomic Updates

The `subtask_update()` function **sets** the `items_complete` value:

```r
subtask_update(run_id, 1, "RUNNING", items_complete = 10)
```

If multiple parallel workers call this simultaneously, they will overwrite each other's values:

```
Time  Worker A              Worker B              Database
----  -------------------   -------------------   ----------
T1    Read: count = 10      
T2    Calculate: 10 + 1 = 11
T3                          Read: count = 10      count = 10
T4    Write: count = 11                           count = 11
T5                          Calculate: 10 + 1 = 11
T6                          Write: count = 11     count = 11  ❌ Should be 12!
```

### The Solution: Atomic Increments

Use `subtask_increment()` instead, which performs database-level atomic increments:

```sql
UPDATE subtask_progress 
SET items_complete = COALESCE(items_complete, 0) + increment
WHERE run_id = ? AND subtask_number = ?
```

This ensures that increments are atomic at the database level, preventing race conditions.

## Usage Patterns

### Pattern 1: Simple Counter Increment

```r
# Main process
run_id <- task_start("STATIC", "Process Counties")
subtask_start(run_id, 1, "Process all counties", items_total = 3143)

# Worker function
process_county <- function(county_fp) {
  # ... do work ...
  
  # Atomically increment counter (safe for parallel execution)
  subtask_increment(run_id, 1, increment = 1)
  
  return(result)
}

# Parallel execution
cl <- makeCluster(16)
clusterExport(cl, "run_id")
results <- parLapplyLB(cl, county_list, process_county)
stopCluster(cl)

# Complete subtask
subtask_complete(run_id, 1, message = "All counties processed")
```

### Pattern 2: Batch Increment

```r
# Worker function that processes multiple items
process_batch <- function(batch) {
  results <- list()
  completed <- 0
  
  for (item in batch) {
    result <- process_item(item)
    results[[length(results) + 1]] <- result
    completed <- completed + 1
    
    # Increment every 10 items to reduce database calls
    if (completed %% 10 == 0) {
      subtask_increment(run_id, 1, increment = 10)
      completed <- 0
    }
  }
  
  # Increment remaining items
  if (completed > 0) {
    subtask_increment(run_id, 1, increment = completed)
  }
  
  return(results)
}
```

### Pattern 3: Progress with Percent Updates

```r
# Main process
run_id <- task_start("ANNUAL_SEPT", "Load BDC Data")
subtask_start(run_id, 1, "Download state files", items_total = 56)

# Worker function
download_state <- function(state_fp, total_states) {
  # ... download and process ...
  
  # Atomically increment count
  subtask_increment(run_id, 1, increment = 1)
  
  # Separately update percent (main process should do this)
  # Workers should only increment counters
  
  return(result)
}

# Monitor progress in main process
cl <- makeCluster(16)
clusterExport(cl, "run_id")

# Launch async workers
results <- parLapplyLB(cl, state_list, download_state)

# OR: Monitor progress while workers run
# (requires background workers, not blocking parLapply)

stopCluster(cl)
subtask_complete(run_id, 1)
```

## Database Connection Setup for Workers

Each parallel worker needs its own database connection:

```r
cl <- makeCluster(16)
tmp <- clusterEvalQ(cl, devtools::load_all())

# CRITICAL: Return NULL to prevent serialization errors
tmp <- clusterEvalQ(cl, {
  con <- dbConnectBBC(mode="rw")
  NULL  # Prevents "Error in unserialize(socklist[[n]]) : error reading from connection"
})

# Export variables needed by workers
clusterExport(cl, list("run_id", "dateStr", "other_vars"))
```

**Why return NULL?** Database connection objects contain file descriptors that cannot be serialized across R processes. Returning `NULL` prevents `clusterEvalQ()` from trying to return the connection object.

## API Reference

### subtask_increment()

Atomically increment the `items_complete` counter for a subtask.

**Parameters:**
- `run_id`: Run ID from `task_start()`
- `subtask_number`: Subtask number
- `increment`: Number of items to add (default: 1)
- `quiet`: Suppress messages (default: TRUE, recommended for parallel workers)
- `conn`: Database connection (optional, creates new connection if NULL)

**Returns:** TRUE on success

**Thread Safety:** ✅ Safe for concurrent use by multiple workers

**Example:**
```r
subtask_increment(run_id, 1, increment = 1)
subtask_increment(run_id, 2, increment = 5)  # Increment by 5
```

### subtask_update()

Set the `items_complete` value (absolute, not incremental).

**Parameters:**
- `run_id`: Run ID from `task_start()`
- `subtask_number`: Subtask number
- `status`: "RUNNING", "COMPLETED", "FAILED", "SKIPPED"
- `items_complete`: Absolute count (optional)
- `percent`: 0-100 (optional)
- `message`: Progress message (optional)
- `quiet`: Suppress messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** TRUE on success

**Thread Safety:** ⚠️ **NOT safe** for concurrent counter updates. Use `subtask_increment()` for parallel workers.

**Example:**
```r
subtask_update(run_id, 1, "RUNNING", items_complete = 50, percent = 50)
```

### subtask_complete()

Mark a subtask as completed (wrapper around `subtask_update()`).

**Parameters:**
- `run_id`: Run ID from `task_start()`
- `subtask_number`: Subtask number
- `items_completed`: Final count (optional)
- `message`: Completion message (optional)
- `quiet`: Suppress messages (default: FALSE)
- `conn`: Database connection (optional)

**Thread Safety:** ⚠️ Not intended for concurrent use

**Example:**
```r
subtask_complete(run_id, 1, items_completed = 3143, message = "All counties processed")
```

## Best Practices

1. **Use `subtask_increment()` in parallel workers** - Never use `subtask_update()` with `items_complete` parameter from parallel workers

2. **Create per-worker database connections** - Each worker needs its own connection, created via `clusterEvalQ()`

3. **Return NULL from connection creation** - Prevents serialization errors:
   ```r
   tmp <- clusterEvalQ(cl, { con <- dbConnectBBC(mode="rw"); NULL })
   ```

4. **Batch increments to reduce database calls** - Increment every N items instead of every item

5. **Set `quiet=TRUE` for worker increments** - Reduces log noise from parallel workers

6. **Use main process for status updates** - Let main process call `subtask_update()` for status/percent changes

7. **Initialize with `items_total`** - Set expected total in `subtask_start()` for accurate progress tracking

## Migration Guide

### Before (Race Condition Risk)

```r
process_county <- function(county_fp, current_count) {
  # ... work ...
  subtask_update(run_id, 1, "RUNNING", items_complete = current_count + 1)  # ❌ Race condition
}

results <- parLapplyLB(cl, county_list, process_county)
```

### After (Thread Safe)

```r
process_county <- function(county_fp) {
  # ... work ...
  subtask_increment(run_id, 1, increment = 1)  # ✅ Atomic increment
}

results <- parLapplyLB(cl, county_list, process_county)
```

## Testing

Test parallel processing with a small worker count first:

```r
# Test with 2 workers
cl <- makeCluster(2)
test_results <- parLapply(cl, 1:100, process_function)
stopCluster(cl)

# Check that items_complete = 100 (not less due to race condition)
progress <- get_subtask_progress(run_id)
stopifnot(progress$items_complete[1] == 100)
```

## See Also

- [GitHub Copilot Instructions](.github/copilot-instructions.md) - Parallel processing patterns for fccData
- [inst/examples/example_pipeline.R](inst/examples/example_pipeline.R) - Sequential subtask example
- [R/subtask_update.R](../R/subtask_update.R) - Implementation details
