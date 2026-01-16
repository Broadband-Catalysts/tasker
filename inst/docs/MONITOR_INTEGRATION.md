# Process Reporter Monitor Integration - Implementation Complete

## Overview

The Tasker Monitor has been updated to use database-driven process metrics instead of direct `ps` package calls. This enables cross-container monitoring where the Shiny app runs in Docker while tasks execute on the host.

## What Changed

### 1. Database Schema Updates

**New View: `current_task_status_with_metrics`**
- Combines `current_task_status` with latest process metrics
- Includes CPU%, memory, child process counts, metrics age, and error status
- Available in both PostgreSQL and SQLite schemas

**Location:**
- `/inst/sql/postgresql/create_schema.sql`
- `/inst/sql/sqlite/create_schema.sql`

### 2. R API Updates

**Modified: `get_task_status()`**
- Now queries `current_task_status_with_metrics` instead of `current_task_status`
- Returns comprehensive process metrics for all tasks
- **New columns returned:**
  - `cpu_percent` - Main process CPU usage
  - `memory_mb` - Main process memory (RSS)
  - `memory_percent` - Memory usage percentage
  - `child_count` - Number of child processes
  - `child_total_cpu_percent` - Sum of CPU% across all children
  - `child_total_memory_mb` - Sum of memory across all children
  - `is_alive` - Process alive status from metrics
  - `collection_error` - TRUE if metrics collection failed
  - `metrics_error_message` - Error details if collection failed
  - `metrics_error_type` - Error classification
  - `metrics_timestamp` - When metrics were last collected
  - `metrics_age_seconds` - Age of metrics in seconds

### 3. Shiny Monitor UI Updates

**Enhanced Process Status Display** (`build_process_status_html()`)

**Before:**
- Used direct `ps::ps_is_running()` calls to check process status
- Basic CPU/Memory display (if available)
- Process count (unclear meaning)

**After:**
- Uses database `is_alive` field from process metrics
- Comprehensive resource display:
  - Main process CPU% and Memory (with percentage)
  - Child process count with aggregated CPU% and Memory
  - Metrics update timestamp (age in seconds)
- Smart error handling with priority:
  1. Collection errors (highest priority - red banner)
  2. Stale metrics (>30 seconds - yellow banner)
  3. Process dead (from database - red banner)
  4. Missing metrics (gray text warning)

**New UI Features:**

1. **Error Banners**
   - **Collection Error:** Shows when metrics collection fails
   - **Stale Metrics Warning:** Appears when metrics are >30 seconds old
   - **Process Dead Warning:** Shows when database indicates process not alive

2. **Enhanced Metrics Display**
   ```
   Main CPU: 15.2%
   Main Memory: 245.3 MB (2.1%)
   Child Processes: 8 children (95.3% CPU) (1234.5 MB RAM)
   Metrics Updated: 5s ago
   ```

3. **Missing Metrics Warning**
   - Shows red text when task is RUNNING but no metrics available
   - Indicates Process Reporter may not be running

**Removed:**
- Direct `ps` package dependency
- `ps::ps_is_running()` calls
- Manual PID validation

### 4. CSS Styling

**Added: `.process-warning-banner`**
- Yellow background for stale metrics warnings
- Distinct from error banners (uses orange icon color)

**Location:** `/inst/shiny/www/styles.css`

## Database Migration

### For Existing Installations

If you have an existing tasker database, you need to update the schema to add the new view:

**PostgreSQL:**
```sql
-- Run this in your database
CREATE OR REPLACE VIEW tasker.current_task_status_with_metrics AS
SELECT 
    cts.*,
    pm.cpu_percent,
    pm.memory_mb,
    pm.memory_percent,
    pm.child_count,
    pm.child_total_cpu_percent,
    pm.child_total_memory_mb,
    pm.is_alive,
    pm.collection_error,
    pm.error_message AS metrics_error_message,
    pm.error_type AS metrics_error_type,
    pm.timestamp AS metrics_timestamp,
    EXTRACT(EPOCH FROM (NOW() - pm.timestamp))::INTEGER AS metrics_age_seconds
FROM tasker.current_task_status cts
LEFT JOIN LATERAL (
    SELECT *
    FROM tasker.process_metrics
    WHERE process_metrics.run_id = cts.run_id
    ORDER BY timestamp DESC
    LIMIT 1
) pm ON TRUE;
```

**SQLite:**
```sql
CREATE VIEW IF NOT EXISTS current_task_status_with_metrics AS
SELECT 
    cts.*,
    pm.cpu_percent,
    pm.memory_mb,
    pm.memory_percent,
    pm.child_count,
    pm.child_total_cpu_percent,
    pm.child_total_memory_mb,
    pm.is_alive,
    pm.collection_error,
    pm.error_message AS metrics_error_message,
    pm.error_type AS metrics_error_type,
    pm.timestamp AS metrics_timestamp,
    CAST((julianday('now') - julianday(pm.timestamp)) * 86400 AS INTEGER) AS metrics_age_seconds
FROM current_task_status cts
LEFT JOIN process_metrics pm ON pm.run_id = cts.run_id 
    AND pm.timestamp = (
        SELECT MAX(timestamp) 
        FROM process_metrics pm2 
        WHERE pm2.run_id = cts.run_id
    );
```

**Or use R:**
```r
# Recreate schema (WARNING: This will drop and recreate all views)
tasker::setup_tasker_db(force = TRUE)

# Ensure process reporter tables exist
tasker::setup_process_reporter_schema()
```

## Testing

A test script is provided to verify the integration:

```r
# Run from tasker-dev project root
source("tests/manual/test_monitor_integration.R")
```

**What it tests:**
1. Process reporter schema exists
2. `current_task_status_with_metrics` view is available
3. `get_task_status()` returns metrics columns
4. Process reporter is running and healthy

## Usage

### For Users

No changes needed! The monitor will automatically:
- Display process metrics when available
- Show warnings if Process Reporter isn't running
- Alert on stale or failed metrics collection

### For Developers

**Accessing metrics in custom code:**
```r
library(tasker)

# Get task status with metrics
status <- get_task_status(status = "RUNNING")

# Access new metric fields
for (i in 1:nrow(status)) {
  task <- status[i, ]
  
  cat(sprintf("Task: %s/%s\n", task$stage_name, task$task_name))
  
  if (!is.na(task$cpu_percent)) {
    cat(sprintf("  CPU: %.1f%%\n", task$cpu_percent))
    cat(sprintf("  Memory: %.1f MB (%.1f%%)\n", 
                task$memory_mb, task$memory_percent))
    cat(sprintf("  Children: %d (%.1f%% CPU, %.1f MB)\n",
                task$child_count, 
                task$child_total_cpu_percent,
                task$child_total_memory_mb))
    cat(sprintf("  Metrics age: %d seconds\n", task$metrics_age_seconds))
  } else if (task$status %in% c("RUNNING", "STARTED")) {
    cat("  No metrics available\n")
  }
  
  if (isTRUE(task$collection_error)) {
    cat(sprintf("  ERROR: %s\n", task$metrics_error_message))
  }
}
```

## Benefits

1. **Cross-Container Compatibility** - Monitor runs in Docker, tasks on host
2. **No Direct Process Access** - Monitor doesn't need `/proc` access
3. **Historical Context** - Shows when metrics were last collected
4. **Better Error Visibility** - Clear warnings for collection issues
5. **Child Process Insight** - See parallel worker resource usage
6. **Stale Detection** - Alerts when metrics haven't updated recently
7. **Database-Driven** - All process info centralized in database

## Known Limitations

1. **Requires Process Reporter** - Metrics only available if reporter is running
2. **Metrics Lag** - Up to 10 seconds delay (default collection interval)
3. **No Historical Charts** - UI shows current metrics only (planned for Phase 4)
4. **No Direct Kill** - Can't kill processes from monitor (security feature)

## Future Enhancements (Phase 4)

- [ ] Historical metrics time series charts
- [ ] Resource threshold alerting (OOM warnings)
- [ ] Multi-host dashboard view
- [ ] Metrics export/reporting
- [ ] Process tree visualization

## Files Modified

1. `/inst/sql/postgresql/create_schema.sql` - Added view
2. `/inst/sql/sqlite/create_schema.sql` - Added view
3. `/R/get_task_status.R` - Query new view
4. `/inst/shiny/server.R` - Database-driven metrics display
5. `/inst/shiny/www/styles.css` - Warning banner styles

## Files Added

1. `/tests/manual/test_monitor_integration.R` - Integration test script
2. `/inst/docs/MONITOR_INTEGRATION.md` - This document

## Compatibility

- **Backward Compatible:** Yes - works without Process Reporter (shows warnings)
- **Schema Migration Required:** Yes - add new view to existing databases
- **Breaking Changes:** None - all changes additive

## Support

For issues or questions:
1. Check that Process Reporter schema is installed: `setup_process_reporter_schema()`
2. Verify reporter is running: `get_process_reporter_status()`
3. Run integration test: `source("tests/manual/test_monitor_integration.R")`
4. Check Shiny console for errors when loading monitor
