-- Process Reporter Database Schema for MySQL/MariaDB
-- Tables for collecting and storing process metrics for running tasks

-- ============================================================================
-- Table: process_metrics
-- Stores process resource usage snapshots over time
-- ============================================================================

CREATE TABLE IF NOT EXISTS tasker.process_metrics (
    metric_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id CHAR(36) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Main process info
    process_id INT NOT NULL,
    hostname VARCHAR(255) NOT NULL,
    is_alive BOOLEAN NOT NULL DEFAULT TRUE,
    process_start_time TIMESTAMP,              -- Process creation time for PID reuse detection
    
    -- Resource usage - CPU and Memory
    cpu_percent DECIMAL(5,2),                  -- CPU usage percentage
    cpu_cores INT,                             -- Number of CPU cores in system
    memory_mb DECIMAL(10,2),                   -- Memory (RSS) in MB
    memory_percent DECIMAL(5,2),               -- Memory usage percentage
    memory_vms_mb DECIMAL(10,2),               -- Virtual memory size in MB
    swap_mb DECIMAL(10,2),                     -- Swap usage in MB
    
    -- Resource usage - I/O
    read_bytes BIGINT,                         -- Cumulative bytes read
    write_bytes BIGINT,                        -- Cumulative bytes written
    read_count BIGINT,                         -- Number of read operations
    write_count BIGINT,                        -- Number of write operations
    io_wait_percent DECIMAL(5,2),              -- Percentage of time waiting for I/O
    
    -- Resource usage - System
    open_files INT,                            -- Number of open file descriptors
    num_fds INT,                               -- Total file descriptors
    num_threads INT,                           -- Number of threads in main process
    page_faults_minor BIGINT,                  -- Minor page faults (no I/O)
    page_faults_major BIGINT,                  -- Major page faults (disk I/O)
    num_ctx_switches_voluntary BIGINT,         -- Voluntary context switches
    num_ctx_switches_involuntary BIGINT,       -- Involuntary context switches
    
    -- Child process aggregates
    child_count INT DEFAULT 0,                 -- Number of child processes
    child_total_cpu_percent DECIMAL(8,2),      -- Sum of CPU% across all children
    child_total_memory_mb DECIMAL(12,2),       -- Sum of memory across all children
    
    -- Error tracking
    collection_error BOOLEAN DEFAULT FALSE,
    error_message TEXT,                        -- Error details if collection failed
    error_type VARCHAR(100),                   -- Error category
    
    -- Metadata
    reporter_version VARCHAR(50),              -- Version of the reporter tool
    collection_duration_ms INT,                -- Time taken to collect metrics
    
    INDEX idx_process_metrics_run_id (run_id),
    INDEX idx_process_metrics_timestamp (timestamp),
    INDEX idx_process_metrics_hostname (hostname),
    INDEX idx_process_metrics_process_id (process_id)
);

-- ============================================================================
-- Table: task_runs (simplified reference for foreign key)
-- This would typically be created by the main tasker schema
-- ============================================================================

CREATE TABLE IF NOT EXISTS tasker.task_runs (
    run_id CHAR(36) PRIMARY KEY,
    task_id VARCHAR(100) NOT NULL,
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP NULL,
    status VARCHAR(50) DEFAULT 'running',
    process_id INT,
    hostname VARCHAR(255),
    
    INDEX idx_task_runs_task_id (task_id),
    INDEX idx_task_runs_status (status),
    INDEX idx_task_runs_start_time (start_time)
);

-- Add foreign key constraint after both tables exist
ALTER TABLE tasker.process_metrics 
ADD CONSTRAINT fk_process_metrics_run_id 
FOREIGN KEY (run_id) REFERENCES tasker.task_runs(run_id) 
ON DELETE CASCADE;

-- ============================================================================
-- View: task_runs_with_latest_metrics
-- Combines task runs with their most recent process metrics
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
    UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(pm.timestamp) AS metrics_age_seconds
FROM tasker.task_runs tr
LEFT JOIN tasker.process_metrics pm ON pm.run_id = tr.run_id
AND pm.timestamp = (
    SELECT MAX(timestamp)
    FROM tasker.process_metrics pm2
    WHERE pm2.run_id = tr.run_id
);