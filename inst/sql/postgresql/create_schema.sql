-- tasker Schema for PostgreSQL
-- Task and Pipeline Execution Tracking

CREATE TABLE IF NOT EXISTS tasker.stages (
    stage_id SERIAL PRIMARY KEY,
    stage_name VARCHAR(100) NOT NULL UNIQUE,
    stage_order INTEGER,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stages_name ON tasker.stages(stage_name);
CREATE INDEX idx_stages_order ON tasker.stages(stage_order);

CREATE TABLE IF NOT EXISTS tasker.tasks (
    task_id SERIAL PRIMARY KEY,
    stage_id INTEGER REFERENCES tasker.stages(stage_id),
    task_name VARCHAR(255) NOT NULL,
    task_type VARCHAR(20),
    task_order INTEGER,
    description TEXT,
    script_path TEXT,
    script_filename VARCHAR(255),
    log_path TEXT,
    log_filename VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(stage_id, task_name)
);

CREATE INDEX idx_tasks_stage ON tasker.tasks(stage_id);
CREATE INDEX idx_tasks_name ON tasker.tasks(task_name);
CREATE INDEX idx_tasks_order ON tasker.tasks(task_order);

CREATE TABLE IF NOT EXISTS tasker.task_runs (
    run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id INTEGER NOT NULL REFERENCES tasker.tasks(task_id),
    
    -- Execution identification
    hostname VARCHAR(255) NOT NULL,
    process_id INTEGER NOT NULL,
    parent_pid INTEGER,
    
    -- Timing information
    start_time TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL,
    
    -- Overall task progress
    total_subtasks INTEGER,
    current_subtask INTEGER,
    overall_percent_complete NUMERIC(5,2),
    overall_progress_message TEXT,
    
    -- Resource tracking
    memory_mb INTEGER,
    cpu_percent NUMERIC(5,2),
    
    -- Error tracking
    error_message TEXT,
    error_detail TEXT,
    
    -- Metadata
    version VARCHAR(50),
    git_commit VARCHAR(40),
    user_name VARCHAR(100),
    environment JSONB,
    
    CONSTRAINT chk_task_status CHECK (status IN 
        ('NOT_STARTED', 'STARTED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED', 'CANCELLED'))
);

CREATE INDEX idx_task_runs_task ON tasker.task_runs(task_id);
CREATE INDEX idx_task_runs_status ON tasker.task_runs(status);
CREATE INDEX idx_task_runs_start ON tasker.task_runs(start_time);
CREATE INDEX idx_task_runs_hostname_pid ON tasker.task_runs(hostname, process_id);

CREATE TABLE IF NOT EXISTS tasker.subtask_progress (
    progress_id SERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES tasker.task_runs(run_id) ON DELETE CASCADE,
    
    -- Subtask identification
    subtask_number INTEGER NOT NULL,
    subtask_name VARCHAR(500),
    
    -- Status
    status VARCHAR(20) NOT NULL,
    
    -- Timing
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    last_update TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Progress within subtask
    percent_complete NUMERIC(5,2),
    progress_message TEXT,
    items_total BIGINT,
    items_complete BIGINT,
    
    -- Error tracking
    error_message TEXT,
    
    CONSTRAINT chk_subtask_status CHECK (status IN 
        ('NOT_STARTED', 'STARTED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED')),
    UNIQUE(run_id, subtask_number)
);

CREATE INDEX idx_subtask_progress_run ON tasker.subtask_progress(run_id);
CREATE INDEX idx_subtask_progress_number ON tasker.subtask_progress(subtask_number);
CREATE INDEX idx_subtask_progress_status ON tasker.subtask_progress(status);

-- Update timestamp triggers
CREATE OR REPLACE FUNCTION tasker.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stages_updated_at
    BEFORE UPDATE ON tasker.stages
    FOR EACH ROW
    EXECUTE FUNCTION tasker.update_updated_at();

CREATE TRIGGER tasks_updated_at
    BEFORE UPDATE ON tasker.tasks
    FOR EACH ROW
    EXECUTE FUNCTION tasker.update_updated_at();

-- Update last_update triggers
CREATE OR REPLACE FUNCTION tasker.update_last_update()
RETURNS TRIGGER AS $func$
BEGIN
    NEW.last_update = NOW();
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;

CREATE TRIGGER task_runs_last_update
    BEFORE UPDATE ON tasker.task_runs
    FOR EACH ROW
    EXECUTE FUNCTION tasker.update_last_update();

CREATE TRIGGER subtask_progress_last_update
    BEFORE UPDATE ON tasker.subtask_progress
    FOR EACH ROW
    EXECUTE FUNCTION tasker.update_last_update();

-- Views for easier querying
CREATE OR REPLACE VIEW tasker.current_task_status AS
SELECT 
    s.stage_name,
    s.stage_order,
    t.task_name,
    t.task_type,
    t.task_order,
    tr.run_id,
    tr.hostname,
    tr.process_id,
    tr.status,
    tr.start_time,
    tr.end_time,
    tr.last_update,
    tr.total_subtasks,
    tr.current_subtask,
    tr.overall_percent_complete,
    tr.overall_progress_message,
    t.script_path,
    t.script_filename,
    t.log_path,
    t.log_filename,
    tr.error_message
FROM tasker.task_runs tr
JOIN tasker.tasks t ON tr.task_id = t.task_id
JOIN tasker.stages s ON t.stage_id = s.stage_id
WHERE tr.run_id IN (
    SELECT run_id 
    FROM tasker.task_runs tr2 
    WHERE tr2.task_id = tr.task_id 
    ORDER BY tr2.start_time DESC 
    LIMIT 1
);

CREATE OR REPLACE VIEW tasker.active_tasks AS
SELECT * FROM tasker.current_task_status
WHERE status IN ('STARTED', 'RUNNING')
ORDER BY stage_order, task_order;

-- View combining current task status with latest process metrics
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

COMMENT ON SCHEMA tasker IS 'Task and pipeline execution tracking';
COMMENT ON TABLE tasker.stages IS 'Pipeline stages (e.g., PREREQ, STATIC, DAILY)';
COMMENT ON TABLE tasker.tasks IS 'Tasks within stages (e.g., specific scripts)';
COMMENT ON TABLE tasker.task_runs IS 'Individual executions of tasks';
COMMENT ON TABLE tasker.subtask_progress IS 'Progress tracking for subtasks within a task run';
