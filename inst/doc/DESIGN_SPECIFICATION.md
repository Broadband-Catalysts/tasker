# Tasker Design Specification

**Package:** tasker  
**Version:** 0.1.0  
**Author:** Gregory Warnes  
**Last Updated:** December 26, 2025

## Executive Summary

The `tasker` package provides a comprehensive task and pipeline execution tracking system for R projects. It enables hierarchical tracking of computational workflows through a PostgreSQL or SQLite database backend, supporting real-time progress monitoring, error tracking, and execution history management. The system is designed for complex data processing pipelines that require reliable state management, progress reporting, and post-mortem analysis.

The package implements a **4-level hierarchy** for granular progress tracking:
- **Stages**: Logical groupings of related tasks (e.g., "PREREQ", "STATIC", "DAILY")
- **Tasks**: Individual units of work within a stage (e.g., "Build FCC Database")
- **Subtasks**: Subdivisions of tasks for detailed progress tracking (e.g., "Process all counties")
- **Items**: Individual work items within subtasks (e.g., individual counties being processed)

This hierarchical design enables both coarse-grained pipeline monitoring and fine-grained progress tracking, particularly valuable for parallel processing workloads where multiple workers process individual items concurrently.

---

## 1. Purpose and Scope

### 1.1 Problem Statement

Modern data processing pipelines often involve:
- Long-running tasks spanning hours or days
- Multi-stage workflows with complex dependencies
- Parallel processing across multiple workers
- Need for real-time progress monitoring
- Requirement for execution history and audit trails
- Error tracking and recovery mechanisms

Traditional logging approaches fail to provide:
- Structured, queryable execution status
- Real-time progress visibility
- Historical trend analysis
- Hierarchical task decomposition
- Database-backed persistence

### 1.2 Solution Overview

`tasker` provides a database-backed tracking system with:
- **4-level hierarchy**: Stages → Tasks → Subtasks → Items
- **Item-level progress**: Track individual work items within subtasks for parallel processing
- **Atomic updates**: Thread-safe item counter increments for concurrent workers
- **Process tree monitoring**: Track main process + all child workers (aggregate metrics)
- **Resource watchdog**: Automatic system resource monitoring and orphaned worker cleanup
- **Real-time monitoring**: Live progress updates via Shiny dashboard
- **Persistent storage**: PostgreSQL or SQLite backend
- **Flexible configuration**: YAML files, environment variables, or direct parameters
- **Rich metadata**: Timing, resource usage, errors, git commits, versions
- **Query API**: Comprehensive functions for status retrieval and history analysis

### 1.3 Use Cases

- **ETL Pipelines**: Track extract, transform, load operations
- **Scientific Computing**: Monitor long-running simulations and analyses
- **Data Processing**: Track batch processing jobs with multiple stages
- **Build Systems**: Monitor complex build and deployment workflows
- **Machine Learning**: Track model training and evaluation pipelines

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌────────────────────────────────────────────────────────┐
│                      R Application Layer               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Task Scripts │  │ Pipeline Mgr │  │ Monitoring   │  │
│  │              │  │              │  │ Dashboard    │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                 │          │
└─────────┼─────────────────┼─────────────────┼──────────┘
          │                 │                 │
          └─────────────────┼─────────────────┘
                            │
                   ┌────────▼─────────┐
                   │   tasker R API   │
                   │                  │
                   │  - Config Mgmt   │
                   │  - Task Start    │
                   │  - Progress Upd  │
                   │  - Status Query  │
                   │  - Registration  │
                   └────────┬─────────┘
                            │
                   ┌────────▼─────────┐
                   │  DBI/RPostgres   │
                   │    RSQLite       │
                   └────────┬─────────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
     ┌────────▼─────────┐       ┌─────────▼────────┐
     │   PostgreSQL     │       │      SQLite      │
     │                  │       │                  │
     │  - tasker schema │       │  - Local file DB │
     │  - 4 tables      │       │  - 4 tables      │
     │  - 2 views       │       │  - 2 views       │
     └──────────────────┘       └──────────────────┘
```

### 2.2 Component Overview

| Component                  | Purpose                                  | Technology            |
|----------------------------|------------------------------------------|-----------------------|
| **Configuration Manager**  | Load and validate connection settings    | R, YAML               |
| **Schema Initializer**     | Create database schema and objects       | SQL, DBI              |
| **Task Registry**          | Register stages and tasks                | R, SQL                |
| **Execution Tracker**      | Track task runs and subtask progress     | R, SQL                |
| **Query API**              | Retrieve status and history              | R, SQL, dplyr         |
| **Monitoring Dashboard**   | Real-time visual monitoring              | Shiny, DT             |
| **Database Backend**       | Persistent storage                       | PostgreSQL or SQLite  |

---

## 3. Data Model

### 3.1 Entity-Relationship Diagram

```
┌──────────────┐
│   stages     │
│──────────────│
│ stage_id (PK)│◄────┐
│ stage_name   │     │
│ stage_order  │     │
│ description  │     │
│ created_at   │     │
│ updated_at   │     │
└──────────────┘     │
                     │
                     │ 1:N
                     │
┌──────────────┐     │
│    tasks     │     │
│──────────────│     │
│ task_id (PK) │◄────┼────┐
│ stage_id (FK)├─────┘    │
│ task_name    │          │
│ task_type    │          │
│ task_order   │          │
│ description  │          │
│ script_path  │          │
│ log_path     │          │
│ created_at   │          │
│ updated_at   │          │
└──────────────┘          │
                          │ 1:N
                          │
┌──────────────┐          │
│  task_runs   │          │
│──────────────│          │
│ run_id (PK)  │◄─────────┼────┐
│ task_id (FK) ├──────────┘    │
│ hostname     │               │
│ process_id   │               │
│ start_time   │               │
│ end_time     │               │
│ status       │               │
│ progress_%   │               │
│ error_msg    │               │
│ version      │               │
│ git_commit   │               │
│ ...          │               │
└──────────────┘               │
                               │ 1:N
                               │
┌──────────────────┐           │
│ subtask_progress │           │
│──────────────────│           │
│ progress_id (PK) │           │
│ run_id (FK)      ├───────────┘
│ subtask_number   │           │
│ subtask_name     │           │
│ status           │           │
│ start_time       │           │
│ end_time         │           │
│ percent_complete │           │
│ items_total      │◄─── Item-level tracking
│ items_complete   │◄─── for parallel workers
│ progress_message │           │
│ error_message    │           │
└──────────────────┘           │
                               │
┌────────────────────┐         │
│ resource_snapshots │         │
│────────────────────│         │
│ snapshot_id (PK)   │         │
│ run_id (FK)        ├─────────┘
│ timestamp          │
│ process_count      │◄─── Process tree metrics
│ total_cpu_percent  │◄─── Aggregate CPU%
│ total_memory_gb    │◄─── Aggregate memory
│ total_memory_pct   │◄─── % of system memory
│ system_memory_gb   │
│ system_cpu_count   │
└────────────────────┘
```

### 3.2 Table Specifications

#### 3.2.1 stages

Defines logical groupings of related tasks.

| Column         | Type             | Constraints             | Description                           |
|----------------|------------------|-------------------------|---------------------------------------|
| `stage_id`     | SERIAL/INTEGER   | PRIMARY KEY             | Auto-incrementing identifier          |
| `stage_name`   | VARCHAR(100)     | NOT NULL, UNIQUE        | Stage name (e.g., "PREREQ", "STATIC") |
| `stage_order`  | INTEGER          |                         | Execution order                       |
| `description`  | TEXT             |                         | Stage description                     |
| `created_at`   | TIMESTAMPTZ/TEXT | NOT NULL, DEFAULT NOW() | Creation timestamp                    |
| `updated_at`   | TIMESTAMPTZ/TEXT | NOT NULL, DEFAULT NOW() | Last update timestamp                 |

**Indexes:**
- `idx_stages_name` on `stage_name`
- `idx_stages_order` on `stage_order`

#### 3.2.2 tasks

Defines individual tasks within stages.

| Column            | Type             | Constraints              | Description                           |
|-------------------|------------------|--------------------------|---------------------------------------|
| `task_id`         | SERIAL/INTEGER   | PRIMARY KEY              | Auto-incrementing identifier          |
| `stage_id`        | INTEGER          | FOREIGN KEY → stages     | Parent stage                          |
| `task_name`       | VARCHAR(255)     | NOT NULL                 | Task name                             |
| `task_type`       | VARCHAR(20)      |                          | Type: "R", "python", "sh", etc.       |
| `task_order`      | INTEGER          |                          | Execution order within stage          |
| `description`     | TEXT             |                          | Task description                      |
| `script_path`     | TEXT             |                          | Path to script directory              |
| `script_filename` | VARCHAR(255)     |                          | Script filename                       |
| `log_path`        | TEXT             |                          | Path to log directory                 |
| `log_filename`    | VARCHAR(255)     |                          | Log filename                          |
| `created_at`      | TIMESTAMPTZ/TEXT | NOT NULL, DEFAULT NOW()  | Creation timestamp                    |
| `updated_at`      | TIMESTAMPTZ/TEXT | NOT NULL, DEFAULT NOW()  | Last update timestamp                 |

**Constraints:**
- `UNIQUE(stage_id, task_name)`

**Indexes:**
- `idx_tasks_stage` on `stage_id`
- `idx_tasks_name` on `task_name`
- `idx_tasks_order` on `task_order`

#### 3.2.3 task_runs

Records individual task execution instances.

| Column                       | Type             | Constraints                     | Description                             |
|------------------------------|------------------|---------------------------------|-----------------------------------------|
| `run_id`                     | UUID/TEXT        | PRIMARY KEY                     | Unique run identifier                   |
| `task_id`                    | INTEGER          | NOT NULL, FOREIGN KEY → tasks   | Task being executed                     |
| `hostname`                   | VARCHAR(255)     | NOT NULL                        | Execution host                          |
| `process_id`                 | INTEGER          | NOT NULL                        | Process ID                              |
| `parent_pid`                 | INTEGER          |                                 | Parent process ID                       |
| `start_time`                 | TIMESTAMPTZ/TEXT |                                 | Execution start time                    |
| `end_time`                   | TIMESTAMPTZ/TEXT |                                 | Execution end time                      |
| `last_update`                | TIMESTAMPTZ/TEXT | NOT NULL, DEFAULT NOW()         | Last status update                      |
| `status`                     | VARCHAR(20)      | NOT NULL, CHECK constraint      | Execution status                        |
| `total_subtasks`             | INTEGER          |                                 | Total number of subtasks                |
| `current_subtask`            | INTEGER          |                                 | Current subtask number                  |
| `overall_percent_complete`   | NUMERIC(5,2)     |                                 | Overall completion %                    |
| `overall_progress_message`   | TEXT             |                                 | Progress message                        |
| `memory_mb`                  | INTEGER          |                                 | Main process memory (MB)                |
| `cpu_percent`                | NUMERIC(5,2)     |                                 | Main process CPU %                      |
| `process_count`              | INTEGER          |                                 | Total processes (incl children)         |
| `total_cpu_percent`          | NUMERIC(8,2)     |                                 | Aggregate CPU % (all processes)         |
| `total_memory_gb`            | NUMERIC(10,3)    |                                 | Aggregate memory GB (all processes)     |
| `total_memory_percent`       | NUMERIC(5,2)     |                                 | % of system memory used                 |
| `error_message`              | TEXT             |                                 | Error message if failed                 |
| `error_detail`               | TEXT             |                                 | Detailed error info                     |
| `version`                    | VARCHAR(50)      |                                 | Software version                        |
| `git_commit`                 | VARCHAR(40)      |                                 | Git commit hash                         |
| `user_name`                  | VARCHAR(100)     |                                 | Username                                |
| `environment`                | JSONB/TEXT       |                                 | Environment metadata                    |

**Valid Status Values:**
- `NOT_STARTED`: Task registered but not started
- `STARTED`: Task initialization begun
- `RUNNING`: Task actively executing
- `COMPLETED`: Task finished successfully
- `FAILED`: Task encountered error
- `SKIPPED`: Task intentionally skipped
- `CANCELLED`: Task cancelled by user

**Indexes:**
- `idx_task_runs_task` on `task_id`
- `idx_task_runs_status` on `status`
- `idx_task_runs_start` on `start_time`
- `idx_task_runs_hostname_pid` on `(hostname, process_id)`

#### 3.2.4 subtask_progress

Tracks progress within individual subtasks, including item-level progress for parallel processing.

| Column              | Type             | Constraints                          | Description                         |
|---------------------|------------------|--------------------------------------|-------------------------------------|
| `progress_id`       | SERIAL/INTEGER   | PRIMARY KEY                          | Auto-incrementing identifier        |
| `run_id`            | UUID/TEXT        | NOT NULL, FOREIGN KEY → task_runs    | Parent task run                     |
| `subtask_number`    | INTEGER          | NOT NULL                             | Subtask sequence number             |
| `subtask_name`      | VARCHAR(500)     |                                      | Subtask description                 |
| `status`            | VARCHAR(20)      | NOT NULL, CHECK constraint           | Subtask status                      |
| `start_time`        | TIMESTAMPTZ/TEXT |                                      | Start time                          |
| `end_time`          | TIMESTAMPTZ/TEXT |                                      | End time                            |
| `last_update`       | TIMESTAMPTZ/TEXT | NOT NULL, DEFAULT NOW()              | Last update                         |
| `percent_complete`  | NUMERIC(5,2)     |                                      | Completion percentage               |
| `progress_message`  | TEXT             |                                      | Progress message                    |
| `items_total`       | BIGINT           |                                      | Total items to process              |
| `items_complete`    | BIGINT           |                                      | Items completed (atomic counter)    |
| `error_message`     | TEXT             |                                      | Error message                       |

**Constraints:**
- `UNIQUE(run_id, subtask_number)`
- `ON DELETE CASCADE` for `run_id`

**Valid Status Values:**
- `NOT_STARTED`, `STARTED`, `RUNNING`, `COMPLETED`, `FAILED`, `SKIPPED`

**Indexes:**
- `idx_subtask_progress_run` on `run_id`
- `idx_subtask_progress_number` on `subtask_number`
- `idx_subtask_progress_status` on `status`

#### 3.2.5 resource_snapshots

Periodic snapshots of system resource usage for process tree monitoring.

| Column                | Type             | Constraints                          | Description                             |
|-----------------------|------------------|--------------------------------------|-----------------------------------------|
| `snapshot_id`         | SERIAL/INTEGER   | PRIMARY KEY                          | Auto-incrementing identifier            |
| `run_id`              | UUID/TEXT        | NOT NULL, FOREIGN KEY → task_runs    | Parent task run                         |
| `timestamp`           | TIMESTAMPTZ/TEXT | NOT NULL, DEFAULT NOW()              | Snapshot time                           |
| `process_count`       | INTEGER          | NOT NULL                             | Total processes (main + children)       |
| `total_cpu_percent`   | NUMERIC(8,2)     | NOT NULL                             | Aggregate CPU % across all processes    |
| `total_memory_gb`     | NUMERIC(10,3)    | NOT NULL                             | Aggregate memory GB                     |
| `total_memory_percent`| NUMERIC(5,2)     | NOT NULL                             | % of system memory                      |
| `system_memory_gb`    | NUMERIC(10,3)    | NOT NULL                             | Total system memory                     |
| `system_cpu_count`    | INTEGER          | NOT NULL                             | Number of CPU cores                     |
| `load_average_1min`   | NUMERIC(6,2)     |                                      | 1-minute load average                   |
| `swap_used_gb`        | NUMERIC(10,3)    |                                      | Swap space used (thrashing indicator)   |

**Constraints:**
- `ON DELETE CASCADE` for `run_id`

**Indexes:**
- `idx_resource_snapshots_run` on `run_id`
- `idx_resource_snapshots_timestamp` on `timestamp`

**Purpose:** Enables historical resource trend analysis, identifies memory leaks, detects thrashing conditions, and provides data for capacity planning.

#### Item-Level Progress Tracking

The `items_total` and `items_complete` columns enable fine-grained progress tracking within subtasks:

**Use Cases:**
- **Parallel Processing**: Track items (e.g., counties, files) processed by multiple workers
- **Batch Operations**: Monitor progress through large datasets
- **Iterative Workflows**: Track completion of individual iterations

**Key Features:**
- **Atomic Increments**: `subtask_increment()` provides thread-safe counter updates
- **Concurrent Workers**: Multiple parallel workers safely increment same counter
- **Real-time Progress**: Dashboard displays "X of Y items completed"
- **Percentage Calculation**: Auto-calculated as `(items_complete / items_total) * 100`

**Example Hierarchy:**
```
Task: "Process Road Lengths"
  Subtask 3: "Process all counties in parallel" (items_total = 3143)
    Item 1: Process county 01001 ✓
    Item 2: Process county 01003 ✓
    ...
    Item 3143: Process county 56045 ⟳ (items_complete incrementing)
```

### 3.3 Views

#### 3.3.1 current_task_status

Provides current status of all tasks with latest run information.

```sql
CREATE VIEW current_task_status AS
SELECT 
    s.stage_name,
    s.stage_order,
    t.task_name,
    t.task_type,
    t.task_order,
    tr.run_id,
    tr.status,
    tr.start_time,
    tr.end_time,
    tr.overall_percent_complete,
    tr.overall_progress_message,
    tr.hostname,
    tr.process_id
FROM tasks t
JOIN stages s ON t.stage_id = s.stage_id
LEFT JOIN LATERAL (
    SELECT * FROM task_runs 
    WHERE task_id = t.task_id 
    ORDER BY start_time DESC 
    LIMIT 1
) tr ON true
ORDER BY s.stage_order, t.task_order;
```

#### 3.3.2 active_tasks

Shows only currently running tasks.

```sql
CREATE VIEW active_tasks AS
SELECT 
    s.stage_name,
    t.task_name,
    tr.run_id,
    tr.status,
    tr.start_time,
    tr.hostname,
    tr.process_id,
    tr.overall_percent_complete
FROM task_runs tr
JOIN tasks t ON tr.task_id = t.task_id
JOIN stages s ON t.stage_id = s.stage_id
WHERE tr.status IN ('STARTED', 'RUNNING')
ORDER BY tr.start_time;
```

---

## 4. API Design

### 4.1 Configuration Functions

#### 4.1.1 `tasker_config()`

Load or set tasker configuration from YAML file, environment variables, or parameters.

**Parameters:**
- `config_file`: Path to `.tasker.yml` (optional, auto-discovered)
- `host`, `port`, `dbname`, `user`, `password`: Database connection parameters
- `schema`: Database schema name (default: "tasker")
- `driver`: Database driver ("postgresql" or "sqlite")
- `start_dir`: Directory to start config file search (default: `getwd()`)
- `reload`: Force reload configuration (default: FALSE)

**Returns:** Invisibly returns configuration list

**Configuration Sources (Priority Order):**
1. Direct function parameters
2. Environment variables (`TASKER_DB_*`)
3. YAML configuration file (`.tasker.yml`)
4. Default values

**Example YAML:**
```yaml
database:
  host: localhost
  port: 5432
  dbname: mydb
  user: ${USER}
  password: ${DB_PASSWORD}
  schema: tasker
  driver: postgresql

pipeline:
  name: "Data Processing Pipeline"
```

#### 4.1.2 `find_config_file()`

Search for `.tasker.yml` in current directory and parent directories.

**Parameters:**
- `start_dir`: Directory to start search (default: `getwd()`)
- `filename`: Config filename to search for (default: ".tasker.yml")

**Returns:** Path to config file or NULL if not found

### 4.2 Database Setup Functions

#### 4.2.1 `setup_tasker_db()`

Initialize tasker database schema.

**Parameters:**
- `conn`: Database connection (optional, uses config if NULL)
- `schema_name`: Schema name (default: "tasker")
- `force`: Drop and recreate schema (default: FALSE) **⚠️ DESTROYS DATA**

**Returns:** TRUE if successful, FALSE if schema exists and force=FALSE

**Actions:**
- Creates schema (PostgreSQL) or verifies connection (SQLite)
- Creates tables: `stages`, `tasks`, `task_runs`, `subtask_progress`
- Creates views: `current_task_status`, `active_tasks`
- Creates triggers for timestamp management
- Sets up indexes

#### 4.2.2 `get_db_connection()`

Get database connection using current configuration.

**Parameters:**
- `config`: Configuration list (optional, uses `getOption("tasker.config")` if NULL)

**Returns:** DBI connection object

**Behavior:**
- For PostgreSQL: Uses `RPostgres::Postgres()`
- For SQLite: Uses `RSQLite::SQLite()`
- Applies schema search path for PostgreSQL

### 4.3 Task Registration Functions

#### 4.3.1 `register_task()`

Register a single task in the tasker system.

**Parameters:**
- `stage`: Stage name (required)
- `name`: Task name (required)
- `type`: Task type, e.g., "R", "python", "sh" (required)
- `description`: Task description (optional)
- `script_path`: Path to script directory (optional)
- `script_filename`: Script filename (optional)
- `log_path`: Log directory path (optional)
- `log_filename`: Log filename (optional)
- `stage_order`: Stage execution order (optional)
- `task_order`: Task order within stage (optional)
- `conn`: Database connection (optional)

**Returns:** `task_id` (invisibly)

**Behavior:**
- Creates stage if it doesn't exist
- Inserts or updates task
- Auto-assigns task_order if not provided

**Example:**
```r
register_task(
  stage = "STATIC",
  name = "Build FCC Database",
  type = "R",
  description = "Process FCC BDC data",
  script_path = "inst/scripts",
  script_filename = "01_fcc_bdc.R"
)
```

#### 4.3.2 `register_tasks()`

Register multiple tasks from a data frame.

**Parameters:**
- `tasks_df`: Data frame with columns: `stage`, `name`, `type`, and optional columns
- `conn`: Database connection (optional)

**Returns:** Vector of `task_id` values (invisibly)

**Example:**
```r
tasks <- data.frame(
  stage = c("PREREQ", "PREREQ", "STATIC"),
  name = c("Install System Deps", "Install R Packages", "Build Database"),
  type = c("sh", "R", "R"),
  description = c("Install PostGIS", "Install R dependencies", "Load FCC data")
)
register_tasks(tasks)
```

### 4.4 Execution Tracking Functions

#### 4.4.1 `task_start()`

Start tracking a task execution.

**Parameters:**
- `stage`: Stage name (required)
- `task`: Task name (required)
- `total_subtasks`: Total number of subtasks (optional)
- `message`: Initial progress message (optional)
- `version`: Software version (optional)
- `git_commit`: Git commit hash (optional)
- `quiet`: Suppress console messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** `run_id` (UUID) for tracking this execution

**Behavior:**
- Validates task exists
- Creates new `task_runs` record with status "STARTED"
- Captures: hostname, PID, parent PID, username, timestamp
- Logs to console unless `quiet=TRUE`

**Example:**
```r
run_id <- task_start(
  stage = "STATIC",
  task = "Build FCC Database",
  total_subtasks = 56,
  message = "Processing all US counties",
  version = "1.2.0",
  git_commit = "a1b2c3d"
)
```

#### 4.4.2 `task_update()`

Update task execution status.

**Parameters:**
- `run_id`: Run ID from `task_start()` (required)
- `status`: New status (optional)
- `current_subtask`: Current subtask number (optional)
- `overall_percent`: Overall completion percentage (optional)
- `message`: Progress message (optional)
- `memory_mb`: Memory usage in MB (optional)
- `cpu_percent`: CPU utilization percentage (optional)
- `quiet`: Suppress console messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** NULL (invisibly)

**Example:**
```r
task_update(
  run_id = run_id,
  status = "RUNNING",
  current_subtask = 15,
  overall_percent = 27,
  message = "Processing county 15 of 56"
)
```

#### 4.4.3 `task_complete()`

Mark task as completed.

**Parameters:**
- `run_id`: Run ID (required)
- `message`: Completion message (optional)
- `quiet`: Suppress console messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** NULL (invisibly)

**Behavior:**
- Sets status to "COMPLETED"
- Sets `end_time`
- Sets `overall_percent_complete` to 100

**Example:**
```r
task_complete(run_id, message = "Successfully processed all 56 counties")
```

#### 4.4.4 `task_fail()`

Mark task as failed.

**Parameters:**
- `run_id`: Run ID (required)
- `error_message`: Error message (required)
- `error_detail`: Detailed error info (optional)
- `quiet`: Suppress console messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** NULL (invisibly)

**Behavior:**
- Sets status to "FAILED"
- Sets `end_time`
- Stores error message and details

**Example:**
```r
tryCatch({
  # ... task code ...
}, error = function(e) {
  task_fail(run_id, 
           error_message = conditionMessage(e),
           error_detail = capture.output(traceback()))
})
```

#### 4.4.5 `subtask_start()`

Start tracking a subtask.

**Parameters:**
- `run_id`: Run ID from `task_start()` (required)
- `subtask_number`: Subtask number (required)
- `subtask_name`: Subtask description (required)
- `items_total`: Total items to process (optional)
- `message`: Initial message (optional)
- `quiet`: Suppress console messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** `progress_id`

**Example:**
```r
subtask_start(
  run_id = run_id,
  subtask_number = 1,
  subtask_name = "Processing North Carolina (37)",
  items_total = 100
)
```

#### 4.4.6 `subtask_update()`

Update subtask progress.

**Parameters:**
- `run_id`: Run ID (required)
- `subtask_number`: Subtask number (required)
- `status`: Status (optional)
- `percent`: Completion percentage (optional)
- `items_complete`: Items completed (optional)
- `message`: Progress message (optional)
- `quiet`: Suppress console messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** NULL (invisibly)

**Example:**
```r
for (i in 1:100) {
  # ... process item ...
  if (i %% 10 == 0) {
    subtask_update(
      run_id = run_id,
      subtask_number = 1,
      status = "RUNNING",
      percent = i,
      items_complete = i,
      message = sprintf("Processed %d/100 counties", i)
    )
  }
}
```

#### 4.4.7 `subtask_complete()`

Mark subtask as completed.

**Parameters:**
- `run_id`: Run ID (required)
- `subtask_number`: Subtask number (required)
- `message`: Completion message (optional)
- `quiet`: Suppress console messages (default: FALSE)
- `conn`: Database connection (optional)

**Returns:** NULL (invisibly)

**Example:**
```r
subtask_complete(run_id, 1, message = "All counties processed")
```

### 4.5 Query Functions

#### 4.5.1 `get_task_status()`

Get current task status.

**Parameters:**
- `stage`: Filter by stage (optional)
- `task`: Filter by task name (optional)
- `status`: Filter by status (optional)
- `limit`: Maximum results (optional)
- `conn`: Database connection (optional)

**Returns:** Data frame with task status information

**Example:**
```r
# All tasks
get_task_status()

# Only running tasks
get_task_status(status = "RUNNING")

# Tasks in specific stage
get_task_status(stage = "STATIC")
```

#### 4.5.2 `get_active_tasks()`

Get currently running tasks.

**Parameters:**
- `conn`: Database connection (optional)

**Returns:** Data frame with active task information

#### 4.5.3 `get_subtask_progress()`

Get subtask progress for a specific run.

**Parameters:**
- `run_id`: Run ID (required)
- `conn`: Database connection (optional)

**Returns:** Data frame with subtask progress details

**Example:**
```r
get_subtask_progress(run_id)
```

#### 4.5.4 `get_task_history()`

Get execution history for a task.

**Parameters:**
- `stage`: Stage name (optional)
- `task`: Task name (optional)
- `limit`: Maximum results (default: 100)
- `conn`: Database connection (optional)

**Returns:** Data frame with historical executions

**Example:**
```r
# Last 100 runs of a specific task
get_task_history(stage = "STATIC", task = "Build FCC Database", limit = 100)
```

#### 4.5.5 `get_stages()`

Get all registered stages.

**Parameters:**
- `conn`: Database connection (optional)

**Returns:** Data frame with stage information

#### 4.5.6 `get_registered_tasks()`

Get all registered tasks.

**Parameters:**
- `stage`: Filter by stage (optional)
- `conn`: Database connection (optional)

**Returns:** Data frame with task information

### 4.6 Item Progress Functions

#### 4.6.1 `subtask_increment()`

Atomically increment the item counter for a subtask (thread-safe for parallel workers).

**Parameters:**
- `run_id`: Run ID from `task_start()` (required)
- `subtask_number`: Subtask number (required)
- `increment`: Number of items to add (default: 1)
- `quiet`: Suppress console messages (default: TRUE)
- `conn`: Database connection (optional)

**Returns:** TRUE on success

**Thread Safety:** Uses database-level atomic operations (`UPDATE ... SET items_complete = COALESCE(items_complete, 0) + increment`) to safely handle concurrent updates from multiple parallel workers.

**Example:**
```r
# In parallel worker function:
process_county <- function(county_fips) {
  # ... process county ...
  
  # Atomically increment item counter
  subtask_increment(run_id, subtask_number = 3, increment = 1, quiet = TRUE)
  
  return("success")
}

# Main process:
subtask_start(run_id, 3, "Process all counties", items_total = 3143)
results <- parLapply(cl, county_list, process_county)
subtask_complete(run_id, 3)
```

**Best Practices:**
- Call `subtask_increment()` at the END of each work item (just before returning)
- Use `quiet = TRUE` in parallel workers to avoid console spam
- Set `items_total` in `subtask_start()` for accurate progress percentage
- Dashboard will show "X / Y items (Z%)" automatically

### 4.7 Resource Monitoring Functions

#### 4.7.1 `get_process_tree_resources()`

Get aggregate resource usage for main process and all child processes.

**Parameters:**
- `pid`: Process ID (default: current R process)

**Returns:** Named list with:
- `process_count`: Total number of processes
- `total_cpu_percent`: Aggregate CPU % across all processes
- `total_memory_gb`: Aggregate memory in GB
- `total_memory_percent`: Percentage of system memory
- `system_memory_gb`: Total system memory
- `system_cpu_count`: Number of CPU cores
- `process_list`: Data frame of individual processes

**Example:**
```r
resources <- get_process_tree_resources()
cat(sprintf("Using %d processes, %.1f%% CPU, %.2f GB RAM (%.1f%% of system)\n",
            resources$process_count,
            resources$total_cpu_percent,
            resources$total_memory_gb,
            resources$total_memory_percent))
```

#### 4.7.2 `snapshot_resources()`

Record a resource snapshot to the database.

**Parameters:**
- `run_id`: Run ID from `task_start()` (required)
- `quiet`: Suppress console messages (default: TRUE)
- `conn`: Database connection (optional)

**Returns:** TRUE on success

**Behavior:** Captures current process tree resources and stores in `resource_snapshots` table. Also updates aggregate columns in `task_runs` table.

#### 4.7.3 `start_resource_watchdog()`

Start background watchdog process for resource monitoring.

**Parameters:**
- `run_id`: Run ID from `task_start()` (required)
- `interval_seconds`: Snapshot interval (default: 30)
- `memory_threshold_percent`: Maximum memory % before warning (default: 85)
- `memory_kill_percent`: Maximum memory % before terminating task (default: 95)
- `swap_threshold_gb`: Swap usage threshold indicating thrashing (default: 1.0)
- `orphan_check`: Check for orphaned workers (default: TRUE)
- `conn`: Database connection (optional)

**Returns:** Watchdog process ID

**Behavior:**
- Forks a background process that monitors system resources every `interval_seconds`
- Records snapshots to `resource_snapshots` table
- Issues warnings when memory exceeds `memory_threshold_percent`
- Terminates task if memory exceeds `memory_kill_percent` (prevents system thrashing)
- Detects swap usage (thrashing indicator)
- Identifies and terminates orphaned parallel workers
- Automatically stops when task completes

**Example:**
```r
run_id <- task_start("PROCESS", "Process Counties", total_subtasks = 3)

# Start watchdog with custom thresholds
watchdog_pid <- start_resource_watchdog(
  run_id,
  interval_seconds = 15,
  memory_threshold_percent = 80,
  memory_kill_percent = 90,
  orphan_check = TRUE
)

# ... do work ...

# Watchdog stops automatically at task completion
task_complete(run_id, "Processing complete")
```

#### 4.7.4 `stop_resource_watchdog()`

Manually stop the resource watchdog process.

**Parameters:**
- `watchdog_pid`: Watchdog process ID from `start_resource_watchdog()`

**Returns:** TRUE on success

**Note:** Normally not needed as watchdog stops automatically at task completion.

#### 4.7.5 `cleanup_orphaned_workers()`

Identify and terminate orphaned parallel worker processes.

**Parameters:**
- `parent_pid`: Parent process ID (default: current R process)
- `kill_orphans`: Actually terminate orphans (default: FALSE)

**Returns:** Data frame of orphaned processes

**Behavior:**
- Scans for R processes that appear to be parallel workers
- Checks if parent process still exists
- Identifies workers whose parent has terminated (orphans)
- Optionally terminates orphaned processes

**Use Cases:**
- Manual cleanup after interrupted parallel jobs
- Scheduled cleanup in long-running pipeline servers
- Debugging resource leaks

**Example:**
```r
# Check for orphans without killing
orphans <- cleanup_orphaned_workers(kill_orphans = FALSE)
if (nrow(orphans) > 0) {
  print(orphans)
  
  # Kill them if confirmed
  cleanup_orphaned_workers(kill_orphans = TRUE)
}
```

#### 4.7.6 `get_resource_history()`

Retrieve historical resource snapshots for a task run.

**Parameters:**
- `run_id`: Run ID from `task_start()` (required)
- `conn`: Database connection (optional)

**Returns:** Data frame with columns: `timestamp`, `process_count`, `total_cpu_percent`, `total_memory_gb`, `total_memory_percent`, `load_average_1min`, `swap_used_gb`

**Example:**
```r
# Get resource history
history <- get_resource_history(run_id)

# Plot memory usage over time
library(ggplot2)
ggplot(history, aes(x = timestamp, y = total_memory_gb)) +
  geom_line() +
  labs(title = "Memory Usage Over Time",
       x = "Time", y = "Memory (GB)")
```

### 4.8 Utility Functions

#### 4.7.1 `get_parent_pid()`

Get parent process ID of current R session.

**Returns:** Integer PID or NULL

#### 4.7.2 `purge_tasker_data()`

Remove old task execution records.

**Parameters:**
- `older_than_days`: Delete records older than this many days (required)
- `stage`: Filter by stage (optional)
- `task`: Filter by task (optional)
- `conn`: Database connection (optional)

**Returns:** Number of records deleted

**Example:**
```r
# Delete records older than 90 days
purge_tasker_data(older_than_days = 90)
```

---

## 5. User Interface

### 5.1 Shiny Dashboard

The tasker package includes a comprehensive Shiny dashboard for real-time monitoring.

#### 5.1.1 Launch Command

```r
library(tasker)
tasker_config()  # Load configuration
run_monitor()    # Launch dashboard
```

#### 5.1.2 Dashboard Features

**Pipeline Status Tab (Primary Interface):**
- **Hierarchical stage panels**: Collapsible stage sections with progress summaries
- **Task rows with dual progress bars**:
  - Primary progress bar: Overall task completion percentage
  - Secondary item progress bar: Displays "X / Y items (Z%)" when items_total > 0
  - Both progress bars update in real-time during task execution
- **Expandable task details**: Click any task row to expand and view:
  - Complete task metadata (run_id, hostname, PID, timing, status)
  - Subtask progress table with item counts
  - **Live log viewer**: Real-time log file display with auto-scroll
  - Log controls: Toggle auto-refresh, adjust number of lines, manual refresh
  - Syntax highlighting: Color-coded ERROR (red), WARNING (yellow), INFO (cyan)
- **Status badges**: Color-coded task and stage status indicators
- **Real-time updates**: Configurable auto-refresh interval (default: 5 seconds)
- **Stage statistics**: Task completion counts (e.g., "6/6", "2/3")
- **Filtering**: Filter by stage and status

**Log File Integration:**
- Uses correct log file path from database: `file.path(log_path, log_filename)`
- Tail mode: Shows last N lines with automatic scrolling as new entries appear
- Auto-refresh: Updates every 3 seconds when enabled for active tasks
- Maximizable view: Expand log panel for detailed inspection
- Line number configuration: Adjustable from 10 to 5000 lines
- File status: Shows file path, line count, and last update time

#### 5.1.3 UI Components

**Status Color Coding:**
- `NOT_STARTED`: Gray (#e0e0e0)
- `STARTED`: Yellow (#fff3cd)
- `RUNNING`: Animated yellow (#ffd54f, pulsing)
- `COMPLETED`: Green (#81c784)
- `FAILED`: Red (#e57373)
- `SKIPPED`: Light gray (#e2e3e5)
- `CANCELLED`: Orange (#ffb74d)

**Progress Bars:**
- **Dual progress display for tasks**:
  - Primary bar: Overall task completion percentage with smooth transitions
  - Secondary item bar: Shows "X / Y items (Z%)" when processing items
  - Both bars animate with stripes for running tasks
- **Stage-level progress**: Aggregate completion across all tasks
- Animated stripes for active tasks (running status)
- Smooth transitions on updates
- Percentage labels centered in bars
- Color-coded by status (matching status badges)
- **Real-time updates**: Item counters increment as parallel workers complete items
- **Nested display**: Item progress bar positioned directly below task progress bar

**Resource Monitoring Display:**
- Current resources: `N processes | X% CPU | Y.Y GB RAM (Z%)`
- Resource history sparklines for memory/CPU trends over time
- Color-coded warnings (yellow at threshold, red near kill limit)
- Swap usage indicator (thrashing detection)
- Orphaned worker alerts with cleanup buttons
- Peak/average/current resource statistics

**Resource Monitoring Display:**
- Current resources: `N processes | X% CPU | Y.Y GB RAM (Z%)`
- Resource history sparklines for memory/CPU trends
- Color-coded warnings (yellow at threshold, red near kill limit)
- Swap usage indicator (thrashing detection)
- Orphaned worker alerts

### 5.2 Command-Line Interface

All functions provide console output by default:

```
[2025-12-26 14:30:15] Task 1 START | STATIC / Build FCC Database | run_id: 123e4567-e89b-12d3-a456-426614174000
[2025-12-26 14:30:20] Task 1 SUBTASK 1 START | Processing North Carolina (37) | 0/100 counties
[2025-12-26 14:31:00] Task 1 SUBTASK 1 PROGRESS | RUNNING | 50/100 counties | 50.0% complete
[2025-12-26 14:31:40] Task 1 SUBTASK 1 COMPLETE | All counties processed | 100/100 counties
[2025-12-26 14:35:00] Task 1 COMPLETE | Successfully processed all 56 counties | 100.0% complete
```

Suppress with `quiet=TRUE` parameter on any function.

---

## 6. Configuration Management

### 6.1 Configuration Hierarchy

Priority (highest to lowest):

1. **Direct function parameters**
   ```r
   tasker_config(host = "localhost", dbname = "mydb")
   ```

2. **Environment variables**
   ```bash
   export TASKER_DB_HOST=localhost
   export TASKER_DB_PORT=5432
   export TASKER_DB_NAME=mydb
   export TASKER_DB_USER=myuser
   export TASKER_DB_PASSWORD=mypassword
   export TASKER_DB_SCHEMA=tasker
   export TASKER_DB_DRIVER=postgresql
   ```

3. **YAML configuration file** (`.tasker.yml`)
   ```yaml
   database:
     host: localhost
     port: 5432
     dbname: mydb
     user: ${USER}
     password: ${DB_PASSWORD}
     schema: tasker
     driver: postgresql
   
   pipeline:
     name: "My Data Pipeline"
   
   resource_watchdog:
     enabled: true
     interval_seconds: 30
     memory_threshold_percent: 85
     memory_kill_percent: 95
     swap_threshold_gb: 1.0
     orphan_check: true
     orphan_check_interval: 300
   ```

4. **Default values**
   - host: "localhost"
   - port: 5432
   - user: `$USER`
   - schema: "tasker"
   - driver: "postgresql"

### 6.2 Configuration File Discovery

`tasker_config()` searches for `.tasker.yml` starting from current directory and walking up to root.

**Search Path Example:**
```
/home/user/project/subdir/script.R  ← Start here
/home/user/project/subdir/.tasker.yml
/home/user/project/.tasker.yml      ← Found!
/home/user/.tasker.yml
/home/.tasker.yml
/.tasker.yml
```

### 6.3 Environment Variable Expansion

Configuration supports environment variable expansion:

```yaml
database:
  user: ${USER}              # Expands to current user
  password: ${DB_PASSWORD}   # Expands from environment
  dbname: ${PROJECT_DB:-mydb}  # With default fallback
```

### 6.4 Multi-Environment Support

Use different config files for different environments:

```bash
# Development
export TASKER_CONFIG=.tasker.dev.yml

# Production
export TASKER_CONFIG=.tasker.prod.yml

# In R
tasker_config(config_file = Sys.getenv("TASKER_CONFIG", ".tasker.yml"))
```

---

## 7. Implementation Patterns

### 7.1 Basic Task Tracking

```r
library(tasker)

# Configure
tasker_config()

# Register task
register_task(stage = "PROCESS", name = "Load Data", type = "R")

# Execute with tracking
run_id <- task_start("PROCESS", "Load Data")

tryCatch({
  # Your code here
  data <- load_data()
  
  task_complete(run_id, "Data loaded successfully")
  
}, error = function(e) {
  task_fail(run_id, conditionMessage(e))
  stop(e)
})
```

### 7.2 Multi-Subtask Tracking

```r
run_id <- task_start("PROCESS", "Process Counties", total_subtasks = 3)

# Subtask 1
subtask_start(run_id, 1, "Validate data", items_total = 100)
for (i in 1:100) {
  # ... work ...
  if (i %% 20 == 0) {
    subtask_update(run_id, 1, "RUNNING", 
                   percent = i, items_complete = i,
                   message = sprintf("Validated %d/100", i))
  }
}
subtask_complete(run_id, 1, "Validation complete")

# Subtask 2
subtask_start(run_id, 2, "Transform data", items_total = 100)
# ... similar pattern ...
subtask_complete(run_id, 2, "Transform complete")

# Subtask 3
subtask_start(run_id, 3, "Load to database", items_total = 100)
# ... similar pattern ...
subtask_complete(run_id, 3, "Load complete")

task_complete(run_id, "All processing complete")
```

### 7.3 Parallel Processing with Item Tracking

```r
library(parallel)

run_id <- task_start("PROCESS", "Process Counties", total_subtasks = 1)

# Get list of counties to process
county_list <- get_county_list()  # Returns 3143 counties

# Start subtask with item count
subtask_start(run_id, 1, "Process all counties in parallel", 
              items_total = length(county_list))

# Create cluster
cl <- makeCluster(16)
clusterEvalQ(cl, library(tasker))
clusterExport(cl, c("run_id"))

# Create worker function that increments item counter
process_county <- function(county_fips) {
  tryCatch({
    # ... do the actual work ...
    result <- compute_county_data(county_fips)
    
    # Atomically increment item counter (thread-safe)
    subtask_increment(run_id, subtask_number = 1, increment = 1, quiet = TRUE)
    
    return("success")
    
  }, error = function(e) {
    # Don't increment on error - allows retry
    return(as.character(e))
  })
}

# Parallel processing - each worker increments counter
results <- parLapply(cl, county_list, process_county)

stopCluster(cl)

# Mark subtask complete
subtask_complete(run_id, 1, message = "All counties processed")
task_complete(run_id, "Processing complete")
```

**Dashboard Display:**
```
Subtask 1: Process all counties in parallel
  Status: RUNNING
  Progress: 2847 / 3143 items (90.6%)
  [████████████████████░░] 90.6%
```

### 7.4 Resource Monitoring with Watchdog

```r
library(parallel)

run_id <- task_start("PROCESS", "Process Counties", total_subtasks = 1)

# Start resource watchdog
# - Monitors every 30 seconds
# - Warns at 85% memory usage
# - Kills task at 95% memory (prevents thrashing)
# - Detects orphaned workers
watchdog_pid <- start_resource_watchdog(
  run_id,
  interval_seconds = 30,
  memory_threshold_percent = 85,
  memory_kill_percent = 95,
  swap_threshold_gb = 1.0,
  orphan_check = TRUE
)

subtask_start(run_id, 1, "Process all counties in parallel",
              items_total = length(county_list))

# Take initial resource snapshot
snapshot_resources(run_id)

# Create cluster
cl <- makeCluster(16)
on.exit({
  stopCluster(cl)
  # Watchdog will detect orphaned workers if cluster cleanup fails
})

clusterEvalQ(cl, library(tasker))
clusterExport(cl, c("run_id"))

# Parallel processing
results <- parLapply(cl, county_list, function(county_fips) {
  tryCatch({
    result <- process_county(county_fips)
    subtask_increment(run_id, 1, quiet = TRUE)
    "success"
  }, error = function(e) {
    as.character(e)
  })
})

stopCluster(cl)

# Final resource snapshot
snapshot_resources(run_id)

subtask_complete(run_id, 1)
task_complete(run_id, "Processing complete")

# Watchdog stops automatically

# View resource history
history <- get_resource_history(run_id)
print(history)

# Summary stats
cat(sprintf("
  Peak Resources:
    Processes: %d
    CPU: %.1f%%
    Memory: %.2f GB (%.1f%% of system)
    Max Swap: %.2f GB\n",
  max(history$process_count),
  max(history$total_cpu_percent),
  max(history$total_memory_gb),
  max(history$total_memory_percent),
  max(history$swap_used_gb, na.rm = TRUE)
))
```

**Dashboard Display:**
```
Task: Process Counties
  Status: RUNNING
  Resources: 17 processes | 1247% CPU | 89.3 GB RAM (72.1%)
  
Subtask 1: Process all counties
  Progress: 2847 / 3143 items (90.6%)
  
Resource History: [Mini sparkline graph showing memory trend]
  Peak: 89.3 GB | Avg: 76.2 GB | Current: 87.1 GB
```

**Watchdog Actions:**
```
[2025-12-26 14:23:45] Resource snapshot: 17 proc, 1247% CPU, 89.3 GB (72.1%)
[2025-12-26 14:24:15] Resource snapshot: 17 proc, 1189% CPU, 91.7 GB (74.0%)
[2025-12-26 14:24:45] WARNING: Memory usage 87.2% exceeds threshold (85%)
[2025-12-26 14:25:15] Resource snapshot: 17 proc, 1156% CPU, 88.4 GB (71.3%)
[2025-12-26 14:25:45] Orphan check: Found 0 orphaned workers
```

### 7.5 Pipeline Integration

```r
# Define pipeline
pipeline <- list(
  list(stage = "EXTRACT", tasks = c("Download FCC Data", "Download Census Data")),
  list(stage = "TRANSFORM", tasks = c("Clean Data", "Join Datasets")),
  list(stage = "LOAD", tasks = c("Load to Database", "Create Indexes"))
)

# Register all tasks
for (stage_def in pipeline) {
  for (task_name in stage_def$tasks) {
    register_task(stage = stage_def$stage, name = task_name, type = "R")
  }
}

# Execute pipeline
for (stage_def in pipeline) {
  for (task_name in stage_def$tasks) {
    run_id <- task_start(stage_def$stage, task_name)
    
    tryCatch({
      execute_task(stage_def$stage, task_name)
      task_complete(run_id)
    }, error = function(e) {
      task_fail(run_id, conditionMessage(e))
      stop("Pipeline failed at: ", task_name)
    })
  }
}
```

### 7.6 Error Handling

```r
run_id <- task_start("PROCESS", "Risky Operation", total_subtasks = 3)

# Periodic resource updates
while (processing) {
  # Get resource usage
  mem_mb <- as.integer(pryr::mem_used() / 1024^2)
  cpu_pct <- get_cpu_usage()  # Custom function
  
  task_update(run_id,
             status = "RUNNING",
             memory_mb = mem_mb,
             cpu_percent = cpu_pct,
             message = sprintf("Memory: %d MB, CPU: %.1f%%", mem_mb, cpu_pct))
  
  Sys.sleep(60)  # Update every minute
}
```

### 7.7 Manual Resource Updates

For tasks that need custom resource reporting without the watchdog:

```r
run_id <- task_start("PROCESS", "Long Task", total_subtasks = 1)

# Periodic manual resource snapshots
for(i in 1:100) {
  # Take resource snapshot (includes process tree)
  snapshot_resources(run_id, quiet = TRUE)
  
  # ... do work ...
  Sys.sleep(10)
}

task_complete(run_id, "Complete")

# Alternative: Update individual metrics
resources <- get_process_tree_resources()
task_update(run_id, "RUNNING",
           current_subtask = 1,
           memory_mb = as.integer(resources$total_memory_gb * 1024),
           cpu_percent = resources$total_cpu_percent,
           message = sprintf("%d proc, %.1f%% CPU, %.2f GB RAM",
                           resources$process_count,
                           resources$total_cpu_percent,
                           resources$total_memory_gb))
```

---

## 8. Database Backends

### 8.1 PostgreSQL Backend

**Advantages:**
- Full SQL feature support
- Concurrent access
- JSONB for metadata
- Triggers and functions
- UUIDs for run_id
- Advanced indexing

**Setup:**
```yaml
database:
  driver: postgresql
  host: localhost
  port: 5432
  dbname: tasker_db
  user: tasker_user
  password: secure_password
  schema: tasker
```

**Requirements:**
- PostgreSQL 12+
- `RPostgres` package
- `CREATE SCHEMA` permission
- `gen_random_uuid()` support

### 8.2 SQLite Backend

**Advantages:**
- No server required
- Single file database
- Simple setup
- Portable
- Good for development/testing

**Limitations:**
- Limited concurrent writes
- No JSONB (uses TEXT)
- No UUID type (uses TEXT)
- Manual timestamp management

**Setup:**
```yaml
database:
  driver: sqlite
  path: /path/to/tasker.db
```

**Requirements:**
- `RSQLite` package
- Write access to database file directory

### 8.3 Backend Compatibility

The package abstracts backend differences:

| Feature           | PostgreSQL       | SQLite                   |
|-------------------|------------------|--------------------------|  
| Schema support    | ✅ Yes           | ❌ No (uses default)     |
| UUID type         | ✅ Native        | ⚠️ TEXT                  |
| JSONB             | ✅ Native        | ⚠️ TEXT (JSON string)    |
| Triggers          | ✅ Full support  | ⚠️ Limited               |
| Concurrent writes | ✅ High          | ⚠️ Low                   |
| NOW() function    | ✅ Built-in      | ⚠️ datetime('now')       |

---

## 9. Security Considerations

### 9.1 Database Credentials

**Best Practices:**

1. **Never commit credentials to version control**
   ```bash
   # Add to .gitignore
   .tasker.yml
   .env
   ```

2. **Use environment variables**
   ```yaml
   database:
     user: ${DB_USER}
     password: ${DB_PASSWORD}
   ```

3. **File permissions**
   ```bash
   chmod 600 .tasker.yml
   ```

4. **Use read-only connections when possible**
   ```r
   # Query functions should use read-only connections
   conn <- dbConnect(Postgres(), ..., options = "-c default_transaction_read_only=on")
   ```

### 9.2 SQL Injection Prevention

All user inputs are parameterized using `glue::glue_sql()`:

```r
# ✅ SAFE - Parameterized
DBI::dbGetQuery(
  conn,
  glue::glue_sql("SELECT * FROM tasks WHERE task_name = {task}", .con = conn)
)

# ❌ UNSAFE - String interpolation
DBI::dbGetQuery(
  conn,
  paste0("SELECT * FROM tasks WHERE task_name = '", task, "'")
)
```

### 9.3 Access Control

**Database-Level:**
```sql
-- Create read-only role for monitoring
CREATE ROLE tasker_readonly;
GRANT USAGE ON SCHEMA tasker TO tasker_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA tasker TO tasker_readonly;

-- Create read-write role for execution
CREATE ROLE tasker_readwrite;
GRANT USAGE ON SCHEMA tasker TO tasker_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tasker TO tasker_readwrite;
```

---

## 10. Performance Considerations

### 10.1 Database Indexes

All critical query paths are indexed:

- Lookups by stage/task name
- Filtering by status
- Time-based queries
- Join columns

### 10.2 Connection Management

**Connection Pooling:**
```r
# Create connection pool for high-frequency updates
pool <- pool::dbPool(
  drv = RPostgres::Postgres(),
  host = config$database$host,
  dbname = config$database$dbname,
  ...
)

# Use pool for queries
conn <- pool::poolCheckout(pool)
# ... operations ...
pool::poolReturn(conn)
```

### 10.3 Batch Updates

For high-frequency updates, consider batching:

```r
# Instead of updating every iteration
for (i in 1:10000) {
  process_item(i)
  # Skip individual updates
}

# Update periodically
if (i %% 100 == 0) {
  subtask_update(run_id, subtask_num, 
                percent = (i/10000)*100,
                items_complete = i)
}
```

### 10.4 Data Retention

Implement purging strategy for old data:

```r
# Automated cleanup in pipeline
purge_tasker_data(older_than_days = 90)

# Or scheduled cleanup
cron_schedule("0 2 * * *", {
  purge_tasker_data(older_than_days = 90)
})
```

---

## 11. Error Handling

### 11.1 Graceful Degradation

Functions continue when database unavailable:

```r
tryCatch({
  task_update(run_id, status = "RUNNING")
}, error = function(e) {
  warning("Failed to update task status: ", conditionMessage(e))
  # Continue execution
})
```

### 11.2 Transaction Management

Updates use transactions when needed:

```r
DBI::dbWithTransaction(conn, {
  # Multiple related updates
  task_update(run_id, status = "RUNNING")
  subtask_start(run_id, 1, "Processing")
})
```

### 11.3 Error Context Capture

Capture full context on failures:

```r
task_fail(
  run_id,
  error_message = conditionMessage(e),
  error_detail = jsonlite::toJSON(list(
    call = deparse(sys.call()),
    traceback = capture.output(traceback()),
    session_info = capture.output(sessionInfo()),
    timestamp = Sys.time()
  ))
)
```

---

## 12. Testing Strategy

### 12.1 Unit Tests

Test individual functions in isolation:

```r
test_that("task_start creates run record", {
  conn <- setup_test_db()
  register_task("TEST", "Test Task", "R", conn = conn)
  
  run_id <- task_start("TEST", "Test Task", conn = conn)
  
  expect_true(!is.na(run_id))
  expect_match(run_id, "^[0-9a-f-]{36}$")  # UUID format
  
  teardown_test_db(conn)
})
```

### 12.2 Integration Tests

Test end-to-end workflows:

```r
test_that("complete task workflow", {
  conn <- setup_test_db()
  
  # Register, start, update, complete
  register_task("TEST", "Full Test", "R", conn = conn)
  run_id <- task_start("TEST", "Full Test", total_subtasks = 2, conn = conn)
  
  subtask_start(run_id, 1, "Sub 1", conn = conn)
  subtask_complete(run_id, 1, conn = conn)
  
  subtask_start(run_id, 2, "Sub 2", conn = conn)
  subtask_complete(run_id, 2, conn = conn)
  
  task_complete(run_id, conn = conn)
  
  # Verify final state
  status <- get_task_status(stage = "TEST", task = "Full Test", conn = conn)
  expect_equal(status$status, "COMPLETED")
  expect_equal(status$overall_percent_complete, 100)
  
  teardown_test_db(conn)
})
```

### 12.3 Backend Compatibility Tests

Test both PostgreSQL and SQLite:

```r
test_backends <- function(test_fn) {
  # PostgreSQL
  test_that(paste("PostgreSQL:", as.character(substitute(test_fn))), {
    conn <- setup_pg_test()
    test_fn(conn)
    teardown_pg_test(conn)
  })
  
  # SQLite
  test_that(paste("SQLite:", as.character(substitute(test_fn))), {
    conn <- setup_sqlite_test()
    test_fn(conn)
    teardown_sqlite_test(conn)
  })
}
```

---

## 13. Deployment

### 13.1 Package Installation

```r
# From GitHub
devtools::install_github("Broadband-Catalysts/tasker")

# From source
install.packages("tasker_0.1.0.tar.gz", repos = NULL, type = "source")
```

### 13.2 Database Setup

```r
library(tasker)

# Configure
tasker_config(config_file = "config/production.tasker.yml")

# Initialize database
setup_tasker_db()

# Register tasks from definition file
tasks <- read.csv("config/tasks.csv")
register_tasks(tasks)
```

### 13.3 Production Monitoring

```r
# Launch monitoring dashboard
run_monitor(host = "0.0.0.0", port = 8080)

# Or use Docker
docker run -p 8080:8080 \
  -e TASKER_DB_HOST=db.example.com \
  -e TASKER_DB_NAME=tasker \
  -e TASKER_DB_USER=tasker_user \
  -e TASKER_DB_PASSWORD=secret \
  tasker/monitor:latest
```

---

## 14. Future Enhancements

### 14.1 Planned Features

1. **Task Dependencies**
   - DAG-based execution
   - Automatic dependency resolution
   - Conditional execution

2. **Advanced Scheduling**
   - Cron-like scheduling
   - Retry policies
   - Timeout management

3. **Notifications**
   - Email alerts on failure
   - Slack/Teams integration
   - Custom webhooks

4. **Enhanced Metrics**
   - Execution time trends
   - Resource usage analytics
   - Bottleneck identification

5. **Multi-Database Support**
   - MySQL/MariaDB backend
   - Cloud database services (RDS, Cloud SQL)

6. **API Server**
   - REST API for external integration
   - Authentication/authorization
   - OpenAPI/Swagger documentation

### 14.2 Extensibility Points

- Custom status values
- Pluggable notification backends
- Custom metadata fields
- External monitoring integration

---

## 15. Appendices

### 15.1 Status Value Reference

| Status        | Meaning                          | Used In         | Terminal?  |
|---------------|----------------------------------|-----------------|------------|
| `NOT_STARTED` | Task registered but not begun    | Tasks           | No         |
| `STARTED`     | Task initialization begun        | Tasks           | No         |
| `RUNNING`     | Task actively executing          | Tasks, Subtasks | No         |
| `COMPLETED`   | Task finished successfully       | Tasks, Subtasks | Yes        |
| `FAILED`      | Task encountered error           | Tasks, Subtasks | Yes        |
| `SKIPPED`     | Task intentionally bypassed      | Tasks, Subtasks | Yes        |
| `CANCELLED`   | Task cancelled by user           | Tasks           | Yes        |

### 15.2 Database Size Estimates

Approximate storage requirements:

| Component          | Per Record | 1000 Tasks   | 10000 Tasks   |
|--------------------|------------|--------------|---------------|
| Stages             | 500 bytes  | 5 KB         | 50 KB         |
| Tasks              | 1 KB       | 1 MB         | 10 MB         |
| Task Runs          | 2 KB       | 2 MB         | 20 MB         |
| Subtask Progress   | 500 bytes  | 500 KB       | 5 MB          |
| **Total**          | -          | **~3.5 MB**  | **~35 MB**    |

*Note: Actual size depends on metadata, error messages, and text field content.*

### 15.3 Glossary

- **Stage**: Logical grouping of related tasks (e.g., "PREREQ", "STATIC", "DAILY")
- **Task**: Individual unit of work within a stage (e.g., "Build Database")
- **Subtask**: Subdivision of a task for detailed progress tracking (e.g., "Process all counties")
- **Item**: Individual work unit within a subtask (e.g., single county, file, or record)
- **Item Counter**: Atomic counter tracking items completed (`items_complete` / `items_total`)
- **Run**: Single execution instance of a task
- **Run ID**: Unique identifier (UUID) for a task run
- **Progress ID**: Unique identifier for a subtask progress record
- **Atomic Increment**: Thread-safe database operation for updating item counters from parallel workers
- **Process Tree**: Main process and all child processes (e.g., parallel workers)
- **Resource Snapshot**: Point-in-time capture of process tree resource usage
- **Watchdog**: Background process monitoring system resources and cleaning up orphaned workers
- **Orphaned Worker**: Parallel worker process whose parent has terminated
- **Thrashing**: Excessive disk swapping when system runs out of physical memory

### 15.4 Related Documentation

- [README.md](../README.md) - User guide and quick start
- [SQL Schema](../inst/sql/postgresql/create_schema.sql) - PostgreSQL schema definition
- [Example Pipeline](../inst/examples/example_pipeline.R) - Complete example
- [Shiny Dashboard](../inst/shiny/app.R) - Monitoring UI

---

## Document History

| Version | Date       | Author         | Changes                       |
|---------|------------|----------------|-------------------------------|
| 1.0     | 2025-12-26 | Gregory Warnes | Initial design specification  |

---

**End of Design Specification**
