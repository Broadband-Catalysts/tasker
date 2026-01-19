-- Process Reporter Database Schema for SQLite
-- Tables for collecting and storing process metrics for running tasks

-- ============================================================================
-- Table: process_metrics
-- Stores process resource usage snapshots over time
-- ============================================================================

CREATE TABLE IF NOT EXISTS process_metrics (
    metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT NOT NULL REFERENCES task_runs(run_id) ON DELETE CASCADE,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    
    -- Main process info
    process_id INTEGER NOT NULL,
    hostname TEXT NOT NULL,
    is_alive INTEGER NOT NULL DEFAULT 1,  -- SQLite uses INTEGER for boolean
    process_start_time TEXT,               -- Process creation time for PID reuse detection
    
    -- Resource usage - CPU and Memory
    cpu_percent REAL,                      -- CPU usage percentage
    cpu_cores INTEGER,                     -- Number of CPU cores in system
    memory_mb REAL,                        -- Memory (RSS) in MB
    memory_percent REAL,                   -- Memory usage percentage
    memory_vms_mb REAL,                    -- Virtual memory size in MB
    swap_mb REAL,                          -- Swap usage in MB
    
    -- Resource usage - I/O
    read_bytes INTEGER,                    -- Cumulative bytes read
    write_bytes INTEGER,                   -- Cumulative bytes written
    read_count INTEGER,                    -- Number of read operations
    write_count INTEGER,                   -- Number of write operations
    io_wait_percent REAL,                 -- Percentage of time waiting for I/O
    
    -- Resource usage - System
    open_files INTEGER,                    -- Number of open file descriptors
    num_fds INTEGER,                       -- Total file descriptors
    num_threads INTEGER,                   -- Number of threads in main process
    page_faults_minor INTEGER,             -- Minor page faults (no I/O)
    page_faults_major INTEGER,             -- Major page faults (disk I/O)
    num_ctx_switches_voluntary INTEGER,    -- Voluntary context switches
    num_ctx_switches_involuntary INTEGER,  -- Involuntary context switches
    
    -- Child process aggregates
    child_count INTEGER DEFAULT 0,        -- Number of child processes
    child_total_cpu_percent REAL,         -- Sum of CPU% across all children
    child_total_memory_mb REAL,           -- Sum of memory across all children
    
    -- Error tracking
    collection_error INTEGER DEFAULT 0,   -- SQLite uses INTEGER for boolean
    error_message TEXT,                    -- Error details if collection failed
    error_type TEXT,                       -- Error classification
    
    -- Metadata
    reporter_version TEXT,
    collection_duration_ms INTEGER,       -- Time to collect this metric
    
    UNIQUE (run_id, timestamp)
);

-- Indexes for process_metrics
CREATE INDEX IF NOT EXISTS idx_process_metrics_run_id ON process_metrics(run_id);
CREATE INDEX IF NOT EXISTS idx_process_metrics_timestamp ON process_metrics(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_process_metrics_hostname ON process_metrics(hostname);
CREATE INDEX IF NOT EXISTS idx_process_metrics_run_timestamp ON process_metrics(run_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_process_metrics_errors ON process_metrics(run_id, timestamp) WHERE collection_error = 1;
CREATE INDEX IF NOT EXISTS idx_process_metrics_cleanup ON process_metrics(timestamp) WHERE is_alive = 0;

-- ============================================================================
-- Table: process_reporter_status  
-- Tracks active process reporters (one per host)
-- ============================================================================

CREATE TABLE IF NOT EXISTS process_reporter_status (
    reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
    hostname TEXT NOT NULL UNIQUE,
    process_id INTEGER NOT NULL,
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
    version TEXT,
    config TEXT DEFAULT '{}',              -- SQLite uses TEXT for JSON
    shutdown_requested INTEGER DEFAULT 0   -- SQLite uses INTEGER for boolean
);

CREATE INDEX IF NOT EXISTS idx_reporter_hostname ON reporter_status(hostname);
CREATE INDEX IF NOT EXISTS idx_reporter_heartbeat ON reporter_status(last_heartbeat DESC);

-- ============================================================================
-- Table: process_metrics_retention
-- Tracks retention policy and cleanup status
-- ============================================================================

CREATE TABLE IF NOT EXISTS process_metrics_retention (
    retention_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT NOT NULL REFERENCES task_runs(run_id) ON DELETE CASCADE,
    task_completed_at TEXT NOT NULL,
    metrics_delete_after TEXT NOT NULL,    -- completion + 30 days
    metrics_deleted INTEGER DEFAULT 0,     -- SQLite uses INTEGER for boolean
    deleted_at TEXT,
    metrics_count INTEGER,                 -- Number of metrics deleted
    
    UNIQUE (run_id)
);

CREATE INDEX IF NOT EXISTS idx_retention_delete_after ON process_metrics_retention(metrics_delete_after) 
    WHERE metrics_deleted = 0;

-- ============================================================================
-- Index on task_runs for Active Tasks Query
-- Optimize the reporter's query for active tasks on a specific host
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_task_runs_active_host ON task_runs(hostname, status) 
    WHERE status IN ('RUNNING', 'STARTED');

-- ============================================================================
-- View: task_runs_with_latest_metrics
-- Join task runs with their most recent process metrics
-- SQLite version using subquery approach (no LATERAL)
-- ============================================================================

CREATE VIEW IF NOT EXISTS task_runs_with_latest_metrics AS
SELECT 
    tr.*,
    pm.cpu_percent,
    pm.cpu_cores,
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
    CAST((julianday('now') - julianday(pm.timestamp)) * 86400 AS INTEGER) AS metrics_age_seconds
FROM task_runs tr
LEFT JOIN process_metrics pm ON pm.run_id = tr.run_id 
    AND pm.timestamp = (
        SELECT MAX(timestamp) 
        FROM process_metrics pm2 
        WHERE pm2.run_id = tr.run_id
    );