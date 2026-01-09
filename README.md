# tasker

Task and Pipeline Execution Tracking

## Overview

`tasker` provides a comprehensive system for tracking the status and progress of tasks, subtasks, and pipeline executions in a PostgreSQL database. It supports hierarchical tracking (stages → tasks → subtasks) with detailed progress monitoring.

## What's New in v2.0 🎉

**Simplified API** - Dramatically reduced boilerplate code:
- **Context-based tracking**: No more passing `run_id` to every function
- **Auto-numbered subtasks**: Automatic subtask numbering
- **One-line parallel setup**: Simplified cluster initialization with `tasker_cluster()`
- **Auto-configuration**: Configuration loads automatically on first use
- **50-70% less boilerplate** while maintaining full backward compatibility

See the [API Simplification Proposal](inst/docs/API_SIMPLIFICATION_PROPOSAL.md) for details.

## Features

- **Hierarchical tracking**: Organize work into stages, tasks, and subtasks
- **Real-time progress monitoring**: Track overall and per-subtask progress
- **Database persistence**: Store execution history in PostgreSQL or SQLite
- **Flexible configuration**: YAML files, environment variables, or direct parameters
- **Rich metadata**: Capture hostname, PID, timing, errors, and custom metadata
- **Query functions**: Retrieve current status, history, and active tasks
- **Shiny dashboard**: Visual monitoring of pipeline execution
- **Parallel processing helpers**: Built-in support for parallel workflows

## Installation

```r
# Install from GitHub
devtools::install_github("Broadband-Catalysts/tasker")
```

## Quick Start

### 1. Configure

Create `.tasker.yml` in your project root:

```yaml
# PostgreSQL configuration
database:
  host: localhost
  port: 5432
  dbname: mydb
  user: ${USER}
  password: ${DB_PASSWORD}
  schema: tasker
  driver: postgresql

# Or SQLite configuration (simpler, no server required)
database:
  path: /path/to/tasker.db
  driver: sqlite
```

Or use environment variables:

```bash
export TASKER_DB_HOST=localhost
export TASKER_DB_PORT=5432
export TASKER_DB_NAME=mydb
export TASKER_DB_USER=myuser
export TASKER_DB_PASSWORD=mypassword
```

### 2. Initialize Schema

```r
library(tasker)

# Load configuration (auto-discovers .tasker.yml)
tasker_config()

# Create database schema
setup_tasker_db()

# Or force recreate (drops existing schema!)
setup_tasker_db(force = TRUE)
```

### 3. Register Tasks

```r
# Register individual tasks
register_task(stage = "PREREQ", name = "Install System Dependencies", type = "sh")
register_task(stage = "PREREQ", name = "Install R Packages", type = "R")

# Or register multiple tasks at once
tasks <- data.frame(
  stage = c("STATIC", "STATIC", "DAILY"),
  name = c("Build Database", "Create Indexes", "Update Records"),
  type = c("R", "SQL", "R")
)
register_tasks(tasks)
```

### 4. Track Execution

```r
# Start task
run_id <- task_start("STATIC", "Build Database", total_subtasks = 3)

# Track subtask 1
subtask_start(run_id, 1, "Loading data", items_total = 56)
for (i in 1:56) {
  # ... do work ...
  subtask_update(run_id, 1, "RUNNING", 
                 percent = (i/56)*100, 
                 items_complete = i,
                 message = sprintf("Processing item %d", i))
}
subtask_complete(run_id, 1, "Data loaded")

# Track subtask 2
subtask_start(run_id, 2, "Processing")
# ... do work ...
subtask_complete(run_id, 2)

# Complete task
task_complete(run_id, "All subtasks finished")
```

### 5. Query Status

```r
# Get current status of all tasks
get_task_status()

# Get active (running) tasks
get_active_tasks()

# Get task history
get_task_history(stage = "STATIC", limit = 50)

# Get subtask details
get_subtask_progress(run_id)
```

## NEW: Simplified API Examples

### Context-Based Tracking (No run_id!)

```r
# Start task - becomes active context
task_start("PROCESS", "Data Analysis")

# All subsequent calls use context automatically
subtask_start("Load data", items_total = 100)
subtask_update(status = "RUNNING", items_complete = 50)
subtask_complete()

# Auto-numbered subtasks!
subtask_start("Transform data")
subtask_complete()

task_complete("Analysis done")
```

### Simplified Parallel Processing

```r
task_start("PROCESS", "County Analysis")
subtask_start("Process counties", items_total = 3143)

# One-line cluster setup!
cl <- tasker_cluster(
  ncores = 16,
  export = c("counties")
)

# Workers use context automatically
results <- parallel::parLapplyLB(cl, counties, function(county_fips) {
  result <- analyze_county(county_fips)
  subtask_increment(increment = 1, quiet = TRUE)
  return(result)
})

stop_tasker_cluster(cl)
subtask_complete()
task_complete()
```

### API Comparison

**Old API (still works, backward compatible):**
```r
run_id <- task_start("STAGE", "Task", total_subtasks = 3)
subtask_start(run_id, 1, "Load", items_total = 100)
subtask_update(run_id, 1, "RUNNING", items_complete = 50)
subtask_complete(run_id, 1)
task_complete(run_id)
```

**New API (cleaner, less boilerplate):**
```r
task_start("STAGE", "Task")
subtask_start("Load", items_total = 100)
subtask_update(status = "RUNNING", items_complete = 50)
subtask_complete()
task_complete()
```

**Result: 50-70% reduction in boilerplate code!**

See [inst/examples/example_pipeline_simplified.R](inst/examples/example_pipeline_simplified.R) for a complete working example.

## Shiny Dashboard

The package includes an interactive Shiny dashboard for visual monitoring of pipeline execution.

### Launching the Dashboard

```r
# Launch from within R
tasker::run_monitor()

# Launch on a specific port
tasker::run_monitor(port = 8080)

# Or run from the command line
R -e "tasker::run_monitor()"
```

### Dashboard Features

The Shiny app provides real-time monitoring with three main views:

**Overview Tab:**
- Interactive table showing all tasks with their current status
- Color-coded status indicators (running, completed, failed, etc.)
- Stage and status filtering
- Click on any task to see detailed information including:
  - Task identification (ID, stage, name, type)
  - Execution timing (start time, duration, last update)
  - Progress tracking (task and overall progress percentages)
  - Subtask progress with individual status and completion
  - Error messages and logs (if applicable)
  - Process information (hostname, PID)

**Stage Summary Tab:**
- Visual progress charts by stage
- Summary statistics for each pipeline stage
- Task count and completion status

**Timeline Tab:**
- Gantt-chart style visualization of task execution
- Shows start times, durations, and overlapping executions
- Useful for identifying bottlenecks and parallelization opportunities

### Configuration

The dashboard uses the same configuration as the rest of the package (`.tasker.yml` or environment variables). Make sure your database connection is properly configured before launching.

### Auto-refresh

- Configurable auto-refresh interval (default: 5 seconds)
- Manual refresh button for on-demand updates
- Displays last update timestamp

## Configuration

`tasker` supports three configuration methods (in order of precedence):

1. **Direct parameters** to `tasker_config()`
2. **Environment variables** (`TASKER_DB_*`)
3. **YAML configuration file** (`.tasker.yml`)

The package automatically searches for `.tasker.yml` starting from the current directory and walking up the directory tree.

### Database Drivers

**PostgreSQL** (production use):
```yaml
database:
  driver: postgresql
  host: localhost
  port: 5432
  dbname: mydb
  user: myuser
  password: mypassword
  schema: tasker
```

**SQLite** (testing, single-user, or embedded use):
```yaml
database:
  driver: sqlite
  path: /path/to/tasker.db
```

SQLite is ideal for:
- Unit testing
- Single-user applications
- Embedded systems
- Development environments
- No need for a database server

## Status Values

**Task Status:**
- `NOT_STARTED` - Registered but not yet started
- `STARTED` - Just started
- `RUNNING` - Currently executing
- `COMPLETED` - Finished successfully
- `FAILED` - Finished with errors
- `SKIPPED` - Deliberately skipped
- `CANCELLED` - Cancelled mid-execution

**Subtask Status:**
- `NOT_STARTED`, `STARTED`, `RUNNING`, `COMPLETED`, `FAILED`, `SKIPPED`

## Database Schema

The package uses four main tables:

- **`stages`** - Pipeline stages (e.g., PREREQ, STATIC, DAILY)
- **`tasks`** - Tasks within stages
- **`task_runs`** - Individual task executions
- **`subtask_progress`** - Progress tracking for subtasks

## License

GPL-3

## Author

Gregory Warnes <greg@warnes.net>
