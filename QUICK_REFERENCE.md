# tasker Quick Reference

## Setup

```r
library(tasker)
tasker_config()          # Auto-discover .tasker.yml or use env vars
create_schema()          # Initialize database (first time only)
```

## Register Tasks

```r
# Single task
register_task(stage = "STATIC", name = "Build Database", type = "R")

# Multiple tasks
register_tasks(data.frame(
  stage = c("PREREQ", "STATIC", "DAILY"),
  name = c("Setup", "Build", "Update"),
  type = c("sh", "R", "R")
))
```

## Track Execution

### Simple (no subtasks)

```r
run_id <- task_start("STATIC", "Build Database")
# ... do work ...
task_complete(run_id)
```

### With subtasks

```r
run_id <- task_start("STATIC", "Process Data", total_subtasks = 3)

# Subtask 1
subtask_start(run_id, 1, "Load data", items_total = 100)
for (i in 1:100) {
  # ... process item i ...
  subtask_update(run_id, 1, "RUNNING", percent = i, items_complete = i)
}
subtask_complete(run_id, 1)

# Subtask 2
subtask_start(run_id, 2, "Transform data")
# ... do work ...
subtask_complete(run_id, 2)

# Subtask 3
subtask_start(run_id, 3, "Save data")
# ... do work ...
subtask_complete(run_id, 3)

task_complete(run_id)
```

### With error handling

```r
run_id <- task_start("STATIC", "Build Database")

tryCatch({
  # ... do work ...
  task_complete(run_id)
}, error = function(e) {
  task_fail(run_id, error_message = e$message,
                    error_detail = paste(capture.output(traceback()), collapse = "\n"))
})
```

## Query Status

```r
# Current status of all tasks
get_task_status()

# Currently running tasks
get_active_tasks()

# Status of specific stage
get_task_status(stage = "STATIC")

# Status of specific task
get_task_status(task = "Build Database")

# Only failed tasks
get_task_status(status = "FAILED")

# Task execution history
get_task_history(stage = "STATIC", limit = 50)

# Subtask details for a run
get_subtask_progress(run_id)

# All registered tasks
get_tasks()

# All stages
get_stages()
```

## Configuration

### .tasker.yml (recommended)

Place in project root:

```yaml
database:
  host: localhost
  port: 5432
  dbname: mydb
  user: ${USER}
  password: ${DB_PASSWORD}
  schema: tasker
  driver: postgresql
```

### Environment variables

```bash
export TASKER_DB_HOST=localhost
export TASKER_DB_PORT=5432
export TASKER_DB_NAME=mydb
export TASKER_DB_USER=myuser
export TASKER_DB_PASSWORD=secret
export TASKER_DB_SCHEMA=tasker
```

### Direct parameters

```r
tasker_config(
  host = "localhost",
  port = 5432,
  dbname = "mydb",
  user = "myuser",
  password = "secret"
)
```

## Status Values

**Task Status:**
- `NOT_STARTED` - Registered but not started
- `STARTED` - Just started
- `RUNNING` - Currently executing
- `COMPLETED` - Finished successfully
- `FAILED` - Finished with errors
- `SKIPPED` - Deliberately skipped
- `CANCELLED` - Cancelled mid-execution

**Subtask Status:**
- `NOT_STARTED`, `STARTED`, `RUNNING`, `COMPLETED`, `FAILED`, `SKIPPED`

## Function Reference

### Configuration
- `tasker_config()` - Load/set configuration
- `find_config_file()` - Find .tasker.yml file
- `get_tasker_config()` - Get current configuration

### Connection
- `get_db_connection()` - Get database connection
- `create_schema()` - Create database schema

### Registration
- `register_task()` - Register single task
- `register_tasks()` - Register multiple tasks
- `get_tasks()` - Get registered tasks

### Task Tracking
- `task_start()` - Start tracking task
- `task_update()` - Update task status
- `task_complete()` - Mark task complete
- `task_fail()` - Mark task failed

### Subtask Tracking
- `subtask_start()` - Start tracking subtask
- `subtask_update()` - Update subtask status
- `subtask_complete()` - Mark subtask complete
- `subtask_fail()` - Mark subtask failed

### Queries
- `get_task_status()` - Get current task status
- `get_active_tasks()` - Get running tasks
- `get_subtask_progress()` - Get subtask details
- `get_stages()` - Get all stages
- `get_task_history()` - Get execution history

## Common Patterns

### Progress bar style updates

```r
subtask_start(run_id, 1, "Processing items", items_total = n)
for (i in 1:n) {
  # ... process item ...
  if (i %% 10 == 0) {  # Update every 10 items
    subtask_update(run_id, 1, "RUNNING",
                   percent = (i/n)*100,
                   items_complete = i,
                   message = sprintf("Processed %d/%d items", i, n))
  }
}
subtask_complete(run_id, 1)
```

### With existing genter/gexit

```r
# At script start (where genter() is)
run_id <- task_start("STATIC", "My Script", total_subtasks = 2)

# At task boundaries
subtask_start(run_id, 1, "Task 1")
# ... existing code ...
subtask_complete(run_id, 1)

subtask_start(run_id, 2, "Task 2")
# ... existing code ...
subtask_complete(run_id, 2)

# At script end (where gexit() is)
task_complete(run_id)
```

### Conditional subtask execution

```r
run_id <- task_start("STATIC", "My Script", total_subtasks = 3)

subtask_start(run_id, 1, "Always runs")
# ... work ...
subtask_complete(run_id, 1)

if (condition) {
  subtask_start(run_id, 2, "Conditional task")
  # ... work ...
  subtask_complete(run_id, 2)
} else {
  # Still record that we skipped it
  subtask_start(run_id, 2, "Conditional task")
  subtask_update(run_id, 2, "SKIPPED", message = "Condition not met")
}

subtask_start(run_id, 3, "Cleanup")
# ... work ...
subtask_complete(run_id, 3)

task_complete(run_id)
```

## Tips

- Always capture `run_id` from `task_start()` - you'll need it for all other calls
- Update progress regularly (every 100 items or every 10%) but not too frequently
- Use meaningful subtask names that describe the work being done
- Include the run_id in your log messages for easy correlation
- Test tracking code with small data first
- Tracking failures should never halt your script - they're logged but ignored
