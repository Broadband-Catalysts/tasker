# Pipeline Status Tracking System - Design Document

**Date:** 2025-12-20  
**Author:** System Design  
**Status:** DRAFT - Awaiting Review

---

## Executive Summary

This document proposes a comprehensive database-backed status tracking system for the FCC Data Pipeline to replace the current file-based monitoring approach. The new system will provide real-time visibility into script execution status, progress, and performance metrics.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Proposed Solution](#proposed-solution)
3. [Database Schema](#database-schema)
4. [Status Details & Metrics](#status-details--metrics)
5. [Implementation Components](#implementation-components)
6. [Migration Path](#migration-path)
7. [Benefits](#benefits)
8. [Risks & Mitigation](#risks--mitigation)

---

## Current State Analysis

### Existing Monitoring Approach

The current pipeline monitor ([inst/pipeline-monitor/app.R](inst/pipeline-monitor/app.R)) uses:

1. **Log File Analysis**: Parses `.Rout` and `.log` files to extract status
2. **Process Detection**: Uses `ps auxwww | grep` to detect running scripts
3. **Pattern Matching**: Searches for completion markers like "COMPLETE", "Error in", etc.
4. **File Timestamps**: Uses modification times to infer execution duration

### Limitations of Current Approach

1. **Unreliable Process Detection**
   - Process name matching can be ambiguous
   - Truncated process names cause false negatives
   - No way to distinguish multiple runs of same script

2. **Limited Progress Visibility**
   - Only a few scripts have custom progress tracking
   - Progress requires database queries for specific table states
   - No standardized progress reporting

3. **No Historical Data**
   - Cannot track execution history
   - No performance trend analysis
   - Difficult to identify bottlenecks

4. **Incomplete Status Information**
   - Missing: task-level progress within scripts
   - Missing: error context and recovery information
   - Missing: resource usage metrics

5. **Log File Dependency**
   - Must parse unstructured text
   - Patterns can change with script modifications
   - No standard format across R/Python/Shell scripts

### Functions Currently Used

The codebase uses `genter()`, `gexit()`, and `gmessage()` functions for logging:

**Observed Usage Pattern:**
```r
genter("processing state location data")
# ... do work ...
gexit()
```

These appear to be simple console logging functions (not found in package, likely defined elsewhere or in calling environment). They provide natural insertion points for status tracking.

---

## Proposed Solution

### Overview

Create a **database-backed status tracking system** with:

1. **PostgreSQL Table** (`geodb.pipeline_status`) to store execution state
2. **R Package Functions** (`track_status()`) to record status updates
3. **Python Module** (`pipeline_tracker.py`) with equivalent functionality
4. **Enhanced Monitor Dashboard** to display real-time status
5. **Standard Integration Points** in all pipeline scripts

### Key Design Principles

1. **Minimal Script Changes**: Use existing `genter()`/`gexit()` insertion points
2. **Fail-Safe**: Tracking failures should not halt pipeline execution
3. **Performance**: Async/batch updates to avoid blocking
4. **Comprehensive**: Capture all relevant execution metadata
5. **Real-Time**: Dashboard updates within seconds

---

## Database Schema

### Table: `pipeline_status`

Located in `geodb` database (production monitoring database).

```sql
CREATE TABLE IF NOT EXISTS pipeline_status (
    -- Primary identification
    execution_id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL UNIQUE,
    
    -- Task identification
    task_name VARCHAR(255) NOT NULL,
    task_stage VARCHAR(50),       -- PREREQ, DAILY, ANNUAL_DEC, etc.
    task_type VARCHAR(10),        -- R, python, sh, etc.
    
    -- Execution context
    hostname VARCHAR(255) NOT NULL,
    process_id INTEGER NOT NULL,
    user_name VARCHAR(100),
    
    -- File paths
    script_path VARCHAR(500),
    script_file VARCHAR(255),
    log_path VARCHAR(500),
    log_file VARCHAR(255),
    
    -- Timing information
    execution_start TIMESTAMPTZ NOT NULL,
    execution_end TIMESTAMPTZ,
    last_update TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Status tracking
    execution_status VARCHAR(20) NOT NULL,  -- STARTED, RUNNING, FINISHED, FAILED, CANCELLED
    
    -- Subtask tracking (for multi-step tasks)
    total_subtasks INTEGER,
    current_subtask INTEGER,
    subtask_name VARCHAR(500),
    subtask_status VARCHAR(20),  -- NOT_STARTED, RUNNING, COMPLETED, FAILED
    
    -- Overall progress (across all subtasks)
    overall_percent_complete NUMERIC(5,2),  -- 0.00 to 100.00
    overall_progress_message TEXT,
    
    -- Subtask progress (within current subtask)
    subtask_percent_complete NUMERIC(5,2),  -- 0.00 to 100.00
    subtask_progress_message TEXT,
    subtask_items_total BIGINT,      -- Total items in current subtask (e.g., 56 states)
    subtask_items_complete BIGINT,   -- Items completed in current subtask
    
    -- Resource tracking
    memory_mb INTEGER,
    cpu_percent NUMERIC(5,2),
    
    -- Error tracking
    error_message TEXT,
    error_detail TEXT,
    
    -- Metadata
    git_commit VARCHAR(40),
    environment JSONB,  -- Store relevant env vars
    
    -- Constraints
    CONSTRAINT chk_status CHECK (execution_status IN 
        ('STARTED', 'RUNNING', 'FINISHED', 'FAILED', 'CANCELLED')),
    CONSTRAINT chk_subtask_status CHECK (subtask_status IS NULL OR subtask_status IN 
        ('NOT_STARTED', 'RUNNING', 'COMPLETED', 'FAILED'))
);

-- Indexes for common queries
CREATE INDEX idx_pipeline_status_run_id ON pipeline_status(run_id);
CREATE INDEX idx_pipeline_status_script_name ON pipeline_status(script_name);
CREATE INDEX idx_pipeline_status_status ON pipeline_status(execution_status);
CREATE INDEX idx_pipeline_status_start_time ON pipeline_status(execution_start);
CREATE INDEX idx_pipeline_status_hostname_pid ON pipeline_status(hostname, process_id);

-- Index for latest status per script
CREATE INDEX idx_pipeline_status_latest ON pipeline_status(script_name, execution_start DESC);

-- Partitioning by date (optional, for high-volume environments)
-- Can partition by execution_start for historical data management
```

### Table: `pipeline_status_history`

Archive table for completed runs (optional, for long-term analytics):

```sql
CREATE TABLE IF NOT EXISTS pipeline_status_history (
    LIKE pipeline_status INCLUDING ALL
) PARTITION BY RANGE (execution_start);

-- Create partitions as needed (monthly or quarterly)
```

---

## Status Details & Metrics

### Execution Status Values

| Status | Meaning | When Set |
|--------|---------|----------|
| `STARTED` | Script initialization | At script startup, before main work |
| `RUNNING` | Active execution | After startup, during main processing |
| `FINISHED` | Successful completion | At normal script termination |
| `FAILED` | Error/exception occurred | On uncaught errors or explicit failure |
| `CANCELLED` | Manually stopped | On SIGTERM/SIGINT signals |

### Task Status Values

| Status | Meaning |
|--------|---------|
| `NOT_STARTED` | Task queued but not begun |
| `RUNNING` | Task currently executing |
| `COMPLETED` | Task finished successfully |
| `FAILED` | Task encountered error |

### Progress Calculation

The system tracks **two levels of progress**:

#### 1. Overall Script Progress

Tracks completion across all tasks in the script.

**Automatic Calculation:**
- `overall_percent_complete = (current_task / total_tasks) * 100`
- Updated automatically when `genter()` is called (task counter increments)
- Provides high-level view of script completion

**Manual Override:**
- Scripts can set custom overall percentage if task-based calculation isn't accurate
- Useful for scripts with variable-length tasks

**Example Overall Messages:**
```
"Processing 56 states (task 12 of 56)"
"Step 3 of 5: Building consolidated table"
```

#### 2. Current Task Progress

Tracks progress within the currently executing task.

**Manual Updates:**
- Set via `task_items_total` and `task_items_complete` parameters
- `task_percent_complete = (task_items_complete / task_items_total) * 100`
- Updated during long-running tasks (e.g., processing states, loading files)

**When to Use:**
- Long-running tasks that process multiple items
- Parallel processing with trackable work units
- Any task where intermediate progress is meaningful

**Example Task Messages:**
```
"Loading file 3 of 8: Alaska.csv (2.3M records)"
"Processing state 12 of 56: Delaware"
"Indexing: 450,000 / 1,000,000 rows (45%)"
"Joining roads_hex: 23 of 56 counties complete"
```

#### Combined Display Example

```
Task: DAILY_01_BDC_Locations.R
Overall: Subtask 12 of 56 (21%) - "Processing state location data"
Current Subtask: "Loading Delaware file" - 3 of 8 files (38%)
```

This two-level approach provides:
- **High-level visibility**: How far through the entire script
- **Detailed visibility**: Progress within the current long-running operation
- **Accurate ETAs**: Both for task and overall completion

### Tracked Metrics

#### Essential Metrics (Always Captured)
- Execution start/end times
- Script name and location
- Process ID and hostname
- Status and task counts
- Overall progress (task-based)
- Current task progress (item-based)

#### Optional Metrics (Best Effort)
- Memory usage (current, peak)
- CPU utilization (average)
- Disk I/O rates
- Network I/O (for downloads)
- Database connection count
- Row counts processed

#### Progress Tracking Guidelines

**Overall Progress** (task-level):
- Use for: Script-level completion tracking
- Updated: Automatically by `genter()` / `gexit()`
- Calculation: `current_subtask / total_subtasks`

**Subtask Progress** (item-level):
- Use for: Long-running operations within a single subtask
- Updated: Manually via `track_status()` with item counts
- Calculation: `task_items_complete / task_items_total`
- Examples: States processed, files loaded, rows indexed

---

## Implementation Components

### 1. R Package Functions

Create `R/track_status.R`:

```r
#' Initialize status tracking for current script
#'
#' Call once at script startup to register execution.
#'
#' @param script_name Name of the script
#' @param total_tasks Total number of tasks (optional)
#' @param category Script category (STATIC, DAILY, etc.)
#' @return run_id (UUID) for this execution
#' @export
track_init <- function(script_name, total_tasks = NULL, category = NULL) {
  # Generate unique run ID
  run_id <- uuid::UUIDgenerate()
  
  # Get execution context
  hostname <- Sys.info()[["nodename"]]
  pid <- Sys.getpid()
  user <- Sys.info()[["user"]]
  
  # Detect stage from task name if not provided
  if (is.null(stage)) {
    stage <- detect_task_stage(task_name)
  }
  
  # Connect to monitoring database
  con <- tryCatch({
    dbConnectBBC("monitoring")  # New connection type for geodb
  }, error = function(e) {
    warning("Failed to connect to monitoring database: ", e$message)
    return(NULL)
  })
  
  if (is.null(con)) {
    # Tracking disabled - continue execution
    return(invisible(NULL))
  }
  
  on.exit({
    if (!is.null(con) && DBI::dbIsValid(con)) {
      DBI::dbDisconnect(con)
    }
  })
  
  # Insert initial status record
  tryCatch({
    DBI::dbExecute(con, "
      INSERT INTO tasker.executions (
        run_id, task_name, task_stage, task_type,
        hostname, process_id, user_name,
        execution_start, execution_status,
        total_subtasks, current_subtask,
        git_commit, environment
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13
      )
    ", params = list(
      run_id,
      script_name,
      category,
      "R",
      hostname,
      pid,
      user,
      Sys.time(),
      "STARTED",
      total_tasks,
      0L,
      get_git_commit(),
      get_env_json()
    ))
    
    message(sprintf("Status tracking initialized: run_id=%s", run_id))
    
  }, error = function(e) {
    warning("Failed to initialize status tracking: ", e$message)
  })
  
  # Store run_id in global option for other functions
  options(pipeline_run_id = run_id)
  
  invisible(run_id)
}

#' Update status during task execution
#'
#' Call at subtask boundaries or periodically to update progress.
#'
#' @param status Execution status (RUNNING, FINISHED, FAILED)
#' @param current_subtask Current subtask number (optional)
#' @param subtask_name Description of current subtask (optional)
#' @param subtask_status Status of current subtask (optional)
#' @param overall_percent Manual override for overall progress (optional)
#' @param overall_message Overall progress message (optional)
#' @param subtask_percent Manual override for subtask progress (optional)
#' @param subtask_message Subtask progress message (optional)
#' @param subtask_items_total Total items in current subtask (optional)
#' @param subtask_items_complete Items completed in current subtask (optional)
#' @export
track_status <- function(status = "RUNNING",
                         current_subtask = NULL,
                         subtask_name = NULL,
                         subtask_status = NULL,
                         overall_percent = NULL,
                         overall_message = NULL,
                         subtask_percent = NULL,
                         subtask_message = NULL,
                         subtask_items_total = NULL,
                         subtask_items_complete = NULL) {
  
  run_id <- getOption("pipeline_run_id")
  if (is.null(run_id)) {
    # Tracking not initialized - silent return
    return(invisible(NULL))
  }
  
  con <- tryCatch({
    dbConnectBBC("monitoring")
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(con)) return(invisible(NULL))
  
  on.exit({
    if (!is.null(con) && DBI::dbIsValid(con)) {
      DBI::dbDisconnect(con)
    }
  })
  
  # Get resource usage (best effort)
  memory_mb <- tryCatch({
    as.integer(pryr::mem_used() / 1024^2)
  }, error = function(e) NULL)
  
  # Build update query dynamically based on provided parameters
  updates <- c("last_update = $1", "execution_status = $2")
  params <- list(Sys.time(), status)
  param_idx <- 3
  
  if (!is.null(current_subtask)) {
    updates <- c(updates, sprintf("current_subtask = $%d", param_idx))
    params[[param_idx]] <- current_subtask
    param_idx <- param_idx + 1
  }
  
  if (!is.null(subtask_name)) {
    updates <- c(updates, sprintf("subtask_name = $%d", param_idx))
    params[[param_idx]] <- subtask_name
    param_idx <- param_idx + 1
  }
  
  if (!is.null(subtask_status)) {
    updates <- c(updates, sprintf("subtask_status = $%d", param_idx))
    params[[param_idx]] <- subtask_status
    param_idx <- param_idx + 1
  }
  
  # Overall progress tracking
  if (!is.null(overall_percent)) {
    updates <- c(updates, sprintf("overall_percent_complete = $%d", param_idx))
    params[[param_idx]] <- overall_percent
    param_idx <- param_idx + 1
  }
  
  if (!is.null(overall_message)) {
    updates <- c(updates, sprintf("overall_progress_message = $%d", param_idx))
    params[[param_idx]] <- overall_message
    param_idx <- param_idx + 1
  }
  
  # Subtask-level progress tracking
  if (!is.null(subtask_percent)) {
    updates <- c(updates, sprintf("subtask_percent_complete = $%d", param_idx))
    params[[param_idx]] <- subtask_percent
    param_idx <- param_idx + 1
  }
  
  if (!is.null(subtask_message)) {
    updates <- c(updates, sprintf("subtask_progress_message = $%d", param_idx))
    params[[param_idx]] <- subtask_message
    param_idx <- param_idx + 1
  }
  
  if (!is.null(subtask_items_total)) {
    updates <- c(updates, sprintf("subtask_items_total = $%d", param_idx))
    params[[param_idx]] <- subtask_items_total
    param_idx <- param_idx + 1
  }
  
  if (!is.null(subtask_items_complete)) {
    updates <- c(updates, sprintf("subtask_items_complete = $%d", param_idx))
    params[[param_idx]] <- subtask_items_complete
    param_idx <- param_idx + 1
    
    # Auto-calculate subtask percentage if both total and complete provided
    if (!is.null(subtask_items_total) && subtask_items_total > 0) {
      subtask_pct <- round((subtask_items_complete / subtask_items_total) * 100, 2)
      updates <- c(updates, sprintf("subtask_percent_complete = $%d", param_idx))
      params[[param_idx]] <- subtask_pct
      param_idx <- param_idx + 1
    }
  }
  
  if (!is.null(memory_mb)) {
    updates <- c(updates, sprintf("memory_mb = $%d", param_idx))
    params[[param_idx]] <- memory_mb
    param_idx <- param_idx + 1
  }
  
  # Special handling for FINISHED/FAILED status
  if (status %in% c("FINISHED", "FAILED")) {
    updates <- c(updates, sprintf("execution_end = $%d", param_idx))
    params[[param_idx]] <- Sys.time()
    param_idx <- param_idx + 1
  }
  
  # Execute update
  tryCatch({
    sql <- sprintf("
      UPDATE pipeline_status
      SET %s
      WHERE run_id = $%d
    ", paste(updates, collapse = ", "), param_idx)
    
    params[[param_idx]] <- run_id
    
    DBI::dbExecute(con, sql, params = params)
    
    # Also log to console (prefer task message, fallback to overall)
    log_message <- task_message %||% overall_message
    if (!is.null(log_message)) {
      cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), log_message))
    }
    
  }, error = function(e) {
    warning("Failed to update status: ", e$message)
  })
  
  invisible(NULL)
}

#' Finish status tracking (success)
#'
#' Call at successful script completion.
#'
#' @param message Completion message (optional)
#' @export
track_finish <- function(message = "Script completed successfully") {
  track_status(
    status = "FINISHED",
    overall_percent = 100,
    overall_message = message
  )
}

#' Record failure in status tracking
#'
#' Call in error handlers to record failures.
#'
#' @param error_msg Error message
#' @param error_detail Detailed error information (optional)
#' @export
track_error <- function(error_msg, error_detail = NULL) {
  run_id <- getOption("pipeline_run_id")
  if (is.null(run_id)) return(invisible(NULL))
  
  con <- tryCatch({
    dbConnectBBC("monitoring")
  }, error = function(e) NULL)
  
  if (is.null(con)) return(invisible(NULL))
  
  on.exit({
    if (!is.null(con) && DBI::dbIsValid(con)) {
      DBI::dbDisconnect(con)
    }
  })
  
  tryCatch({
    DBI::dbExecute(con, "
      UPDATE pipeline_status
      SET 
        execution_status = $1,
        execution_end = $2,
        error_message = $3,
        error_detail = $4,
        last_update = $2
      WHERE run_id = $5
    ", params = list(
      "FAILED",
      Sys.time(),
      error_msg,
      error_detail,
      run_id
    ))
    
    message(sprintf("ERROR: %s", error_msg))
    
  }, error = function(e) {
    warning("Failed to record error: ", e$message)
  })
  
  invisible(NULL)
}

#' Enhanced genter() replacement with status tracking
#'
#' Drop-in replacement for existing genter() calls.
#'
#' @param message Task description
#' @export
genter <- function(message) {
  # Get interpolated message (glue evaluation)
  message_text <- glue::glue(message, .envir = parent.frame())
  
  # Check if this is first call (initialization)
  if (is.null(getOption("pipeline_run_id"))) {
    # First genter() call - initialize tracking
    script_name <- get_script_name()
    track_init(script_name)
  }
  
  # Increment task counter
  current_task <- getOption("pipeline_current_task", 0) + 1
  options(pipeline_current_task = current_task)
  
  # Calculate overall progress
  total_tasks <- getOption("pipeline_total_tasks", 0)
  overall_pct <- if (total_tasks > 0) {
    round((current_task / total_tasks) * 100, 2)
  } else {
    NULL
  }
  
  # Update status - reset task progress for new task
  track_status(
    status = "RUNNING",
    current_task = current_task,
    task_name = as.character(message_text),
    task_status = "RUNNING",
    overall_percent = overall_pct,
    overall_message = paste0("Task ", current_task, 
                             if (total_tasks > 0) paste0(" of ", total_tasks) else "", 
                             ": ", message_text),
    # Reset task-level progress
    task_percent = 0,
    task_message = NULL,
    task_items_total = NULL,
    task_items_complete = 0
  )
  
  invisible(NULL)
}

#' Enhanced gexit() replacement with status tracking
#'
#' Drop-in replacement for existing gexit() calls.
#'
#' @export
gexit <- function() {
  current_task <- getOption("pipeline_current_task", 0)
  
  # Mark current task as completed (100% for this task)
  track_status(
    status = "RUNNING",
    current_task = current_task,
    task_status = "COMPLETED",
    task_percent = 100
  )
  
  invisible(NULL)
}

#' Enhanced gmessage() for informational messages
#'
#' @param message Message text
#' @export
gmessage <- function(message) {
  message_text <- glue::glue(message, .envir = parent.frame())
  
  # Update task progress message without changing task status
  track_status(
    status = "RUNNING",
    task_message = as.character(message_text)
  )
  
  invisible(NULL)
}

#' Update task progress during long-running operations
#'
#' Use within a task to report progress on item processing.
#'
#' @param items_complete Number of items completed
#' @param items_total Total number of items (optional, if not set during init)
#' @param message Progress message (optional)
#' @export
#' @examples
#' \dontrun{
#' genter("Processing states")
#' for (i in seq_along(states)) {
#'   process_state(states[i])
#'   track_task_progress(i, length(states), "Processed {states[i]}")
#' }
#' gexit()
#' }
track_task_progress <- function(items_complete, items_total = NULL, message = NULL) {
  # Get interpolated message if provided
  if (!is.null(message)) {
    message <- glue::glue(message, .envir = parent.frame())
  }
  
  track_status(
    status = "RUNNING",
    task_items_complete = items_complete,
    task_items_total = items_total,
    task_message = message
  )
  
  invisible(NULL)
}

# Helper functions

detect_task_stage <- function(task_name) {
  if (grepl("^STATIC_", task_name)) return("STATIC")
  if (grepl("^DAILY_", task_name)) return("DAILY")
  if (grepl("^ANNUAL_DEC_", task_name)) return("ANNUAL_DEC")
  if (grepl("^ANNUAL_SEPT_", script_name)) return("ANNUAL_SEPT")
  if (grepl("^ANNUAL_JUNE_", script_name)) return("ANNUAL_JUNE")
  if (grepl("^PERIODIC_", script_name)) return("PERIODIC")
  if (grepl("^PREREQ_", script_name)) return("PREREQ")
  return("UNKNOWN")
}

get_script_name <- function() {
  # Try to determine script name from call stack
  script <- tryCatch({
    args <- commandArgs(trailingOnly = FALSE)
    file_arg <- args[grep("^--file=", args)]
    if (length(file_arg) > 0) {
      basename(sub("^--file=", "", file_arg))
    } else {
      "unknown_script.R"
    }
  }, error = function(e) "unknown_script.R")
  
  return(script)
}

get_git_commit <- function() {
  tryCatch({
    system("git rev-parse HEAD", intern = TRUE, ignore.stderr = TRUE)
  }, error = function(e) NULL)
}

get_env_json <- function() {
  # Capture relevant environment variables
  env_vars <- Sys.getenv(c(
    "BDC_DOWNLOAD_PATH",
    "PYTHONPATH",
    "R_LIBS",
    "R_LIBS_USER"
  ))
  jsonlite::toJSON(env_vars, auto_unbox = TRUE)
}
```

### 2. Python Module

Create `inst/python/pipeline_tracker.py`:

```python
"""
Pipeline Status Tracker - Python Implementation

Provides status tracking functions for Python pipeline scripts.
"""

import os
import sys
import psycopg2
import uuid
from datetime import datetime
import json
import subprocess
import socket

# Global state
_run_id = None
_current_task = 0

def track_init(script_name, total_tasks=None, category=None):
    """
    Initialize status tracking for current script.
    
    Args:
        script_name: Name of the script
        total_tasks: Total number of tasks (optional)
        category: Script category (STATIC, DAILY, etc.)
    
    Returns:
        run_id (UUID) for this execution
    """
    global _run_id
    
    # Generate unique run ID
    _run_id = str(uuid.uuid4())
    
    # Get execution context
    hostname = socket.gethostname()
    pid = os.getpid()
    user = os.environ.get('USER', 'unknown')
    
    # Detect stage from task name if not provided
    if stage is None:
        stage = _detect_task_stage(task_name)
    
    # Connect to monitoring database
    try:
        conn = _get_monitor_connection()
        if conn is None:
            print("Warning: Failed to connect to monitoring database", 
                  file=sys.stderr)
            return None
        
        cursor = conn.cursor()
        
        # Insert initial status record
        cursor.execute("""
            INSERT INTO tasker.executions (
                run_id, task_name, task_stage, task_type,
                hostname, process_id, user_name,
                execution_start, execution_status,
                total_subtasks, current_subtask,
                git_commit, environment
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
        """, (
            _run_id,
            script_name,
            category,
            "python",
            hostname,
            pid,
            user,
            datetime.now(),
            "STARTED",
            total_tasks,
            0,
            _get_git_commit(),
            _get_env_json()
        ))
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"Status tracking initialized: run_id={_run_id}")
        
    except Exception as e:
        print(f"Warning: Failed to initialize status tracking: {e}", 
              file=sys.stderr)
    
    return _run_id


def track_status(status="RUNNING", current_subtask=None, subtask_name=None,
                 subtask_status=None, overall_percent=None, overall_message=None,
                 subtask_percent=None, subtask_message=None, 
                 subtask_items_total=None, subtask_items_complete=None):
    """
    Update status during task execution.
    
    Args:
        status: Execution status (RUNNING, FINISHED, FAILED)
        current_subtask: Current subtask number (optional)
        subtask_name: Description of current subtask (optional)
        subtask_status: Status of current subtask (optional)
        overall_percent: Manual override for overall progress (optional)
        overall_message: Overall progress message (optional)
        subtask_percent: Manual override for subtask progress (optional)
        subtask_message: Subtask progress message (optional)
        subtask_items_total: Total items in current subtask (optional)
        subtask_items_complete: Items completed in current subtask (optional)
    """
    if _run_id is None:
        # Tracking not initialized - silent return
        return
    
    try:
        conn = _get_monitor_connection()
        if conn is None:
            return
        
        cursor = conn.cursor()
        
        # Build update query dynamically
        updates = ["last_update = %s", "execution_status = %s"]
        params = [datetime.now(), status]
        
        if current_subtask is not None:
            updates.append("current_subtask = %s")
            params.append(current_subtask)
        
        if subtask_name is not None:
            updates.append("subtask_name = %s")
            params.append(subtask_name)
        
        if subtask_status is not None:
            updates.append("subtask_status = %s")
            params.append(subtask_status)
        
        # Overall progress
        if overall_percent is not None:
            updates.append("overall_percent_complete = %s")
            params.append(overall_percent)
        
        if overall_message is not None:
            updates.append("overall_progress_message = %s")
            params.append(overall_message)
        
        # Subtask progress
        if subtask_percent is not None:
            updates.append("subtask_percent_complete = %s")
            params.append(subtask_percent)
        
        if subtask_message is not None:
            updates.append("subtask_progress_message = %s")
            params.append(subtask_message)
        
        if subtask_items_total is not None:
            updates.append("subtask_items_total = %s")
            params.append(subtask_items_total)
        
        if subtask_items_complete is not None:
            updates.append("subtask_items_complete = %s")
            params.append(subtask_items_complete)
            
            # Auto-calculate subtask percentage if both provided
            if subtask_items_total is not None and subtask_items_total > 0:
                subtask_pct = round((subtask_items_complete / subtask_items_total) * 100, 2)
                updates.append("subtask_percent_complete = %s")
                params.append(subtask_pct)
        
        # Special handling for FINISHED/FAILED status
        if status in ["FINISHED", "FAILED"]:
            updates.append("execution_end = %s")
            params.append(datetime.now())
        
        # Add run_id to params
        params.append(_run_id)
        
        # Execute update
        sql = f"""
            UPDATE pipeline_status
            SET {', '.join(updates)}
            WHERE run_id = %s
        """
        
        cursor.execute(sql, params)
        conn.commit()
        cursor.close()
        conn.close()
        
        # Also log to console (prefer subtask message, fallback to overall)
        log_message = subtask_message or overall_message
        if log_message:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] {log_message}")
        
    except Exception as e:
        print(f"Warning: Failed to update status: {e}", file=sys.stderr)


def track_finish(message="Script completed successfully"):
    """Finish status tracking (success)."""
    track_status(
        status="FINISHED",
        overall_percent=100,
        overall_message=message
    )


def track_task_progress(items_complete, items_total=None, message=None):
    """
    Update task progress during long-running operations.
    
    Args:
        items_complete: Number of items completed
        items_total: Total number of items (optional)
        message: Progress message (optional)
    
    Example:
        for i, state in enumerate(states, 1):
            process_state(state)
            track_task_progress(i, len(states), f"Processed {state}")
    """
    track_status(
        status="RUNNING",
        task_items_complete=items_complete,
        task_items_total=items_total,
        task_message=message
    )


def track_error(error_msg, error_detail=None):
    """Record failure in status tracking."""
    if _run_id is None:
        return
    
    try:
        conn = _get_monitor_connection()
        if conn is None:
            return
        
        cursor = conn.cursor()
        
        cursor.execute("""
            UPDATE pipeline_status
            SET 
                execution_status = %s,
                execution_end = %s,
                error_message = %s,
                error_detail = %s,
                last_update = %s
            WHERE run_id = %s
        """, (
            "FAILED",
            datetime.now(),
            error_msg,
            error_detail,
            datetime.now(),
            _run_id
        ))
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"ERROR: {error_msg}", file=sys.stderr)
        
    except Exception as e:
        print(f"Warning: Failed to record error: {e}", file=sys.stderr)


# Helper functions

def _get_monitor_connection():
    """Get connection to monitoring database."""
    try:
        # Read connection details from environment or config
        # For now, use same connection as main database
        conn_str = os.environ.get('MONITOR_DB_CONN')
        if conn_str:
            return psycopg2.connect(conn_str)
        
        # Fallback to individual parameters
        return psycopg2.connect(
            host=os.environ.get('MONITOR_DB_HOST', 'localhost'),
            port=int(os.environ.get('MONITOR_DB_PORT', 5432)),
            database=os.environ.get('MONITOR_DB_NAME', 'geodb'),
            user=os.environ.get('MONITOR_DB_USER', 'pipeline'),
            password=os.environ.get('MONITOR_DB_PASSWORD', '')
        )
    except Exception as e:
        print(f"Warning: Cannot connect to monitor database: {e}", 
              file=sys.stderr)
        return None


def _detect_task_stage(task_name):
    """Detect task stage from name."""
    if task_name.startswith('STATIC_'):
        return 'STATIC'
    elif script_name.startswith('DAILY_'):
        return 'DAILY'
    elif script_name.startswith('ANNUAL_DEC_'):
        return 'ANNUAL_DEC'
    elif script_name.startswith('ANNUAL_SEPT_'):
        return 'ANNUAL_SEPT'
    elif script_name.startswith('ANNUAL_JUNE_'):
        return 'ANNUAL_JUNE'
    elif script_name.startswith('PERIODIC_'):
        return 'PERIODIC'
    elif script_name.startswith('PREREQ_'):
        return 'PREREQ'
    return 'UNKNOWN'


def _get_git_commit():
    """Get current git commit hash."""
    try:
        result = subprocess.run(
            ['git', 'rev-parse', 'HEAD'],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except:
        return None


def _get_env_json():
    """Get relevant environment variables as JSON."""
    env_vars = {
        'BDC_DOWNLOAD_PATH': os.environ.get('BDC_DOWNLOAD_PATH'),
        'PYTHONPATH': os.environ.get('PYTHONPATH'),
        'PATH': os.environ.get('PATH')
    }
    return json.dumps(env_vars)
```

### 3. Script Modifications

#### Example: Modify Existing Script

**Before:**
```r
library(dplyr)
library(glue)
devtools::load_all()
con <- dbConnectBBC(mode="rw")

genter('processing state location data')

for(state_code in state_codes) {
  genter("loading file '{file}'...")
  locations <- read_csv(file)
  gexit()
  
  genter("writing data to database table '{table_name}'")
  dbWriteTable(con, table_name, locations)
  gexit()
}

gexit()
```

**After (with enhanced genter/gexit and task progress):**
```r
library(dplyr)
library(glue)
devtools::load_all()
con <- dbConnectBBC(mode="rw")

# Initialize tracking with total tasks
track_init("DAILY_01_BDC_Locations.R", total_tasks = length(state_codes) * 2)

genter('processing state location data')

for(i in seq_along(state_codes)) {
  state_code <- state_codes[i]
  
  genter("loading file for state '{state_code}'")
  locations <- read_csv(file)
  gexit()
  
  genter("writing data to database")
  # Track progress within this task (56 states total)
  track_task_progress(i, length(state_codes), "Writing {state_code}: {nrow(locations)} rows")
  dbWriteTable(con, table_name, locations)
  gexit()
}

track_finish("Successfully processed {length(state_codes)} states")
```

**What this provides:**
- **Overall Progress**: Subtask 23 of 112 (20%) - tracks `genter()` calls
- **Subtask Progress**: Writing state 12 of 56 (21%) - tracks items within current subtask
- **Dashboard shows both levels** for complete visibility

The enhanced functions automatically handle dual-level status tracking!

---

## Migration Path

### Phase 1: Infrastructure Setup (Week 1)

1. **Create database table** in `geodb`
   - Run schema creation script
   - Set up indexes
   - Configure permissions

2. **Implement R package functions**
   - Create `R/track_status.R`
   - Add to NAMESPACE
   - Write unit tests

3. **Implement Python module**
   - Create `inst/python/pipeline_tracker.py`
   - Add integration tests

4. **Test with pilot script**
   - Select one simple script (e.g., STATIC_02)
   - Add tracking calls
   - Verify database updates

### Phase 2: Script Migration (Weeks 2-3)

**Priority Order:**
1. DAILY scripts (highest visibility)
2. ANNUAL_DEC scripts (complex, benefit most)
3. ANNUAL_SEPT scripts
4. ANNUAL_JUNE scripts
5. STATIC scripts
6. PERIODIC scripts

**Migration Process per Script:**
1. Add `track_init()` at start
2. Verify `genter()`/`gexit()` calls are present
3. Add `track_finish()` at end
4. Add error handlers with `track_error()`
5. Test execution
6. Verify status updates in database

### Phase 3: Monitor Enhancement (Week 4)

1. **Update monitor dashboard** ([inst/pipeline-monitor/app.R](inst/pipeline-monitor/app.R))
   - Replace file-based status detection
   - Query `pipeline_status` table
   - Display real-time progress
   - Show task-level detail

2. **Add historical views**
   - Execution history page
   - Performance trends
   - Failure analysis

3. **Add alerting**
   - Email on failures
   - Slack notifications
   - Completion webhooks

### Phase 4: Advanced Features (Week 5+)

1. **Resource monitoring**
   - Memory tracking
   - CPU utilization
   - Disk I/O

2. **Dependency visualization**
   - Show script dependencies
   - Critical path analysis
   - Bottleneck identification

3. **Predictive completion**
   - Estimated completion times
   - Historical performance data
   - Alert on abnormal durations

---

## Benefits

### Immediate Benefits

1. **Accurate Process Detection**
   - No more false positives from `ps | grep`
   - PID tracking for exact process identification
   - Handles multiple concurrent runs

2. **Real-Time Progress**
   - Task-level visibility
   - Percent complete tracking
   - Meaningful progress messages

3. **Better Error Handling**
   - Capture error messages
   - Track failure context
   - Easier debugging

### Long-Term Benefits

1. **Performance Analytics**
   - Track execution times over time
   - Identify degrading performance
   - Optimize bottlenecks

2. **Operational Intelligence**
   - Success/failure rates
   - Mean time to completion
   - Resource utilization patterns

3. **Improved Reliability**
   - Detect hung processes
   - Automatic cleanup
   - Recovery automation

---

## Risks & Mitigation

### Risk 1: Database Connection Failures

**Impact:** Status tracking fails if monitoring database unavailable

**Mitigation:**
- Tracking failures are non-fatal (log warnings, continue execution)
- Connection timeout limits (5 seconds max)
- Fallback to file-based logging
- Monitor database has high availability

### Risk 2: Performance Overhead

**Impact:** Frequent database updates slow pipeline

**Mitigation:**
- Async/batched updates (not blocking)
- Update only at task boundaries (not per-row)
- Prepared statements for efficiency
- Monitoring database on fast SSD

### Risk 3: Schema Changes

**Impact:** Table structure changes break existing code

**Mitigation:**
- Version tracking in table
- Backward-compatible changes only
- Migration scripts for major changes
- Abstract database layer in R/Python code

### Risk 4: Script Migration Effort

**Impact:** 50+ scripts need modifications

**Mitigation:**
- Enhanced `genter()`/`gexit()` minimize changes
- Most scripts already use `genter()`/`gexit()`
- Gradual rollout (pilot → phased → complete)
- Scripts work without tracking (graceful degradation)

---

## Success Criteria

### Phase 1 Success (Infrastructure)
- ✅ Database table created and accessible
- ✅ R functions work in test script
- ✅ Python module works in test script
- ✅ Status visible in database queries

### Phase 2 Success (Migration)
- ✅ All DAILY scripts tracked
- ✅ All ANNUAL scripts tracked
- ✅ No pipeline failures due to tracking
- ✅ 95%+ of executions logged

### Phase 3 Success (Monitor)
- ✅ Dashboard shows real-time status
- ✅ Task-level progress visible
- ✅ Historical execution data available
- ✅ Users prefer new monitor over old

### Phase 4 Success (Advanced)
- ✅ Resource metrics captured
- ✅ Performance trends visible
- ✅ Alerting functional
- ✅ Dependency graph generated

---

## Appendices

### Appendix A: Example Queries

**Get current status of all scripts:**
```sql
SELECT DISTINCT ON (script_name)
    script_name,
    execution_status,
    execution_start,
    current_task,
    total_tasks,
    overall_percent_complete,
    overall_progress_message,
    task_name,
    task_percent_complete,
    task_progress_message,
    task_items_complete,
    task_items_total
FROM pipeline_status
ORDER BY script_name, execution_start DESC;
```

**Find long-running scripts:**
```sql
SELECT 
    script_name,
    execution_start,
    EXTRACT(EPOCH FROM (NOW() - execution_start)) / 60 AS runtime_minutes,
    overall_percent_complete,
    overall_progress_message,
    task_percent_complete,
    task_progress_message
FROM pipeline_status
WHERE execution_status IN ('STARTED', 'RUNNING')
    AND execution_start < NOW() - INTERVAL '30 minutes'
ORDER BY runtime_minutes DESC;
```

**Execution history with performance:**
```sql
SELECT 
    script_name,
    execution_start::DATE as run_date,
    COUNT(*) as runs,
    AVG(EXTRACT(EPOCH FROM (execution_end - execution_start)) / 60) as avg_minutes,
    MIN(EXTRACT(EPOCH FROM (execution_end - execution_start)) / 60) as min_minutes,
    MAX(EXTRACT(EPOCH FROM (execution_end - execution_start)) / 60) as max_minutes,
    COUNT(*) FILTER (WHERE execution_status = 'FAILED') as failures
FROM pipeline_status
WHERE execution_end IS NOT NULL
GROUP BY script_name, run_date
ORDER BY script_name, run_date DESC;
```

### Appendix B: Database Connection Configuration

Add to `~/.Renviron`:
```
MONITOR_DB_HOST=db.example.com
MONITOR_DB_PORT=5432
MONITOR_DB_NAME=geodb
MONITOR_DB_USER=pipeline_monitor
MONITOR_DB_PASSWORD=<secure_password>
```

Or use existing `bbcDB` package connection infrastructure with new connection type:
```r
dbConnectBBC <- function(mode = c("ro", "rw", "monitoring"), ...) {
  mode <- match.arg(mode)
  
  if (mode == "monitoring") {
    # Connect to geodb for status tracking
    conn_string <- get_monitor_connection_string()
    # ... connection logic
  }
  # ... existing ro/rw logic
}
```

---

## Review & Approval

**Please review this design and provide feedback on:**

1. ✅ Overall approach acceptable?
2. ✅ Database schema adequate?
3. ✅ Function signatures appropriate?
4. ✅ Migration timeline reasonable?
5. ✅ Any concerns or missing requirements?

**Next Steps After Approval:**
1. Create implementation task list (separate document)
2. Set up development branch
3. Create database table in dev environment
4. Begin Phase 1 implementation

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-20
