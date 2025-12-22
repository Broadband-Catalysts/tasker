-- tasker Schema for SQLite
-- Task and Pipeline Execution Tracking

CREATE TABLE IF NOT EXISTS stages (
    stage_id INTEGER PRIMARY KEY AUTOINCREMENT,
    stage_name VARCHAR(100) NOT NULL UNIQUE,
    stage_order INTEGER,
    description TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_stages_name ON stages(stage_name);
CREATE INDEX IF NOT EXISTS idx_stages_order ON stages(stage_order);

CREATE TABLE IF NOT EXISTS tasks (
    task_id INTEGER PRIMARY KEY AUTOINCREMENT,
    stage_id INTEGER REFERENCES stages(stage_id),
    task_name VARCHAR(255) NOT NULL,
    task_type VARCHAR(20),
    task_order INTEGER,
    description TEXT,
    script_path TEXT,
    script_filename VARCHAR(255),
    log_path TEXT,
    log_filename VARCHAR(255),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(stage_id, task_name)
);

CREATE INDEX IF NOT EXISTS idx_tasks_stage ON tasks(stage_id);
CREATE INDEX IF NOT EXISTS idx_tasks_name ON tasks(task_name);
CREATE INDEX IF NOT EXISTS idx_tasks_order ON tasks(task_order);

CREATE TABLE IF NOT EXISTS task_runs (
    run_id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    task_id INTEGER NOT NULL REFERENCES tasks(task_id),
    
    -- Execution identification
    hostname VARCHAR(255) NOT NULL,
    process_id INTEGER NOT NULL,
    parent_pid INTEGER,
    
    -- Timing information
    start_time TEXT,
    end_time TEXT,
    last_update TEXT NOT NULL DEFAULT (datetime('now')),
    
    -- Status tracking
    status VARCHAR(20) NOT NULL,
    
    -- Overall task progress
    total_subtasks INTEGER,
    current_subtask INTEGER,
    overall_percent_complete REAL,
    overall_progress_message TEXT,
    
    -- Resource tracking
    memory_mb INTEGER,
    cpu_percent REAL,
    
    -- Error tracking
    error_message TEXT,
    error_detail TEXT,
    
    -- Metadata
    version VARCHAR(50),
    git_commit VARCHAR(40),
    user_name VARCHAR(100),
    environment TEXT,  -- JSON as TEXT in SQLite
    
    CHECK (status IN 
        ('NOT_STARTED', 'STARTED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED', 'CANCELLED'))
);

CREATE INDEX IF NOT EXISTS idx_task_runs_task ON task_runs(task_id);
CREATE INDEX IF NOT EXISTS idx_task_runs_status ON task_runs(status);
CREATE INDEX IF NOT EXISTS idx_task_runs_start ON task_runs(start_time);
CREATE INDEX IF NOT EXISTS idx_task_runs_hostname_pid ON task_runs(hostname, process_id);

CREATE TABLE IF NOT EXISTS subtask_progress (
    progress_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT NOT NULL REFERENCES task_runs(run_id) ON DELETE CASCADE,
    
    -- Subtask identification
    subtask_number INTEGER NOT NULL,
    subtask_name VARCHAR(500),
    
    -- Status
    status VARCHAR(20) NOT NULL,
    
    -- Timing
    start_time TEXT,
    end_time TEXT,
    last_update TEXT NOT NULL DEFAULT (datetime('now')),
    
    -- Progress within subtask
    percent_complete REAL,
    progress_message TEXT,
    items_total INTEGER,
    items_complete INTEGER,
    
    -- Error tracking
    error_message TEXT,
    
    CHECK (status IN 
        ('NOT_STARTED', 'STARTED', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED')),
    UNIQUE(run_id, subtask_number)
);

CREATE INDEX IF NOT EXISTS idx_subtask_progress_run ON subtask_progress(run_id);
CREATE INDEX IF NOT EXISTS idx_subtask_progress_number ON subtask_progress(subtask_number);
CREATE INDEX IF NOT EXISTS idx_subtask_progress_status ON subtask_progress(status);

-- Update timestamp triggers for SQLite
CREATE TRIGGER IF NOT EXISTS stages_insert_timestamps
    AFTER INSERT ON stages
    FOR EACH ROW
BEGIN
    UPDATE stages 
    SET created_at = datetime('now'),
        updated_at = datetime('now')
    WHERE stage_id = NEW.stage_id;
END;

CREATE TRIGGER IF NOT EXISTS stages_updated_at
    AFTER UPDATE ON stages
    FOR EACH ROW
BEGIN
    UPDATE stages SET updated_at = datetime('now') WHERE stage_id = NEW.stage_id;
END;

CREATE TRIGGER IF NOT EXISTS tasks_insert_timestamps
    AFTER INSERT ON tasks
    FOR EACH ROW
BEGIN
    UPDATE tasks 
    SET created_at = datetime('now'),
        updated_at = datetime('now')
    WHERE task_id = NEW.task_id;
END;

CREATE TRIGGER IF NOT EXISTS tasks_updated_at
    AFTER UPDATE ON tasks
    FOR EACH ROW
BEGIN
    UPDATE tasks SET updated_at = datetime('now') WHERE task_id = NEW.task_id;
END;

CREATE TRIGGER IF NOT EXISTS task_runs_insert_timestamp
    AFTER INSERT ON task_runs
    FOR EACH ROW
BEGIN
    UPDATE task_runs 
    SET last_update = datetime('now')
    WHERE run_id = NEW.run_id;
END;

CREATE TRIGGER IF NOT EXISTS task_runs_last_update
    AFTER UPDATE ON task_runs
    FOR EACH ROW
BEGIN
    UPDATE task_runs SET last_update = datetime('now') WHERE run_id = NEW.run_id;
END;

CREATE TRIGGER IF NOT EXISTS subtask_progress_insert_timestamp
    AFTER INSERT ON subtask_progress
    FOR EACH ROW
BEGIN
    UPDATE subtask_progress 
    SET last_update = datetime('now')
    WHERE progress_id = NEW.progress_id;
END;

CREATE TRIGGER IF NOT EXISTS subtask_progress_last_update
    AFTER UPDATE ON subtask_progress
    FOR EACH ROW
BEGIN
    UPDATE subtask_progress SET last_update = datetime('now') WHERE progress_id = NEW.progress_id;
END;

-- Views for easier querying
CREATE VIEW IF NOT EXISTS current_task_status AS
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
FROM task_runs tr
JOIN tasks t ON tr.task_id = t.task_id
JOIN stages s ON t.stage_id = s.stage_id
WHERE tr.run_id IN (
    SELECT run_id 
    FROM task_runs tr2 
    WHERE tr2.task_id = tr.task_id 
    ORDER BY tr2.start_time DESC 
    LIMIT 1
);

CREATE VIEW IF NOT EXISTS active_tasks AS
SELECT * FROM current_task_status
WHERE status IN ('STARTED', 'RUNNING')
ORDER BY stage_order, task_order;
