-- Process Reporter Database Schema
-- Tables for collecting and storing process metrics for running tasks

-- ============================================================================
-- Table: process_metrics
-- Stores process resource usage snapshots over time
-- ============================================================================

CREATE TABLE IF NOT EXISTS tasker.process_metrics (
    metric_id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES tasker.task_runs(run_id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Main process info
    process_id INTEGER NOT NULL,
    hostname VARCHAR(255) NOT NULL,
    is_alive BOOLEAN NOT NULL DEFAULT TRUE,
    process_start_time TIMESTAMPTZ,         -- Process creation time for PID reuse detection
    
    -- Resource usage - CPU and Memory
    cpu_percent NUMERIC(5,2),               -- CPU usage percentage
    cpu_cores INTEGER,                      -- Number of CPU cores in system
    memory_mb NUMERIC(10,2),                -- Memory (RSS) in MB
    memory_percent NUMERIC(5,2),            -- Memory usage percentage
    memory_vms_mb NUMERIC(10,2),            -- Virtual memory size in MB
    swap_mb NUMERIC(10,2),                  -- Swap usage in MB
    
    -- Resource usage - I/O
    read_bytes BIGINT,                      -- Cumulative bytes read
    write_bytes BIGINT,                     -- Cumulative bytes written
    read_count BIGINT,                      -- Number of read operations
    write_count BIGINT,                     -- Number of write operations
    io_wait_percent NUMERIC(5,2),           -- Percentage of time waiting for I/O
    
    -- Resource usage - System
    open_files INTEGER,                     -- Number of open file descriptors
    num_fds INTEGER,                        -- Total file descriptors
    num_threads INTEGER,                    -- Number of threads in main process
    page_faults_minor BIGINT,               -- Minor page faults (no I/O)
    page_faults_major BIGINT,               -- Major page faults (disk I/O)
    num_ctx_switches_voluntary BIGINT,      -- Voluntary context switches
    num_ctx_switches_involuntary BIGINT,    -- Involuntary context switches
    
    -- Child process aggregates
    child_count INTEGER DEFAULT 0,          -- Number of child processes
    child_total_cpu_percent NUMERIC(8,2),   -- Sum of CPU% across all children
    child_total_memory_mb NUMERIC(12,2),    -- Sum of memory across all children
    
    -- Error tracking
    collection_error BOOLEAN DEFAULT FALSE,
    error_message TEXT,                     -- Error details if collection failed
    error_type VARCHAR(50),                 -- Error classification
    
    -- Metadata
    reporter_version VARCHAR(50),
    collection_duration_ms INTEGER,         -- Time to collect this metric
    
    CONSTRAINT process_metrics_run_timestamp_idx UNIQUE (run_id, timestamp)
);

-- Indexes for process_metrics
CREATE INDEX IF NOT EXISTS idx_process_metrics_run_id ON tasker.process_metrics(run_id);
CREATE INDEX IF NOT EXISTS idx_process_metrics_timestamp ON tasker.process_metrics(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_process_metrics_hostname ON tasker.process_metrics(hostname);
CREATE INDEX IF NOT EXISTS idx_process_metrics_run_timestamp ON tasker.process_metrics(run_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_process_metrics_errors ON tasker.process_metrics(run_id, timestamp) WHERE collection_error = TRUE;
CREATE INDEX IF NOT EXISTS idx_process_metrics_cleanup ON tasker.process_metrics(timestamp) WHERE is_alive = FALSE;

-- ============================================================================
-- Table: reporter_status
-- Tracks active process reporters (one per host)
-- ============================================================================

CREATE TABLE IF NOT EXISTS tasker.reporter_status (
    reporter_id SERIAL PRIMARY KEY,
    hostname VARCHAR(255) NOT NULL UNIQUE,
    process_id INTEGER NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    version VARCHAR(50),
    config JSONB DEFAULT '{}'::JSONB,
    shutdown_requested BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_reporter_hostname ON tasker.reporter_status(hostname);
CREATE INDEX IF NOT EXISTS idx_reporter_heartbeat ON tasker.reporter_status(last_heartbeat DESC);

-- ============================================================================
-- Table: process_metrics_retention
-- Tracks retention policy and cleanup status
-- ============================================================================

CREATE TABLE IF NOT EXISTS tasker.process_metrics_retention (
    retention_id SERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES tasker.task_runs(run_id) ON DELETE CASCADE,
    task_completed_at TIMESTAMPTZ NOT NULL,
    metrics_delete_after TIMESTAMPTZ NOT NULL,  -- completion + 30 days
    metrics_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    metrics_count INTEGER,                     -- Number of metrics deleted
    
    CONSTRAINT unique_run_retention UNIQUE (run_id)
);

CREATE INDEX IF NOT EXISTS idx_retention_delete_after ON tasker.process_metrics_retention(metrics_delete_after) 
    WHERE metrics_deleted = FALSE;

-- ============================================================================
-- Index on task_runs for Active Tasks Query
-- Optimize the reporter's query for active tasks on a specific host
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_task_runs_active_host ON tasker.task_runs(hostname, status) 
    WHERE status IN ('RUNNING', 'STARTED');

-- ============================================================================
-- View: task_runs_with_latest_metrics
-- Join task runs with their most recent process metrics
-- ============================================================================

CREATE OR REPLACE VIEW tasker.task_runs_with_latest_metrics AS
SELECT 
    tr.*,
    pm.cpu_percent AS metrics_cpu_percent,
    pm.cpu_cores AS metrics_cpu_cores,
    pm.memory_mb AS metrics_memory_mb,
    pm.memory_percent AS metrics_memory_percent,
    pm.child_count AS metrics_child_count,
    pm.child_total_cpu_percent AS metrics_child_total_cpu_percent,
    pm.child_total_memory_mb AS metrics_child_total_memory_mb,
    pm.is_alive AS metrics_is_alive,
    pm.collection_error AS metrics_collection_error,
    pm.error_message AS metrics_error_message,
    pm.error_type AS metrics_error_type,
    pm.timestamp AS metrics_timestamp,
    EXTRACT(EPOCH FROM (NOW() - pm.timestamp))::INTEGER AS metrics_age_seconds
FROM tasker.task_runs tr
LEFT JOIN LATERAL (
    SELECT *
    FROM tasker.process_metrics
    WHERE process_metrics.run_id = tr.run_id
    ORDER BY timestamp DESC
    LIMIT 1
) pm ON TRUE;

-- ============================================================================
-- View: task_runs_with_aggregated_metrics
-- Join task runs with latest metrics AND aggregated statistics (avg/max)
-- ============================================================================

CREATE OR REPLACE VIEW tasker.task_runs_with_aggregated_metrics AS
SELECT 
    tr.*,
    -- Latest metrics (current values)
    pm_latest.cpu_percent AS metrics_cpu_percent,
    pm_latest.cpu_cores AS metrics_cpu_cores,
    pm_latest.memory_mb AS metrics_memory_mb,
    pm_latest.memory_percent AS metrics_memory_percent,
    pm_latest.child_count AS metrics_child_count,
    pm_latest.child_total_cpu_percent AS metrics_child_total_cpu_percent,
    pm_latest.child_total_memory_mb AS metrics_child_total_memory_mb,
    pm_latest.is_alive AS metrics_is_alive,
    pm_latest.collection_error AS metrics_collection_error,
    pm_latest.error_message AS metrics_error_message,
    pm_latest.error_type AS metrics_error_type,
    pm_latest.timestamp AS metrics_timestamp,
    EXTRACT(EPOCH FROM (NOW() - pm_latest.timestamp))::INTEGER AS metrics_age_seconds,
    -- Aggregated metrics (average values)
    pm_agg.avg_cpu_percent,
    pm_agg.avg_memory_mb,
    pm_agg.avg_memory_percent,
    pm_agg.avg_child_count,
    pm_agg.avg_child_total_cpu_percent,
    pm_agg.avg_child_total_memory_mb,
    -- Aggregated metrics (maximum values)
    pm_agg.max_cpu_percent,
    pm_agg.max_memory_mb,
    pm_agg.max_memory_percent,
    pm_agg.max_child_count,
    pm_agg.max_child_total_cpu_percent,
    pm_agg.max_child_total_memory_mb,
    pm_agg.metrics_count
FROM tasker.task_runs tr
LEFT JOIN LATERAL (
    SELECT *
    FROM tasker.process_metrics
    WHERE process_metrics.run_id = tr.run_id
    ORDER BY timestamp DESC
    LIMIT 1
) pm_latest ON TRUE
LEFT JOIN LATERAL (
    SELECT 
        AVG(cpu_percent) AS avg_cpu_percent,
        AVG(memory_mb) AS avg_memory_mb,
        AVG(memory_percent) AS avg_memory_percent,
        AVG(child_count) AS avg_child_count,
        AVG(child_total_cpu_percent) AS avg_child_total_cpu_percent,
        AVG(child_total_memory_mb) AS avg_child_total_memory_mb,
        MAX(cpu_percent) AS max_cpu_percent,
        MAX(memory_mb) AS max_memory_mb,
        MAX(memory_percent) AS max_memory_percent,
        MAX(child_count) AS max_child_count,
        MAX(child_total_cpu_percent) AS max_child_total_cpu_percent,
        MAX(child_total_memory_mb) AS max_child_total_memory_mb,
        COUNT(*)::INTEGER AS metrics_count
    FROM tasker.process_metrics
    WHERE process_metrics.run_id = tr.run_id
      AND collection_error = FALSE  -- Only use successful metrics
) pm_agg ON TRUE;
