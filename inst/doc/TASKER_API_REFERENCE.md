# tasker Package - Terminology and API Reference

**Version:** 1.0  
**Last Updated:** 2025-12-20  
**Status:** Final Design

---

## Terminology

### Three Levels of Tracking

```
┌─────────────────────────────────────────┐
│ STAGE (Pipeline Phase)                   │  ← Highest level grouping
│  e.g., "PREREQ", "DAILY", "ANNUAL_DEC"  │
├─────────────────────────────────────────┤
│  ├─ TASK (Work Unit)                    │  ← Individual executable
│  │   e.g., "Install R", "Process BDC"   │
│  │                                       │
│  │  ├─ SUBTASK (Items within task)      │  ← Progress within task
│  │  │   e.g., "State 12 of 56"          │
│  │  └─ SUBTASK                           │
│  │                                       │
│  ├─ TASK                                 │
│  └─ TASK                                 │
└─────────────────────────────────────────┘
```

### Definitions

| Term | Definition | Examples |
|------|------------|----------|
| **Stage** | Pipeline phase or execution grouping | PREREQ, DAILY, MONTHLY, ANNUAL_DEC |
| **Task** | Individual work unit or executable | "Install R", "DAILY_01_BDC_Locations.R" |
| **Subtask** | Progress items within a single task | States, files, rows, records |

### Mapping to Code

- **Stage** → `stage` parameter, `task_stage` column
- **Task** → `task_name` parameter/column  
- **Subtask** → `subtask_*` parameters/columns

---

## Core API

### Configuration Functions

#### `tasker_config()` - Load or set configuration

```r
#' Load or set tasker configuration
#'
#' @param config_file Path to .tasker.yml config file (optional)
#'   If NULL, searches up directory tree from working directory
#' @param host Database host (overrides config file)
#' @param port Database port (overrides config file)
#' @param dbname Database name (overrides config file)
#' @param user Database user (overrides config file)
#' @param password Database password (overrides config file)
#' @param schema Database schema (overrides config file, default: "tasker")
#' @param driver Database driver (overrides config file, default: "postgresql")
#' @param reload Force reload even if already loaded (default: FALSE)
#' @return Invisibly returns configuration list
#' @export
#' 
#' @details
#' Configuration precedence (highest to lowest):
#' 1. Explicit parameters passed to function
#' 2. Environment variables (TASKER_DB_HOST, etc.)
#' 3. Configuration file (.tasker.yml)
#' 4. Built-in defaults
#' 
#' This function is automatically called by all tasker functions.
#' Configuration is cached in options for performance.
#' 
#' @examples
#' # Auto-load from .tasker.yml in project root
#' tasker_config()
#' 
#' # Load specific config file
#' tasker_config(config_file = "/path/to/.tasker.yml")
#' 
#' # Override specific settings
#' tasker_config(host = "localhost", port = 5433)
#' 
#' # Force reload
#' tasker_config(reload = TRUE)
tasker_config(
  config_file = NULL,
  host = NULL,
  port = NULL,
  dbname = NULL,
  user = NULL,
  password = NULL,
  schema = NULL,
  driver = NULL,
  reload = FALSE
)
```

#### `get_tasker_config()` - Get current configuration

```r
#' Get current tasker configuration
#'
#' @return List with configuration settings
#' @export
get_tasker_config()
```

#### `find_config_file()` - Locate .tasker.yml

```r
#' Find .tasker.yml configuration file
#'
#' @param start_dir Starting directory (default: current working directory)
#' @param filename Configuration filename (default: ".tasker.yml")
#' @param max_depth Maximum directory levels to search up (default: 10)
#' @return Path to config file, or NULL if not found
#' @export
#' 
#' @details
#' Searches up the directory tree from start_dir looking for the
#' configuration file. Stops at filesystem root or after max_depth levels.
#' 
#' @examples
#' # Find from current directory
#' find_config_file()
#' 
#' # Find from specific directory
#' find_config_file("/path/to/project/subdir")
find_config_file(start_dir = getwd(), filename = ".tasker.yml", max_depth = 10)
```

### Registration Functions

#### `register_task()` - Register a single task

```r
register_task(
  stage,                          # Stage name (e.g., "PREREQ", "DAILY")
  name,                           # Task name
  type = "R",                     # Task type: "R", "python", "sh", etc.
  description = NULL,             # Optional description
  total_subtasks = NULL,          # Expected number of subtasks
  expected_duration_minutes = NULL,  # Expected runtime
  schedule = NULL                 # Optional cron schedule
)
```

**Examples:**
```r
# Simple registration
register_task(stage = "PREREQ", name = "Install R", type = "sh")
register_task(stage = "PREREQ", name = "Install System Dependencies", type = "sh")
register_task(stage = "DAILY", name = "DAILY_01_BDC_Locations.R", type = "R")

# With full details
register_task(
  stage = "DAILY",
  name = "DAILY_01_BDC_Locations.R",
  type = "R",
  description = "Load BDC location data for all 56 states",
  total_subtasks = 56,
  expected_duration_minutes = 120,
  schedule = "0 2 * * *"  # Daily at 2 AM
)
```

#### `register_tasks()` - Register multiple tasks from data frame

```r
register_tasks(tasks_df)
```

**Example:**
```r
tasks_df <- data.frame(
  stage = c("PREREQ", "PREREQ", "DAILY", "DAILY"),
  name = c(
    "Install System Dependencies",
    "Install R",
    "DAILY_01_BDC_Locations.R",
    "DAILY_02_Provider_Tables.R"
  ),
  type = c("sh", "sh", "R", "R"),
  description = c(
    "Install system packages",
    "Install R and packages",
    "Load BDC location data",
    "Update provider tables"
  ),
  total_subtasks = c(NA, NA, 56, 10),
  expected_duration_minutes = c(15, 30, 120, 30),
  schedule = c(NA, NA, "0 2 * * *", "0 4 * * *")
)

register_tasks(tasks_df)
```

#### `get_tasks()` - Get registered tasks

```r
get_tasks(
  stage = NULL,     # Filter by stage (optional)
  enabled = TRUE,   # Show only enabled tasks
  conn = NULL       # Database connection (optional)
)
```

**Examples:**
```r
# Get all tasks
all_tasks <- get_tasks()

# Get tasks for specific stage
daily_tasks <- get_tasks(stage = "DAILY")

# Get all tasks including disabled
all_including_disabled <- get_tasks(enabled = NULL)
```

### Tracking Functions

#### `track_init()` - Initialize task tracking

```r
track_init(
  task_name,              # Name of task being tracked
  total_subtasks = NULL,  # Expected number of subtasks
  stage = NULL,           # Stage (auto-detected if NULL)
  script_path = NULL,     # Full path to script file (optional)
  script_file = NULL,     # Script filename (optional)
  log_path = NULL,        # Full path to log directory (optional)
  log_file = NULL,        # Log filename (optional)
  db_conn = NULL          # Database connection (optional)
)
```

**Examples:**
```r
# Simple
track_init("DAILY_01_BDC_Locations.R")

# With subtask count
track_init("DAILY_01_BDC_Locations.R", total_subtasks = 56)

# With explicit stage and file paths
track_init(
  task_name = "Process States", 
  total_subtasks = 56, 
  stage = "PROCESSING",
  script_path = "/home/pipeline/scripts",
  script_file = "process_states.R",
  log_path = "/home/pipeline/logs",
  log_file = "process_states_20251221.log"
)

# Auto-detect paths (helper function)
track_init(
  task_name = "DAILY_01_BDC_Locations.R",
  script_path = dirname(sys.frame(1)$ofile),
  script_file = basename(sys.frame(1)$ofile),
  log_path = getwd(),
  log_file = paste0(tools::file_path_sans_ext(basename(sys.frame(1)$ofile)), ".Rout")
)
```

#### `track_status()` - Update task status

```r
track_status(
  status = "RUNNING",           # Status: STARTED, RUNNING, FINISHED, FAILED
  current_subtask = NULL,       # Current subtask number
  subtask_name = NULL,          # Subtask description
  subtask_status = NULL,        # NOT_STARTED, RUNNING, COMPLETED, FAILED
  overall_percent = NULL,       # Overall progress override (0-100)
  overall_message = NULL,       # Overall progress message
  subtask_percent = NULL,       # Subtask progress override (0-100)
  subtask_message = NULL,       # Subtask progress message
  subtask_items_complete = NULL,  # Items completed
  subtask_items_total = NULL    # Total items
)
```

**Examples:**
```r
# Start a subtask
track_status(
  current_subtask = 1,
  subtask_name = "Loading Alabama data",
  subtask_status = "RUNNING"
)

# Update subtask progress
track_status(
  subtask_items_complete = 12,
  subtask_items_total = 56,
  subtask_message = "Processing state 12 of 56: Delaware"
)

# Complete a subtask
track_status(
  subtask_status = "COMPLETED"
)
```

#### `track_subtask_progress()` - Update subtask progress

```r
track_subtask_progress(
  items_complete,     # Number of items completed
  items_total = NULL, # Total items (optional)
  message = NULL      # Progress message (optional)
)
```

**Examples:**
```r
# In a loop
for (i in seq_along(states)) {
  process_state(states[i])
  track_subtask_progress(i, length(states), "Processed {states[i]}")
}

# Processing files
track_subtask_progress(5, 20, "Processing file 5 of 20")
```

#### `track_finish()` - Mark task complete

```r
track_finish(message = "Task completed successfully")
```

#### `track_error()` - Record failure

```r
track_error(error_msg, error_detail = NULL)
```

### Query Functions

#### `get_tasks()` - Get registered tasks

```r
get_tasks(
  stage = NULL,     # Filter by stage (optional)
  enabled = TRUE,   # Show only enabled tasks (default: TRUE)
  conn = NULL       # Database connection (optional)
)
```

**Returns:** Data frame with columns:
- `task_id`, `task_name`, `task_stage`, `task_type`
- `description`, `total_subtasks`, `expected_duration_minutes`, `schedule`
- `enabled`, `created_at`, `updated_at`

**Examples:**
```r
# Get all registered tasks
all_tasks <- get_tasks()

# Get tasks for specific stage
daily_tasks <- get_tasks(stage = "DAILY")
prereq_tasks <- get_tasks(stage = "PREREQ")

# Get all tasks including disabled
all_including_disabled <- get_tasks(enabled = NULL)

# View task details
print(daily_tasks[, c("task_name", "task_stage", "total_subtasks")])
```

#### `get_current_status()` - Get current execution status

```r
get_current_status(
  stage = NULL,     # Filter by stage (optional)
  task_name = NULL, # Filter by task name (optional)
  conn = NULL       # Database connection (optional)
)
```

**Returns:** Data frame with current status of tasks:
- **Task info:** `task_name`, `task_stage`, `task_type`
- **Execution:** `run_id`, `execution_status`, `execution_start`, `last_update`
- **Files:** `script_path`, `script_file`, `log_path`, `log_file`
- **Overall progress:** `current_subtask`, `total_subtasks`, `overall_percent_complete`, `overall_progress_message`
- **Subtask progress:** `subtask_percent_complete`, `subtask_progress_message`
- **Context:** `hostname`, `process_id`, `user_name`

**Examples:**
```r
# Get all currently executing tasks
status <- get_current_status()

# Get status for specific stage
daily_status <- get_current_status(stage = "DAILY")

# Get status for specific task
task_status <- get_current_status(task_name = "DAILY_01_BDC_Locations.R")

# Check what's running
running <- status[status$execution_status == "RUNNING", ]
cat(sprintf("Currently running: %d tasks\n", nrow(running)))

# Show progress for running tasks
for (i in seq_len(nrow(running))) {
  cat(sprintf(
    "%s: Subtask %d/%d (%.1f%%) - %s\n",
    running$task_name[i],
    running$current_subtask[i],
    running$total_subtasks[i],
    running$overall_percent_complete[i],
    running$overall_progress_message[i]
  ))
}
```

#### `get_execution_history()` - Get execution history

```r
get_execution_history(
  task_name = NULL,   # Filter by task name (optional)
  stage = NULL,       # Filter by stage (optional)
  status = NULL,      # Filter by status (optional)
  start_date = NULL,  # Filter by start date (optional)
  end_date = NULL,    # Filter by end date (optional)
  limit = 100,        # Maximum number of records (default: 100)
  conn = NULL         # Database connection (optional)
)
```

**Returns:** Data frame with historical executions:
- **Task info:** `task_name`, `task_stage`, `task_type`
- **Execution:** `run_id`, `execution_status`, `execution_start`, `execution_end`
- **Files:** `script_path`, `script_file`, `log_path`, `log_file`
- **Duration:** `duration_minutes`
- **Progress:** `total_subtasks`, `overall_percent_complete`
- **Result:** `error_message` (if failed)
- **Context:** `hostname`, `user_name`

**Examples:**
```r
# Get recent history for all tasks
recent <- get_execution_history(limit = 50)

# Get history for specific task
task_history <- get_execution_history(
  task_name = "DAILY_01_BDC_Locations.R",
  limit = 30
)

# Get failures in last 7 days
failures <- get_execution_history(
  status = "FAILED",
  start_date = Sys.Date() - 7,
  end_date = Sys.Date()
)

# Get all DAILY runs this month
daily_runs <- get_execution_history(
  stage = "DAILY",
  start_date = as.Date("2025-12-01"),
  end_date = as.Date("2025-12-31")
)

# Calculate average duration
avg_duration <- mean(task_history$duration_minutes, na.rm = TRUE)
cat(sprintf("Average duration: %.1f minutes\n", avg_duration))
```

#### `get_execution_details()` - Get detailed execution information

```r
get_execution_details(
  run_id,           # Execution run ID (UUID)
  conn = NULL       # Database connection (optional)
)
```

**Returns:** List with complete execution details:
- **task:** Task identification (name, stage, type)
- **execution:** Execution context (hostname, PID, user, times, status)
- **files:** Script path, script file, log path, log file
- **progress:** Overall and subtask progress
- **subtasks:** Data frame of all subtask updates (if tracked)
- **metadata:** Environment, git commit, resource usage

**Examples:**
```r
# Get details for specific execution
details <- get_execution_details(run_id = "550e8400-e29b-41d4-a716-446655440000")

# View task info
cat(sprintf("Task: %s (%s)\n", details$task$name, details$task$stage))

# View execution timeline
cat(sprintf("Started: %s\n", details$execution$start))
cat(sprintf("Ended: %s\n", details$execution$end))
cat(sprintf("Duration: %.1f minutes\n", details$execution$duration_minutes))

# View progress
cat(sprintf("Progress: %d/%d subtasks (%.1f%%)\n",
  details$progress$current_subtask,
  details$progress$total_subtasks,
  details$progress$overall_percent
))

# Check for errors
if (details$execution$status == "FAILED") {
  cat(sprintf("Error: %s\n", details$execution$error_message))
}
```

#### `get_stage_summary()` - Get summary by stage

```r
get_stage_summary(
  stage = NULL,     # Specific stage or NULL for all
  conn = NULL       # Database connection (optional)
)
```

**Returns:** Data frame with stage-level summary:
- `stage`: Stage name
- `total_tasks`: Number of registered tasks
- `running_tasks`: Number currently running
- `completed_today`: Successful completions today
- `failed_today`: Failures today
- `avg_duration_minutes`: Average execution time
- `last_run`: Most recent execution timestamp

**Examples:**
```r
# Get summary for all stages
summary <- get_stage_summary()

# Print summary table
print(summary[, c("stage", "total_tasks", "running_tasks", "completed_today")])

# Get details for specific stage
daily_summary <- get_stage_summary(stage = "DAILY")
cat(sprintf(
  "DAILY stage: %d/%d tasks completed today\n",
  daily_summary$completed_today,
  daily_summary$total_tasks
))
```

#### `get_performance_stats()` - Get performance statistics

```r
get_performance_stats(
  task_name,        # Task name
  days = 30,        # Number of days to analyze (default: 30)
  conn = NULL       # Database connection (optional)
)
```

**Returns:** List with performance metrics:
- `task_name`: Task name
- `executions`: Total number of executions
- `success_count`: Successful executions
- `failure_count`: Failed executions
- `success_rate`: Success percentage
- `avg_duration_minutes`: Average duration
- `min_duration_minutes`: Fastest execution
- `max_duration_minutes`: Slowest execution
- `std_duration_minutes`: Duration standard deviation
- `last_success`: Timestamp of last success
- `last_failure`: Timestamp of last failure

**Examples:**
```r
# Get stats for specific task
stats <- get_performance_stats("DAILY_01_BDC_Locations.R", days = 90)

# Print performance report
cat(sprintf("Task: %s\n", stats$task_name))
cat(sprintf("Executions: %d (last %d days)\n", stats$executions, 90))
cat(sprintf("Success Rate: %.1f%%\n", stats$success_rate))
cat(sprintf("Avg Duration: %.1f ± %.1f minutes\n", 
  stats$avg_duration_minutes,
  stats$std_duration_minutes
))
cat(sprintf("Range: %.1f - %.1f minutes\n",
  stats$min_duration_minutes,
  stats$max_duration_minutes
))

# Check if task is reliable
if (stats$success_rate < 95) {
  warning(sprintf("%s has low success rate: %.1f%%", 
    stats$task_name, stats$success_rate))
}
```

---

## Database Schema

### Table: `tasker.tasks` (Registered Tasks)

```sql
CREATE TABLE tasker.tasks (
    task_id SERIAL PRIMARY KEY,
    task_name VARCHAR(255) NOT NULL UNIQUE,
    task_stage VARCHAR(50),
    task_type VARCHAR(10) DEFAULT 'R',
    description TEXT,
    total_subtasks INTEGER,
    expected_duration_minutes NUMERIC(10,2),
    schedule VARCHAR(100),
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Table: `tasker.executions` (Execution Tracking)

```sql
CREATE TABLE tasker.executions (
    execution_id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL UNIQUE,
    
    -- Task identification
    task_name VARCHAR(255) NOT NULL,
    task_stage VARCHAR(50),
    task_type VARCHAR(10) DEFAULT 'R',
    
    -- Execution context
    hostname VARCHAR(255) NOT NULL,
    process_id INTEGER NOT NULL,
    user_name VARCHAR(100),
    
    -- File paths
    script_path VARCHAR(500),       -- Directory path to script
    script_file VARCHAR(255),       -- Script filename
    log_path VARCHAR(500),          -- Directory path to log file
    log_file VARCHAR(255),          -- Log filename
    
    -- Timing
    execution_start TIMESTAMPTZ NOT NULL,
    execution_end TIMESTAMPTZ,
    last_update TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    execution_status VARCHAR(20) NOT NULL,
    
    -- Subtask tracking
    total_subtasks INTEGER,
    current_subtask INTEGER,
    subtask_name VARCHAR(500),
    subtask_status VARCHAR(20),
    
    -- Overall progress
    overall_percent_complete NUMERIC(5,2),
    overall_progress_message TEXT,
    
    -- Subtask progress
    subtask_percent_complete NUMERIC(5,2),
    subtask_progress_message TEXT,
    subtask_items_total BIGINT,
    subtask_items_complete BIGINT,
    
    -- Additional metadata
    memory_mb INTEGER,
    error_message TEXT,
    error_detail TEXT,
    git_commit VARCHAR(40),
    environment JSONB
);
```

### View: `tasker.monitoring_view`

```sql
CREATE VIEW tasker.monitoring_view AS
SELECT 
    t.task_name,
    t.task_stage,
    t.task_type,
    t.description,
    t.schedule,
    t.expected_duration_minutes,
    e.execution_status,
    e.execution_start,
    e.last_update,
    e.overall_percent_complete,
    e.subtask_percent_complete,
    e.overall_progress_message,
    e.subtask_progress_message,
    CASE 
        WHEN e.execution_status IS NULL THEN 'NOT_STARTED'
        ELSE e.execution_status
    END as display_status
FROM tasker.tasks t
LEFT JOIN tasker.current_status e ON t.task_name = e.task_name
WHERE t.enabled = TRUE
ORDER BY t.task_stage, t.task_name;
```

---

## Configuration Management

### Overview

`tasker` uses a flexible, layered configuration system:

1. **Auto-discovery**: Searches up directory tree for `.tasker.yml`
2. **Environment variables**: Override config file settings
3. **Explicit parameters**: Override all other settings
4. **Lazy loading**: Configuration loaded on first use
5. **Caching**: Configuration stored in options for performance

### Configuration File Format

**`.tasker.yml`**

```yaml
# Database connection settings
database:
  host: db.example.com
  port: 5432
  dbname: geodb
  user: tasker_user
  password: ${TASKER_DB_PASSWORD}  # Environment variable substitution
  schema: tasker
  driver: postgresql

# Optional: Connection pool settings
pool:
  min_size: 1
  max_size: 5
  idle_timeout: 300

# Optional: Default stage detection patterns
stage_patterns:
  PREREQ: "^(prereq|setup|install)"
  DAILY: "^DAILY_"
  MONTHLY: "^MONTHLY_"
  ANNUAL_DEC: "^ANNUAL_DEC_"

# Optional: Logging settings
logging:
  level: INFO
  file: tasker.log
  console: true
```

### Configuration Precedence

Settings are applied in order (last wins):

1. **Built-in defaults**
2. **Configuration file** (`.tasker.yml`)
3. **Environment variables** (`TASKER_DB_HOST`, etc.)
4. **Explicit parameters** (passed to `tasker_config()`)

### Usage Examples

#### Example 1: Auto-discovery (Recommended)

```r
library(tasker)

# No configuration needed - tasker finds .tasker.yml automatically
# Configuration loaded on first function call
track_init("my_script.R")

# Configuration is now loaded and cached
status <- get_current_status()
```

**Directory structure:**
```
/home/user/project/
├── .tasker.yml          # Configuration file
├── scripts/
│   └── analysis/
│       └── my_script.R  # Your script (tasker finds config 2 levels up)
└── data/
```

#### Example 2: Explicit Configuration File

```r
# Load specific config file
tasker_config(config_file = "/path/to/custom.yml")

# Now use tasker functions
track_init("my_script.R")
```

#### Example 3: Override Specific Settings

```r
# Load config file but override host
tasker_config(host = "localhost", port = 5433)

# Or override multiple settings
tasker_config(
  config_file = "~/.tasker.yml",
  dbname = "test_db",
  schema = "tasker_test"
)
```

#### Example 4: Environment Variables Only

```bash
# Set in ~/.bashrc or ~/.Renviron
export TASKER_DB_HOST=db.example.com
export TASKER_DB_PORT=5432
export TASKER_DB_NAME=geodb
export TASKER_DB_USER=tasker_user
export TASKER_DB_PASSWORD=secret123
export TASKER_DB_SCHEMA=tasker
```

```r
# Configuration loaded from environment variables
# No .tasker.yml needed
library(tasker)
track_init("my_script.R")
```

#### Example 5: Programmatic Configuration

```r
# No config file, set everything in code
tasker_config(
  host = "localhost",
  port = 5432,
  dbname = "geodb",
  user = "tasker_user",
  password = keyring::key_get("tasker", "db_password"),
  schema = "tasker",
  driver = "postgresql"
)
```

#### Example 6: Check Current Configuration

```r
# Load config
tasker_config()

# View current settings
config <- get_tasker_config()
print(config)

# Output:
# $database
# $database$host
# [1] "db.example.com"
# $database$port
# [1] 5432
# ...
```

#### Example 7: Reload Configuration

```r
# Initial load
tasker_config()

# ... later, config file changed ...

# Force reload
tasker_config(reload = TRUE)
```

### Configuration File Discovery

The `find_config_file()` function searches up the directory tree:

```r
# How tasker finds .tasker.yml:
find_config_file()

# Search process:
# 1. Check /home/user/project/scripts/analysis/.tasker.yml
# 2. Check /home/user/project/scripts/.tasker.yml
# 3. Check /home/user/project/.tasker.yml  ← FOUND!
# Returns: "/home/user/project/.tasker.yml"
```

**Manual search:**
```r
# Find from specific directory
config_path <- find_config_file("/home/user/project/deep/nested/dir")

if (!is.null(config_path)) {
  tasker_config(config_file = config_path)
} else {
  stop("No .tasker.yml found in directory tree")
}
```

### Internal Implementation

**How configuration loading works:**

```r
# All tasker functions call ensure_configured() internally
track_init <- function(task_name, ...) {
  ensure_configured()  # No-op if already loaded
  
  # ... rest of function ...
}

# ensure_configured() implementation:
ensure_configured <- function() {
  if (!is.null(getOption("tasker.config"))) {
    return(invisible())  # Already loaded
  }
  
  # Auto-load configuration
  tasker_config()
}
```

### Configuration Storage

Configuration is stored in R options:

```r
# Set by tasker_config()
options(
  tasker.config = list(
    database = list(
      host = "db.example.com",
      port = 5432,
      dbname = "geodb",
      user = "tasker_user",
      schema = "tasker",
      driver = "postgresql"
    ),
    loaded_from = "/home/user/project/.tasker.yml",
    loaded_at = "2025-12-21 15:30:45"
  )
)

# Retrieved by functions
config <- getOption("tasker.config")
```

### Best Practices

#### ✅ DO

1. **Use `.tasker.yml` in project root** - Simple and portable
2. **Store passwords in environment variables** - Use `${VAR}` syntax
3. **Version control `.tasker.yml.example`** - Template for team
4. **Add `.tasker.yml` to `.gitignore`** - Don't commit secrets
5. **Use `keyring` for passwords** - Secure credential storage

```yaml
# .tasker.yml.example (commit this)
database:
  host: your-db-host
  port: 5432
  dbname: your-database
  user: your-user
  password: ${TASKER_DB_PASSWORD}  # Set in environment
  schema: tasker
  driver: postgresql
```

#### ❌ DON'T

1. **Don't commit passwords** - Always use environment variables
2. **Don't hardcode credentials** - Security risk
3. **Don't use multiple config files** - Causes confusion
4. **Don't call `tasker_config()` repeatedly** - Once per session

### Troubleshooting

#### Config file not found

```r
# Error: No .tasker.yml found in directory tree

# Solution 1: Check current directory
getwd()  # Are you in project directory?

# Solution 2: Find it manually
find_config_file()  # Returns path or NULL

# Solution 3: Use explicit path
tasker_config(config_file = "/full/path/to/.tasker.yml")

# Solution 4: Use environment variables instead
Sys.setenv(
  TASKER_DB_HOST = "localhost",
  TASKER_DB_PORT = "5432",
  TASKER_DB_NAME = "geodb",
  TASKER_DB_USER = "tasker_user"
)
tasker_config()
```

#### Connection failed

```r
# Error: Could not connect to database

# Check configuration
config <- get_tasker_config()
print(config$database)

# Test connection manually
library(DBI)
conn <- dbConnect(
  RPostgres::Postgres(),
  host = config$database$host,
  port = config$database$port,
  dbname = config$database$dbname,
  user = config$database$user,
  password = config$database$password
)
```

#### Wrong configuration loaded

```r
# Force reload
tasker_config(reload = TRUE)

# Or clear and reload
options(tasker.config = NULL)
tasker_config()
```

---

## Helper Functions

### `get_script_info()` - Auto-detect script details

```r
#' Get current script information
#'
#' @return List with path, file, and suggested log_file
#' @export
get_script_info <- function() {
  # Try to detect script being executed
  script_full <- NULL
  
  # Method 1: commandArgs
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_full <- sub("^--file=", "", file_arg[1])
  }
  
  # Method 2: sys.frame
  if (is.null(script_full)) {
    ofile <- sys.frame(1)$ofile
    if (!is.null(ofile)) {
      script_full <- ofile
    }
  }
  
  # Method 3: Look for Rout file in parent.frame
  if (is.null(script_full)) {
    # Check if running under R CMD BATCH
    for (i in 1:sys.nframe()) {
      frame_info <- sys.frame(i)
      if (!is.null(frame_info$ofile)) {
        script_full <- frame_info$ofile
        break
      }
    }
  }
  
  # Parse path and file
  if (!is.null(script_full)) {
    list(
      path = dirname(script_full),
      file = basename(script_full),
      log_path = getwd(),  # Default to current working directory
      log_file = paste0(tools::file_path_sans_ext(basename(script_full)), ".Rout")
    )
  } else {
    list(
      path = getwd(),
      file = "unknown_script",
      log_path = getwd(),
      log_file = "unknown.Rout"
    )
  }
}
```

**Example:**
```r
# Auto-detect current script
info <- get_script_info()

track_init(
  task_name = info$file,
  script_path = info$path,
  script_file = info$file,
  log_path = info$log_path,
  log_file = info$log_file
)
```

---

## Usage Patterns

### Pattern 1: Simple Task

```r
library(tasker)

# Initialize
track_init("Simple Task")

# Do work
result <- perform_calculation()

# Finish
track_finish("Calculation complete")
```

### Pattern 2: Task with Subtasks (with file tracking)

```r
library(tasker)

# Auto-detect script details
script_info <- list(
  path = dirname(sys.frame(1)$ofile),
  file = basename(sys.frame(1)$ofile)
)
log_info <- list(
  path = getwd(),
  file = paste0(tools::file_path_sans_ext(script_info$file), ".Rout")
)

# Initialize with file tracking
track_init(
  task_name = "Process States", 
  total_subtasks = 56,
  script_path = script_info$path,
  script_file = script_info$file,
  log_path = log_info$path,
  log_file = log_info$file
)

# Process each subtask
for (i in seq_along(states)) {
  track_status(
    current_subtask = i,
    subtask_name = "Processing {states[i]}",
    subtask_status = "RUNNING"
  )
  
  result <- process_state(states[i])
  
  track_status(subtask_status = "COMPLETED")
}

track_finish("All 56 states processed")
```

### Pattern 3: Task with Item-Level Progress

```r
library(tasker)

track_init("Load Large File", total_subtasks = 1)

track_status(
  current_subtask = 1,
  subtask_name = "Loading CSV file"
)

# Read in chunks with progress
data <- data.frame()
chunks <- 100
for (i in 1:chunks) {
  chunk <- read_chunk(file, i)
  data <- rbind(data, chunk)
  
  track_subtask_progress(i, chunks, "Loaded chunk {i} of {chunks}")
}

track_finish("Loaded {nrow(data)} rows")
```

### Pattern 4: Error Handling

```r
library(tasker)

tryCatch({
  track_init("Risky Operation", stage = "PROCESSING")
  
  track_status(subtask_name = "Attempting risky operation")
  result <- risky_function()
  
  track_finish()
  
}, error = function(e) {
  track_error(
    error_msg = conditionMessage(e),
    error_detail = as.character(traceback())
  )
  stop(e)
})
```

---

## Integration Example: fccData Pipeline

### 1. Register Pipeline Tasks

```r
# inst/config/register_pipeline.R
library(tasker)

# Register all pipeline tasks
register_task(stage = "PREREQ", name = "Install System Deps", type = "sh")
register_task(stage = "PREREQ", name = "Install R Packages", type = "R")

register_task(
  stage = "DAILY",
  name = "DAILY_01_BDC_Locations.R",
  type = "R",
  description = "Load BDC location data",
  total_subtasks = 56,
  expected_duration_minutes = 120,
  schedule = "0 2 * * *"
)

register_task(
  stage = "DAILY",
  name = "DAILY_02_Provider_Tables.R",
  type = "R",
  total_subtasks = 10,
  expected_duration_minutes = 30
)

# Or register from CSV
pipeline_tasks <- read.csv("inst/config/pipeline_tasks.csv")
register_tasks(pipeline_tasks)
```

### 2. Wrapper Functions

```r
# fccData/R/tracking.R

#' @export
genter <- function(message) {
  message_text <- glue::glue(message, .envir = parent.frame())
  
  if (is.null(getOption("fcc_pipeline_run_id"))) {
    task_name <- get_script_name()
    stage <- detect_pipeline_stage(task_name)
    run_id <- tasker::track_init(task_name, stage = stage)
    options(fcc_pipeline_run_id = run_id)
  }
  
  current_subtask <- getOption("fcc_pipeline_current_subtask", 0) + 1
  options(fcc_pipeline_current_subtask = current_subtask)
  
  tasker::track_status(
    current_subtask = current_subtask,
    subtask_name = as.character(message_text),
    subtask_status = "RUNNING"
  )
  
  invisible(NULL)
}

#' @export
gexit <- function() {
  tasker::track_status(subtask_status = "COMPLETED")
  invisible(NULL)
}

#' @export
gmessage <- function(message) {
  message_text <- glue::glue(message, .envir = parent.frame())
  tasker::track_status(subtask_message = as.character(message_text))
  invisible(NULL)
}
```

### 3. Script Usage

```r
# DAILY_01_BDC_Locations.R
library(fccData)

genter("Loading BDC data")

for (i in seq_along(states)) {
  state <- states[i]
  
  genter("Processing {state}")
  
  # Update progress within subtask
  tasker::track_subtask_progress(
    items_complete = i,
    items_total = length(states),
    message = "Processing state {i} of {length(states)}: {state}"
  )
  
  data <- load_bdc_data(state)
  write_to_database(data)
  
  gexit()
}

track_finish("Successfully processed {length(states)} states")
```

---

## Practical Query Examples

### Example 1: Dashboard Overview

```r
library(tasker)

# Get all stages and their status
stages <- get_stage_summary()

# Show stage overview
for (i in seq_len(nrow(stages))) {
  cat(sprintf(
    "%-15s | Tasks: %2d | Running: %2d | Today: %2d OK, %2d Failed | Avg: %5.1f min\n",
    stages$stage[i],
    stages$total_tasks[i],
    stages$running_tasks[i],
    stages$completed_today[i],
    stages$failed_today[i],
    stages$avg_duration_minutes[i]
  ))
}

# Get currently running tasks
running <- get_current_status()
running <- running[running$execution_status == "RUNNING", ]

if (nrow(running) > 0) {
  cat("\nCurrently Running:\n")
  for (i in seq_len(nrow(running))) {
    cat(sprintf(
      "  %s [%s]\n    Progress: %d/%d subtasks (%.1f%%) - %s\n",
      running$task_name[i],
      running$task_stage[i],
      running$current_subtask[i],
      running$total_subtasks[i],
      running$overall_percent_complete[i],
      running$overall_progress_message[i]
    ))
  }
}
```

### Example 2: Monitor Specific Stage

```r
# Monitor DAILY stage
daily_tasks <- get_tasks(stage = "DAILY")
daily_status <- get_current_status(stage = "DAILY")

# Merge to see expected vs actual
pipeline_view <- merge(
  daily_tasks[, c("task_name", "total_subtasks", "expected_duration_minutes")],
  daily_status[, c("task_name", "execution_status", "overall_percent_complete", 
                   "current_subtask", "execution_start")],
  by = "task_name",
  all.x = TRUE
)

# Show task status
for (i in seq_len(nrow(pipeline_view))) {
  status <- ifelse(is.na(pipeline_view$execution_status[i]), 
                   "NOT STARTED", 
                   pipeline_view$execution_status[i])
  
  if (status == "RUNNING") {
    elapsed <- difftime(Sys.time(), pipeline_view$execution_start[i], units = "mins")
    cat(sprintf(
      "%-40s | %s | %d/%d (%.0f%%) | %.0f/%.0f min\n",
      pipeline_view$task_name[i],
      status,
      pipeline_view$current_subtask[i],
      pipeline_view$total_subtasks[i],
      pipeline_view$overall_percent_complete[i],
      as.numeric(elapsed),
      pipeline_view$expected_duration_minutes[i]
    ))
  } else {
    cat(sprintf("%-40s | %s\n", pipeline_view$task_name[i], status))
  }
}
```

### Example 3: Performance Analysis

```r
# Analyze task performance over time
task_name <- "DAILY_01_BDC_Locations.R"

# Get recent statistics
stats <- get_performance_stats(task_name, days = 90)
history <- get_execution_history(task_name = task_name, limit = 100)

# Calculate trends
history$date <- as.Date(history$execution_start)
daily_avg <- aggregate(duration_minutes ~ date, history, mean)

# Plot trend (if ggplot2 available)
if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)
  
  ggplot(history, aes(x = execution_start, y = duration_minutes)) +
    geom_point(aes(color = execution_status)) +
    geom_smooth(method = "loess", se = TRUE) +
    geom_hline(yintercept = stats$avg_duration_minutes, 
               linetype = "dashed", color = "blue") +
    labs(
      title = sprintf("Performance: %s", task_name),
      subtitle = sprintf("Avg: %.1f ± %.1f min | Success: %.1f%%",
                        stats$avg_duration_minutes,
                        stats$std_duration_minutes,
                        stats$success_rate),
      x = "Execution Time",
      y = "Duration (minutes)"
    ) +
    theme_minimal()
}

# Identify outliers
outlier_threshold <- stats$avg_duration_minutes + 2 * stats$std_duration_minutes
outliers <- history[history$duration_minutes > outlier_threshold, ]

if (nrow(outliers) > 0) {
  cat(sprintf("\nFound %d outlier executions (>%.1f min):\n", 
              nrow(outliers), outlier_threshold))
  print(outliers[, c("execution_start", "duration_minutes", "execution_status")])
}
```

### Example 4: Failure Investigation

```r
# Find recent failures
failures <- get_execution_history(
  status = "FAILED",
  start_date = Sys.Date() - 7,
  limit = 50
)

if (nrow(failures) > 0) {
  cat(sprintf("Found %d failures in last 7 days:\n\n", nrow(failures)))
  
  # Group by task
  failure_counts <- table(failures$task_name)
  failure_df <- data.frame(
    task_name = names(failure_counts),
    failures = as.numeric(failure_counts)
  )
  failure_df <- failure_df[order(-failure_df$failures), ]
  
  # Show top failing tasks
  cat("Most frequent failures:\n")
  print(failure_df)
  
  # Get details for most problematic task
  top_failing <- failure_df$task_name[1]
  cat(sprintf("\nRecent failures for %s:\n", top_failing))
  
  task_failures <- failures[failures$task_name == top_failing, ]
  for (i in seq_len(min(5, nrow(task_failures)))) {
    details <- get_execution_details(task_failures$run_id[i])
    cat(sprintf(
      "\n%s:\n  Error: %s\n  At subtask: %d/%d\n",
      task_failures$execution_start[i],
      details$execution$error_message,
      details$progress$current_subtask,
      details$progress$total_subtasks
    ))
  }
}
```

### Example 5: Real-time Monitoring Loop

```r
# Monitor pipeline in real-time
monitor_pipeline <- function(stage = NULL, refresh_seconds = 10) {
  cat("Starting real-time monitor (Ctrl+C to stop)...\n\n")
  
  repeat {
    # Clear screen (Unix/Linux)
    cat("\014")
    
    # Get current status
    status <- get_current_status(stage = stage)
    running <- status[status$execution_status == "RUNNING", ]
    
    # Header
    cat(sprintf("Pipeline Monitor | %s | %d tasks running\n", 
                Sys.time(), nrow(running)))
    cat(paste(rep("=", 80), collapse = ""), "\n\n")
    
    if (nrow(running) == 0) {
      cat("No tasks currently running.\n")
    } else {
      # Show each running task
      for (i in seq_len(nrow(running))) {
        elapsed <- difftime(Sys.time(), running$execution_start[i], units = "mins")
        
        # Progress bar
        pct <- running$overall_percent_complete[i]
        bar_width <- 30
        filled <- round(bar_width * pct / 100)
        bar <- sprintf("[%s%s]",
                      paste(rep("=", filled), collapse = ""),
                      paste(rep(" ", bar_width - filled), collapse = ""))
        
        cat(sprintf(
          "%s [%s]\n  %s %.0f%% | Subtask %d/%d | %.0f min\n  %s\n\n",
          running$task_name[i],
          running$task_stage[i],
          bar,
          pct,
          running$current_subtask[i],
          running$total_subtasks[i],
          as.numeric(elapsed),
          running$overall_progress_message[i]
        ))
      }
    }
    
    # Wait before refresh
    Sys.sleep(refresh_seconds)
  }
}

# Usage:
# monitor_pipeline(stage = "DAILY", refresh_seconds = 10)
```

### Example 6: Access Log Files from Failed Tasks

```r
# Find failed tasks and their log files
failures <- get_execution_history(
  status = "FAILED",
  start_date = Sys.Date() - 1
)

if (nrow(failures) > 0) {
  cat(sprintf("Found %d failures:\n\n", nrow(failures)))
  
  for (i in seq_len(nrow(failures))) {
    cat(sprintf(
      "%d. %s\n   Failed at: %s\n   Log: %s/%s\n   Error: %s\n\n",
      i,
      failures$task_name[i],
      failures$execution_start[i],
      failures$log_path[i],
      failures$log_file[i],
      substr(failures$error_message[i], 1, 100)
    ))
    
    # Optionally open log file
    log_path <- file.path(failures$log_path[i], failures$log_file[i])
    if (file.exists(log_path)) {
      cat("   Last 10 lines of log:\n")
      log_lines <- tail(readLines(log_path, warn = FALSE), 10)
      cat(paste("   ", log_lines, collapse = "\n"), "\n\n")
    }
  }
  
  # Offer to open logs interactively
  if (interactive()) {
    choice <- readline(prompt = "Open log file? (1-N or 0 to skip): ")
    idx <- as.integer(choice)
    if (!is.na(idx) && idx > 0 && idx <= nrow(failures)) {
      log_path <- file.path(failures$log_path[idx], failures$log_file[idx])
      if (file.exists(log_path)) {
        # Open in system editor
        system2("less", log_path)
      }
    }
  }
}
```

### Example 7: Track Script Paths for Easy Navigation

```r
# Get currently running tasks with their locations
running <- get_current_status()
running <- running[running$execution_status == "RUNNING", ]

if (nrow(running) > 0) {
  cat("Currently running tasks:\n\n")
  
  for (i in seq_len(nrow(running))) {
    cat(sprintf(
      "%s\n  Script: %s/%s\n  Log: %s/%s\n  Progress: %d/%d (%.1f%%)\n  PID: %d on %s\n\n",
      running$task_name[i],
      running$script_path[i],
      running$script_file[i],
      running$log_path[i],
      running$log_file[i],
      running$current_subtask[i],
      running$total_subtasks[i],
      running$overall_percent_complete[i],
      running$process_id[i],
      running$hostname[i]
    ))
  }
  
  # Generate commands to tail logs
  cat("\nTo monitor logs in real-time:\n")
  for (i in seq_len(nrow(running))) {
    log_path <- file.path(running$log_path[i], running$log_file[i])
    cat(sprintf(
      "  tail -f %s  # %s on %s\n",
      log_path,
      running$task_name[i],
      running$hostname[i]
    ))
  }
}
```

---

## Benefits of This Design

### Clear Hierarchy
- **Stage** groups related tasks
- **Task** is a single executable unit
- **Subtask** shows progress within task

### Flexible Registration
- Simple one-liner: `register_task(stage, name, type)`
- Bulk loading: `register_tasks(data_frame)`
- Optional details: description, schedule, expected duration

### Consistent API
- `track_init()` starts tracking a **task**
- `track_status()` updates progress on current **subtask**
- `track_subtask_progress()` shows item-level progress
- `track_finish()` completes the **task**

### Dashboard-Ready
- `get_tasks()` returns all registered tasks
- `monitoring_view` shows registered + running + completed
- Stage-based grouping in UI
- Clear progress at both task and subtask levels

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-20  
**Status:** Final - Ready for Implementation
