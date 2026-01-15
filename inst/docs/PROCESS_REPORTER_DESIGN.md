# Process Reporter Design Specification

**Version:** 1.1  
**Date:** 2026-01-05  
**Status:** Design Approved

## Overview

The Process Reporter is a background service that collects process and resource usage information for running tasks and stores it in the database. This solves the problem of the Tasker Monitor running in a Docker container without access to process information on the host where tasks are executing.

## Problem Statement

- Tasker Monitor runs in a Docker container
- Tasks execute on the host system or other servers
- Container cannot access host process information via `/proc` or `ps`
- Need centralized process monitoring that works across container boundaries

## Solution Architecture

### Design Decisions

- **Collection Interval:** 10 seconds (balances real-time monitoring with storage efficiency)
- **Retention Policy:** Delete metrics 30 days after task completion
- **Child Process Tracking:** Aggregate summary only (count, total CPU%, total memory, etc.)
- **Deployment Model:** Auto-start on first task (no manual setup required)
- **Monitoring Mode:** Database-only (removes direct `ps` checks for cross-container compatibility)
- **Error Handling:** Record all collection errors in database and display in UI
- **Resource Metrics:** Comprehensive set including CPU, memory, I/O, file descriptors, swap, page faults

### Components

1. **Process Reporter Service** - Standalone R process that runs on each execution host
2. **Database Tables** - Store process metrics, errors, and reporter status
3. **Tasker Integration** - Auto-start reporter when tasks begin, database-only process checks
4. **Monitor Integration** - Display collected metrics and errors in Tasker Monitor UI

## Database Schema

### New Table: `process_metrics`

Stores process resource usage snapshots over time.

```sql
CREATE TABLE IF NOT EXISTS process_metrics (
    metric_id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES task_runs(run_id) ON DELETE CASCADE,
    timestamp TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Main process info
    process_id INTEGER NOT NULL,
    hostname VARCHAR(255) NOT NULL,
    is_alive BOOLEAN NOT NULL DEFAULT TRUE,
    process_start_time TIMESTAMP,         -- Process creation time for PID reuse detection
    
    -- Resource usage - CPU and Memory
    cpu_percent DECIMAL(5,2),              -- CPU usage percentage
    memory_mb DECIMAL(10,2),               -- Memory (RSS) in MB
    memory_percent DECIMAL(5,2),           -- Memory usage percentage
    memory_vms_mb DECIMAL(10,2),           -- Virtual memory size in MB
    swap_mb DECIMAL(10,2),                 -- Swap usage in MB
    
    -- Resource usage - I/O
    read_bytes BIGINT,                     -- Cumulative bytes read
    write_bytes BIGINT,                    -- Cumulative bytes written
    read_count BIGINT,                     -- Number of read operations
    write_count BIGINT,                    -- Number of write operations
    io_wait_percent DECIMAL(5,2),          -- Percentage of time waiting for I/O
    
    -- Resource usage - System
    open_files INTEGER,                    -- Number of open file descriptors
    num_fds INTEGER,                       -- Total file descriptors
    num_threads INTEGER,                   -- Number of threads in main process
    page_faults_minor BIGINT,              -- Minor page faults (no I/O)
    page_faults_major BIGINT,              -- Major page faults (disk I/O)
    num_ctx_switches_voluntary BIGINT,     -- Voluntary context switches
    num_ctx_switches_involuntary BIGINT,   -- Involuntary context switches
    
    -- Child process aggregates
    child_count INTEGER DEFAULT 0,         -- Number of child processes
    child_total_cpu_percent DECIMAL(8,2),  -- Sum of CPU% across all children
    child_total_memory_mb DECIMAL(12,2),   -- Sum of memory across all children
    
    -- Error tracking
    collection_error BOOLEAN DEFAULT FALSE,
    error_message TEXT,                    -- Error details if collection failed
    error_type VARCHAR(50),                -- Error classification (PROCESS_DIED, PERMISSION_DENIED, PS_ERROR, etc.)
    
    -- Metadata
    reporter_version VARCHAR(50),
    collection_duration_ms INTEGER,        -- Time to collect this metric
    
    CONSTRAINT process_metrics_run_timestamp_idx UNIQUE (run_id, timestamp)
);

CREATE INDEX idx_process_metrics_run_id ON process_metrics(run_id);
CREATE INDEX idx_process_metrics_timestamp ON process_metrics(timestamp DESC);
CREATE INDEX idx_process_metrics_hostname ON process_metrics(hostname);
CREATE INDEX idx_process_metrics_errors ON process_metrics(run_id, timestamp) WHERE collection_error = TRUE;
CREATE INDEX idx_process_metrics_cleanup ON process_metrics(timestamp) WHERE is_alive = FALSE;
```

### Index on `task_runs` for Active Tasks Query

```sql
-- Optimize the reporter's query for active tasks on a specific host
CREATE INDEX idx_task_runs_active_host ON task_runs(hostname, status) 
    WHERE status IN ('RUNNING', 'STARTED');
```

### Table: `process_reporter_status`

Tracks active process reporters.

```sql
CREATE TABLE IF NOT EXISTS process_reporter_status (
    reporter_id SERIAL PRIMARY KEY,
    hostname VARCHAR(255) NOT NULL UNIQUE,
    process_id INTEGER NOT NULL,
    started_at TIMESTAMP NOT NULL DEFAULT NOW(),
    last_heartbeat TIMESTAMP NOT NULL DEFAULT NOW(),
    version VARCHAR(50),
    config JSONB DEFAULT '{}'::JSONB,
    shutdown_requested BOOLEAN DEFAULT FALSE
);

-- Note: No CHECK constraint on heartbeat age - stale reporters detected via query
-- Allows recovery if reporter was hung and needs to update heartbeat

CREATE INDEX idx_reporter_hostname ON process_reporter_status(hostname);
CREATE INDEX idx_reporter_heartbeat ON process_reporter_status(last_heartbeat DESC);
```

### Table: `process_metrics_retention`

Tracks retention policy and cleanup status.

```sql
CREATE TABLE IF NOT EXISTS process_metrics_retention (
    retention_id SERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES task_runs(run_id) ON DELETE CASCADE,
    task_completed_at TIMESTAMP NOT NULL,
    metrics_delete_after TIMESTAMP NOT NULL,  -- completion + 30 days
    metrics_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP,
    metrics_count INTEGER,                    -- Number of metrics deleted
    
    CONSTRAINT unique_run_retention UNIQUE (run_id)
);

CREATE INDEX idx_retention_delete_after ON process_metrics_retention(metrics_delete_after) 
    WHERE metrics_deleted = FALSE;
```

### Modifications to `task_runs`

Add view to show latest process metrics:

```sql
-- View: task_runs_with_latest_metrics
CREATE OR REPLACE VIEW task_runs_with_latest_metrics AS
SELECT 
    tr.*,
    pm.cpu_percent,
    pm.memory_mb,
    pm.memory_percent,
    pm.child_count,
    pm.child_total_cpu_percent,
    pm.child_total_memory_mb,
    pm.is_alive,
    pm.collection_error,
    pm.error_message,
    pm.error_type,
    pm.timestamp AS metrics_timestamp,
    EXTRACT(EPOCH FROM (NOW() - pm.timestamp))::INTEGER AS metrics_age_seconds
FROM task_runs tr
LEFT JOIN LATERAL (
    SELECT *
    FROM process_metrics
    WHERE process_metrics.run_id = tr.run_id
    ORDER BY timestamp DESC
    LIMIT 1
) pm ON TRUE;
```

## R API Specification

### Core Functions

#### `start_process_reporter()`

Starts the process reporter as a background daemon.

```r
start_process_reporter <- function(
    interval_seconds = 10,
    hosts = NULL,
    config_file = NULL,
    log_file = NULL,
    daemon = TRUE,
    force = FALSE
) {
  # Args:
  #   interval_seconds: How often to collect metrics (default: 10)
  #   hosts: Optional vector of hostnames to monitor (default: all active)
  #   config_file: Path to YAML config file
  #   log_file: Path for reporter logs
  #   daemon: Run as background daemon (TRUE) or foreground (FALSE)
  #   force: If TRUE, stop existing reporter before starting new one (default: FALSE)
  
  # Single Reporter Per Host:
  #   Only one reporter should run per host. Before starting:
  #     1. Check if reporter already running via get_process_reporter_status()
  #     2. If running and heartbeat recent (<60s), return existing PID unless force=TRUE
  #     3. If running but stale (>60s), stop old reporter and start new one
  #     4. If force=TRUE, stop existing reporter first
  #   
  #   This prevents multiple reporters competing for same tasks and ensures
  #   clean state when restarting. The database UNIQUE constraint on hostname
  #   provides additional protection against concurrent starts.
  #
  #   Example:
  #     # Check for existing reporter
  #     status <- get_process_reporter_status()
  #     if (!is.null(status) && !force) {
  #       age <- difftime(Sys.time(), status$last_heartbeat, units="secs")
  #       if (age < 60) {
  #         message("Reporter already running (PID ", status$process_id, ")")
  #         return(invisible(status$process_id))
  #       } else {
  #         message("Stale reporter detected, restarting...")
  #         stop_process_reporter(timeout = 10)
  #       }
  #     } else if (force && !is.null(status)) {
  #       message("Force flag set, stopping existing reporter...")
  #       stop_process_reporter(timeout = 10)
  #     }
  
  # Daemon Implementation:
  #   Uses callr::r_bg() to start reporter as a true background R process.
  #   This provides:
  #     - Proper process isolation (separate R session)
  #     - Non-blocking execution (returns immediately)
  #     - Automatic cleanup on parent exit
  #     - stdout/stderr redirection to log_file
  #   
  #   Example:
  #     bg_process <- callr::r_bg(
  #       func = process_reporter_main_loop,
  #       args = list(interval_seconds = interval_seconds),
  #       stdout = log_file %||% "/dev/null",
  #       stderr = log_file %||% "/dev/null",
  #       supervise = FALSE  # Don't kill when parent exits
  #     )
  #     return(invisible(bg_process$get_pid()))
  #
  #   Alternative for systemd deployment:
  #     - Create systemd service unit file (tasker-reporter@hostname.service)
  #     - Use systemctl start/stop/status for management
  #     - Provides automatic restart on failure
  #     - Better for production multi-host deployments
  
  # Returns:
  #   PID of the reporter process (invisible)
  #   Returns existing PID if reporter already running and not forced
}
```

#### `stop_process_reporter()`

Stops a running process reporter.

```r
stop_process_reporter <- function(
    hostname = Sys.info()["nodename"],
    timeout = 30
) {
  # Args:
  #   hostname: Which reporter to stop (default: current host)
  #   timeout: Seconds to wait for graceful shutdown
  
  # Behavior:
  #   - Sets shutdown_requested=TRUE in process_reporter_status
  #   - Reporter main loop checks this flag every iteration
  #   - Waits up to timeout seconds for reporter to exit gracefully
  #   - If timeout expires, can optionally send SIGTERM to reporter PID
  
  # Returns:
  #   TRUE if stopped successfully, FALSE otherwise
  
  # Implementation:
  #   con <- get_db_connection()
  #   dbExecute(con, "
  #     UPDATE process_reporter_status 
  #     SET shutdown_requested = TRUE
  #     WHERE hostname = $1
  #   ", params = list(hostname))
  #   
  #   # Wait for reporter to exit
  #   start_time <- Sys.time()
  #   while (difftime(Sys.time(), start_time, units="secs") < timeout) {
  #     status <- get_process_reporter_status(hostname)
  #     if (is.null(status)) return(TRUE)  # Reporter exited
  #     Sys.sleep(1)
  #   }
  #   
  #   return(FALSE)  # Timeout
}
```

#### `get_process_reporter_status()`

Checks if process reporter is running.

```r
get_process_reporter_status <- function(
    hostname = NULL
) {
  # Args:
  #   hostname: Check specific host (NULL = current host)
  
  # Returns:
  #   Data frame with reporter status or NULL if not running
  #   Columns: hostname, process_id, started_at, last_heartbeat, version
}
```

#### `collect_process_metrics()`

Collects metrics for a specific run_id (called by reporter).

```r
collect_process_metrics <- function(
    run_id,
    process_id,
    hostname = Sys.info()["nodename"],
    include_children = TRUE,
    timeout_seconds = 5
) {
  # Args:
  #   run_id: Task run ID to collect metrics for
  #   process_id: Main process PID
  #   hostname: Hostname where process is running
  #   include_children: Collect child process aggregate info (DIRECT children only)
  #   timeout_seconds: Maximum time to spend collecting metrics (default: 5)
  
  # Child Process Behavior:
  #   When include_children=TRUE, aggregates metrics from DIRECT children only.
  #   Does NOT recursively traverse descendants (grandchildren, etc.).
  #   This prevents double-counting in nested parallel scenarios.
  #   Uses ps::ps_children(p, recursive=FALSE) to get direct children.
  
  # Process Start Time Validation:
  #   Retrieves process start time using ps::ps_create_time() and includes in metrics.
  #   On subsequent collections, compares start time to detect PID reuse.
  #   If start time differs, returns PROCESS_DIED error (PID was reused).
  #   Start time stored in process_metrics table for validation on next iteration.
  #   This eliminates the risk of monitoring wrong process due to PID reuse.
  
  # Returns:
  #   List with comprehensive metrics data:
  #     - run_id (echoed back for write_process_metrics)
  #     - process_id, hostname
  #     - process_start_time (POSIX timestamp for PID reuse detection)
  #     - cpu_percent, memory_mb, memory_percent, swap_mb
  #     - read_bytes, write_bytes, read_count, write_count, io_wait_percent
  #     - open_files, num_fds, num_threads
  #     - page_faults_minor, page_faults_major
  #     - ctx_switches_voluntary, ctx_switches_involuntary
  #     - child_count, child_total_cpu_percent, child_total_memory_mb
  #     - is_alive
  #   OR
  #   List with error information if collection failed:
  #     - run_id (always included)
  #     - collection_error = TRUE
  #     - error_message = error description
  #     - error_type = PROCESS_DIED | PID_REUSED | PERMISSION_DENIED | PS_ERROR | 
  #                    COLLECTION_TIMEOUT | UNKNOWN
  #     - is_alive = FALSE (if applicable)
  
  # Implementation uses R.utils::withTimeout() or similar to enforce timeout
}
```

#### `write_process_metrics()`

Writes collected metrics to database.

```r
write_process_metrics <- function(
    metrics_data,
    con = NULL
) {
  # Args:
  #   metrics_data: Output from collect_process_metrics()
  #                 Must include 'run_id' field
  #                 Can include successful metrics OR error information
  #   con: Database connection (NULL = get default)
  
  # Behavior:
  #   - Extracts run_id from metrics_data
  #   - Writes metrics to process_metrics table
  #   - If collection_error = TRUE, also triggers task_update() to mark potential failure
  #   - Records error_message and error_type for UI display
  
  # Returns:
  #   metric_id of inserted row
}
```

#### `cleanup_old_metrics()`

Deletes process metrics older than retention period.

```r
cleanup_old_metrics <- function(
    retention_days = 30,
    con = NULL,
    dry_run = FALSE
) {
  # Args:
  #   retention_days: Days to keep metrics after task completion (default: 30)
  #   con: Database connection (NULL = get default)
  #   dry_run: If TRUE, report what would be deleted without deleting
  
  # Behavior:
  #   - Finds completed tasks with metrics older than retention_days
  #   - Deletes associated process_metrics records
  #   - Updates process_metrics_retention table
  #   - Returns summary of deleted records
  
  # Returns:
  #   Data frame with columns: run_id, metrics_deleted_count, task_name
}
```

#### `register_reporter()`

Registers or updates reporter in database (internal function).

```r
register_reporter <- function(
    con,
    hostname,
    process_id,
    version = as.character(packageVersion("tasker"))
) {
  # Uses UPSERT to handle concurrent reporter starts
  # If reporter already exists for hostname, updates PID and resets timestamps
  
  dbExecute(con, "
    INSERT INTO process_reporter_status 
      (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested)
    VALUES ($1, $2, NOW(), NOW(), $3, FALSE)
    ON CONFLICT (hostname) DO UPDATE SET
      process_id = EXCLUDED.process_id,
      started_at = EXCLUDED.started_at,
      last_heartbeat = EXCLUDED.last_heartbeat,
      version = EXCLUDED.version,
      shutdown_requested = FALSE
  ", params = list(hostname, process_id, version))
}
```

#### `update_reporter_heartbeat()`

Updates reporter heartbeat timestamp (internal function).

```r
update_reporter_heartbeat <- function(con, hostname) {
  dbExecute(con, "
    UPDATE process_reporter_status
    SET last_heartbeat = NOW()
    WHERE hostname = $1
  ", params = list(hostname))
}
```

### Auto-Start Integration

#### Modify `task_start()`

Add automatic reporter check and start:

```r
task_start <- function(..., auto_start_reporter = TRUE) {
  # ... existing code ...
  
  if (auto_start_reporter) {
    # Check if reporter is running on this host
    reporter_status <- get_process_reporter_status()
    
    if (is.null(reporter_status)) {
      message("Starting process reporter...")
      start_process_reporter(daemon = TRUE)
      
      # Poll for reporter to start with timeout
      start_time <- Sys.time()
      timeout_seconds <- 10
      reporter_started <- FALSE
      
      while (difftime(Sys.time(), start_time, units = "secs") < timeout_seconds) {
        Sys.sleep(0.5)
        if (!is.null(get_process_reporter_status())) {
          reporter_started <- TRUE
          break
        }
      }
      
      if (!reporter_started) {
        warning("Failed to start process reporter within ", timeout_seconds, 
                " seconds - metrics will not be collected")
      }
    } else {
      # Check if heartbeat is recent
      time_since_heartbeat <- as.numeric(difftime(
        Sys.time(), 
        reporter_status$last_heartbeat, 
        units = "secs"
      ))
      
      if (time_since_heartbeat > 60) {
        warning("Process reporter heartbeat is stale - may need restart")
      }
    }
  }
  
  # ... rest of existing code ...
}
```

## Process Reporter Implementation

### Main Loop

```r
process_reporter_main_loop <- function(interval_seconds = 10) {
  hostname <- Sys.info()["nodename"]
  process_id <- Sys.getpid()
  last_cleanup_time <- Sys.time() - 7200  # Start 2 hours ago to trigger initial cleanup
  
  # Initial registration
  con <- get_db_connection()
  register_reporter(con, hostname, process_id)
  dbDisconnect(con)
  
  while (TRUE) {
    # Get fresh connection each iteration (handles network issues)
    con <- tryCatch(
      get_db_connection(),
      error = function(e) {
        message("Database connection failed: ", e$message, " - retrying in 30s")
        Sys.sleep(30)
        return(NULL)
      }
    )
    
    if (is.null(con)) next  # Retry on next iteration
    
    tryCatch({
      # Check for shutdown request
      shutdown_check <- dbGetQuery(con, "
        SELECT shutdown_requested FROM process_reporter_status
        WHERE hostname = $1
      ", params = list(hostname))
      
      if (nrow(shutdown_check) > 0 && shutdown_check$shutdown_requested) {
        message("Shutdown requested - exiting reporter")
        dbExecute(con, "DELETE FROM process_reporter_status WHERE hostname = $1", 
                  params = list(hostname))
        dbDisconnect(con)
        break
      }
      
      # Update heartbeat
      update_reporter_heartbeat(con, hostname)
      
      # Get all active task runs on this host
      active_runs <- dbGetQuery(con, "
        SELECT run_id, process_id, hostname
        FROM task_runs
        WHERE status IN ('RUNNING', 'STARTED')
          AND hostname = $1
          AND process_id IS NOT NULL
      ", params = list(hostname))
      
      # Collect metrics for each active run with timeout
      if (nrow(active_runs) > 0) {
        for (i in seq_len(nrow(active_runs))) {
          run <- active_runs[i, ]
          
          # Skip if hostname mismatch (shouldn't happen with query filter)
          if (run$hostname != hostname) {
            warning("Task run ", run$run_id, " hostname mismatch - skipping")
            next
          }
          
          # Get previous metrics to check for process start time changes
          prev_metrics <- tryCatch({
            dbGetQuery(con, "
              SELECT process_start_time 
              FROM process_metrics 
              WHERE run_id = $1 
              ORDER BY timestamp DESC 
              LIMIT 1
            ", params = list(run$run_id))
          }, error = function(e) NULL)
          
          metrics <- collect_process_metrics(
            run_id = run$run_id,
            process_id = run$process_id,
            hostname = run$hostname,
            include_children = TRUE,
            timeout_seconds = 5
          )
          
          # Validate process start time hasn't changed (PID reuse detection)
          if (!is.null(metrics) && !is.null(prev_metrics) && 
              nrow(prev_metrics) > 0 && !is.na(prev_metrics$process_start_time[1])) {
            if (!is.null(metrics$process_start_time) && 
                metrics$process_start_time != prev_metrics$process_start_time[1]) {
              # PID was reused - mark as error
              metrics$collection_error <- TRUE
              metrics$error_type <- "PID_REUSED"
              metrics$error_message <- sprintf(
                "Process PID %d was reused (start time changed from %s to %s)",
                metrics$process_id,
                prev_metrics$process_start_time[1],
                metrics$process_start_time
              )
              metrics$is_alive <- FALSE
            }
          }
          
          # Always write metrics, even if collection failed
          # run_id is included in metrics_data
          if (!is.null(metrics)) {
            write_process_metrics(metrics, con)
            
            # If collection error and process appears dead, trigger task status update
            if (isTRUE(metrics$collection_error) && !isTRUE(metrics$is_alive)) {
              task_update(
                run_id = run$run_id,
                status = "FAILED",
                message = paste0("Process monitoring error: ", metrics$error_message),
                con = con
              )
            }
          }
        }
      }
      
      # Periodic cleanup - check if 1+ hours since last cleanup
      hours_since_cleanup <- difftime(Sys.time(), last_cleanup_time, units = "hours")
      if (hours_since_cleanup >= 1) {
        message("Running metrics cleanup...")
        cleanup_old_metrics(retention_days = 30, con = con)
        last_cleanup_time <- Sys.time()
      }
      
    }, error = function(e) {
      message("Error in process reporter iteration: ", e$message)
    }, finally = {
      dbDisconnect(con)
    })
    
    Sys.sleep(interval_seconds)
  }
  
  message("Process reporter exiting")
}
```

### Configuration File (YAML)

```yaml
# tasker_reporter_config.yml
process_reporter:
  interval_seconds: 10
  log_file: "~/tasker/reporter.log"
  log_level: "INFO"
  
  collection:
    include_children: true          # Aggregate child process metrics
    collect_all_metrics: true       # CPU, memory, I/O, file descriptors, etc.
    
  retention:
    cleanup_days: 30                # Delete metrics 30 days after task completion
    cleanup_check_interval: 3600    # Check for cleanup every hour
    
  database:
    # Use default connection from tasker config
    use_default: true
    
  monitoring:
    heartbeat_interval: 30          # seconds
    stale_threshold: 300            # 5 minutes
    
  error_handling:
    trigger_task_failure: true      # Call task_update() on collection errors
    record_errors_in_db: true       # Store error details in process_metrics
```

## Usage Examples

### Manual Start/Stop

```r
library(tasker)

# Start the reporter (checks for existing instance automatically)
start_process_reporter(interval_seconds = 5)
# If already running: "Reporter already running (PID 12345)"
# If stale: "Stale reporter detected, restarting..."

# Force restart even if running
start_process_reporter(interval_seconds = 5, force = TRUE)

# Check status
status <- get_process_reporter_status()
print(status)

# Stop the reporter
stop_process_reporter()
```

### Automatic Start (Default)

```r
# Reporter automatically starts when task begins
library(tasker)

run_id <- task_start(
  stage = "DATA_LOAD",
  task = "load_census_data",
  total_subtasks = 5
)

# Reporter is now running and collecting metrics
# ... do work ...

task_complete(run_id)
```

### Query Metrics in Monitor

```r
# Get latest metrics for a task (includes errors if any)
metrics <- dbGetQuery(con, "
  SELECT * FROM task_runs_with_latest_metrics
  WHERE run_id = $1
", params = list(run_id))

# Check for collection errors
if (metrics$collection_error) {
  warning(sprintf("Metrics collection error: %s (%s)", 
                  metrics$error_message, metrics$error_type))
}

# Get time series of metrics
time_series <- dbGetQuery(con, "
  SELECT 
    timestamp,
    cpu_percent,
    memory_mb,
    child_count,
    child_total_cpu_percent,
    child_total_memory_mb,
    collection_error,
    error_message
  FROM process_metrics
  WHERE run_id = $1
  ORDER BY timestamp
", params = list(run_id))

# Get all errors for a task
errors <- dbGetQuery(con, "
  SELECT timestamp, error_type, error_message, is_alive
  FROM process_metrics
  WHERE run_id = $1 AND collection_error = TRUE
  ORDER BY timestamp
", params = list(run_id))
```

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Create database tables (`process_metrics`, `process_reporter_status`, `process_metrics_retention`)
- [ ] Add `process_start_time` column to `process_metrics` table
- [ ] Create view `task_runs_with_latest_metrics`
- [ ] Create index `idx_task_runs_active_host` on task_runs
- [ ] Implement `collect_process_metrics()` using ps package with:
  - [ ] Comprehensive metrics collection
  - [ ] Process start time capture using `ps::ps_create_time()`
  - [ ] Direct children only (no recursive descendants)
  - [ ] 5-second timeout using R.utils::withTimeout()
  - [ ] Return run_id and process_start_time in metrics data
- [ ] Implement error detection and classification (all error types including PID_REUSED)
- [ ] Implement `write_process_metrics()` with error handling
- [ ] Implement `register_reporter()` with UPSERT logic
- [ ] Implement `update_reporter_heartbeat()`
- [ ] Implement reporter status tracking with shutdown_requested flag

### Phase 2: Reporter Service
- [ ] Implement main reporter loop with:
  - [ ] 10-second interval
  - [ ] Fresh DB connection each iteration (auto-reconnect)
  - [ ] Shutdown flag checking
  - [ ] Process start time validation on each collection
  - [ ] Cleanup timing based on elapsed hours (not clock time)
  - [ ] Hostname validation
- [ ] Implement `start_process_reporter()` with:
  - [ ] Check for existing reporter (prevent duplicates)
  - [ ] Handle stale reporters (>60s heartbeat)
  - [ ] Force restart option
  - [ ] callr::r_bg() daemon mode
  - [ ] Log file redirection
  - [ ] PID return and tracking
- [ ] Implement `stop_process_reporter()` with graceful shutdown
- [ ] Add heartbeat mechanism with stale detection (no CHECK constraint)
- [ ] Configuration file support (YAML)
- [ ] Implement `cleanup_old_metrics()` for 30-day retention
- [ ] Auto-start integration in `task_start()` with 10-second polling timeout

### Phase 3: Database-Only Monitoring
- [ ] Modify `get_task_status()` to use database metrics exclusively
- [ ] Remove direct `ps` package calls from monitor code
- [ ] Update Tasker Monitor UI to display metrics from database
- [ ] Add error display in monitor UI (warning banners for collection errors)
- [ ] Handle stale metrics gracefully (show age, warn if >30 seconds old)

### Phase 4: Enhancements
- [ ] Add historical metrics visualization (time series charts)
- [ ] Add alerting for resource thresholds (OOM warnings)
- [ ] Add multi-host dashboard view
- [ ] Performance optimization for high-frequency collection
- [ ] Add metrics export/reporting functionality

## Benefits

1. **Cross-Container Compatibility** - Works regardless of container boundaries, monitor can run in Docker
2. **Historical Metrics** - Store comprehensive time series data for diagnosis (especially OOM issues)
3. **Multi-Host Support** - Monitor tasks across multiple servers from single dashboard
4. **Automatic Setup** - Auto-starts when tasks begin, no manual configuration
5. **Scalable** - Independent reporters per host, database-only reads from monitor
6. **Resilient** - Reporter continues if monitor goes down, metrics preserved
7. **Error Tracking** - Collection errors recorded in database and displayed in UI
8. **Efficient Retention** - Automatic 30-day cleanup prevents unbounded growth
9. **Comprehensive Metrics** - All resource usage including CPU, memory, I/O, file descriptors, page faults
10. **Child Process Aggregation** - Track total resource usage across parallel workers

## Dependencies

- **ps** package (>= 1.7.0) - Cross-platform process information with start time validation
- **callr** package (>= 3.7.0) - Background R process management for daemon mode
- **RPostgres** package - Database connectivity
- **yaml** package - Configuration file parsing
- **DBI** package - Database interface
- **R.utils** package - For withTimeout() in metric collection

## Security Considerations

1. **Process Visibility** - Reporter runs as same user as tasks for permission access
2. **Database Permissions** - Reporter needs:
   - INSERT on `process_metrics`
   - UPDATE on `process_reporter_status`
   - INSERT/UPDATE on `process_metrics_retention`
3. **Heartbeat Monitoring** - Detect stale reporters (>5 minutes) and alert in UI
4. **Error Isolation** - Collection errors don't crash reporter, recorded for analysis
5. **Cross-Container Access** - Database must be network-accessible from all task hosts

## Error Types and Handling

| Error Type | Description | Action Taken |
|------------|-------------|--------------|
| PROCESS_DIED | Process no longer exists (PID not found) | Record error, trigger task_update() to mark FAILED |
| PID_REUSED | Process start time changed (PID was recycled) | Record error, trigger task_update() to mark FAILED |
| PERMISSION_DENIED | Cannot access process info (different user) | Record error, log warning |
| PS_ERROR | ps package threw an error | Record error with exception message |
| ZOMBIE_PROCESS | Process is zombie/defunct | Record error, mark is_alive=FALSE |
| COLLECTION_TIMEOUT | Metrics collection took too long (>5 seconds) | Record error, skip this cycle |
| UNKNOWN | Unexpected error during collection | Record error with full message |

**Note on PID Reuse:** The design validates process start times using `ps::ps_create_time()` to detect PID reuse. On each metrics collection, the process start time is retrieved and compared to the previous collection. If the start time has changed, a PID_REUSED error is recorded and the task is marked as failed. This eliminates the risk of monitoring the wrong process, as PID reuse is detected within one monitoring interval (10 seconds).

## Testing Strategy

1. **Unit tests** for metric collection functions
   - Test with running process
   - Test with dead process (PROCESS_DIED error)
   - Test with child processes (aggregate calculation)
   - Test error handling and classification
   
2. **Integration tests** with containerized monitor
   - Monitor in Docker container
   - Tasks running on host
   - Verify database-only monitoring works
   - Verify error display in UI
   
3. **Multi-host deployment testing**
   - Multiple reporters writing to same database
   - Verify hostname filtering works correctly
   - Test reporter collision handling
   
4. **Performance testing** with many parallel tasks
   - 32 child processes per task
   - Multiple concurrent tasks
   - Measure collection overhead
   - Verify 10-second interval maintained
   
5. **Failure recovery testing**
   - Reporter crashes and auto-restarts
   - Database unavailable (connection retry)
   - Stale heartbeat detection and alerting
   
6. **Retention testing**
   - Verify 30-day cleanup works
   - Test retention tracking
   - Verify completed task metrics deleted
