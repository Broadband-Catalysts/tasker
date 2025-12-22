# tasker Package - Terminology Verification

**Date:** 2025-12-20  
**Purpose:** Verify consistent terminology across all documentation

---

## ✅ Correct Terminology

### Three-Level Hierarchy

```
Stage (Pipeline Phase)
  └─ Task (Work Unit)  
      └─ Subtask (Progress Item)
```

### Field Naming Convention

| Level | Singular | Plural | Column Names | Examples |
|-------|----------|--------|--------------|----------|
| **Stage** | `stage` | `stages` | `task_stage` | PREREQ, DAILY, MONTHLY, ANNUAL_DEC |
| **Task** | `task` | `tasks` | `task_name`, `task_type`, `task_id` | "Install R", "DAILY_01_BDC_Locations.R" |
| **Subtask** | `subtask` | `subtasks` | `subtask_name`, `subtask_status`, `current_subtask`, `total_subtasks` | "State 12 of 56", "File 3 of 8" |

---

## ❌ Incorrect/Deprecated Terms

| ❌ Don't Use | ✅ Use Instead | Context |
|-------------|----------------|---------|
| `script_name` | `task_name` | Task identification |
| `script_category` | `task_stage` | Stage grouping |
| `script_type` | `task_type` | Type of task |
| `execution_name` | `task_name` | Task being executed |
| `execution_stage` | `task_stage` | Task's stage |
| `total_tasks` | `total_subtasks` | Count of subtasks |
| `current_task` | `current_subtask` | Current subtask number |
| `task_name` (in executions) | `subtask_name` | Name of current subtask |
| `task_status` (in executions) | `subtask_status` | Status of subtask |
| `task_percent_complete` | `subtask_percent_complete` | Subtask progress |
| `task_progress_message` | `subtask_progress_message` | Subtask message |
| `task_items_*` | `subtask_items_*` | Item counts |

---

## Database Schema - Correct Field Names

### Table: `tasker.tasks` (Registered Tasks)

```sql
CREATE TABLE tasker.tasks (
    task_id SERIAL PRIMARY KEY,
    task_name VARCHAR(255) NOT NULL UNIQUE,     -- ✅ Correct
    task_stage VARCHAR(50),                      -- ✅ Correct (not script_category)
    task_type VARCHAR(10) DEFAULT 'R',          -- ✅ Correct (not script_type)
    description TEXT,
    total_subtasks INTEGER,                      -- ✅ Correct (not total_tasks)
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
    task_name VARCHAR(255) NOT NULL,            -- ✅ Correct (not script_name)
    task_stage VARCHAR(50),                      -- ✅ Correct (not script_category)
    task_type VARCHAR(10) DEFAULT 'R',          -- ✅ Correct (not script_type)
    
    -- Execution context
    hostname VARCHAR(255) NOT NULL,
    process_id INTEGER NOT NULL,
    user_name VARCHAR(100),
    
    -- Timing
    execution_start TIMESTAMPTZ NOT NULL,
    execution_end TIMESTAMPTZ,
    last_update TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    execution_status VARCHAR(20) NOT NULL,
    
    -- Subtask tracking
    total_subtasks INTEGER,                      -- ✅ Correct (not total_tasks)
    current_subtask INTEGER,                     -- ✅ Correct (not current_task)
    subtask_name VARCHAR(500),                   -- ✅ Correct (not task_name)
    subtask_status VARCHAR(20),                  -- ✅ Correct (not task_status)
    
    -- Overall progress
    overall_percent_complete NUMERIC(5,2),
    overall_progress_message TEXT,
    
    -- Subtask progress  
    subtask_percent_complete NUMERIC(5,2),       -- ✅ Correct (not task_percent_complete)
    subtask_progress_message TEXT,               -- ✅ Correct (not task_progress_message)
    subtask_items_total BIGINT,                  -- ✅ Correct (not task_items_total)
    subtask_items_complete BIGINT,               -- ✅ Correct (not task_items_complete)
    
    -- Metadata
    memory_mb INTEGER,
    error_message TEXT,
    error_detail TEXT,
    git_commit VARCHAR(40),
    environment JSONB
);
```

---

## Function Names - Correct Usage

### Registration Functions

```r
# ✅ Correct
register_task(stage, name, type)
register_tasks(tasks_df)
get_tasks(stage)

# ❌ Incorrect (deprecated)
register_execution(execution_name, ...)
register_executions(...)
get_registered_executions()
```

### Tracking Functions

```r
# ✅ Correct
track_init(task_name, total_subtasks, stage)
track_status(current_subtask, subtask_name, subtask_status)
track_subtask_progress(items_complete, items_total)

# ❌ Incorrect (deprecated)
track_init(script_name, total_tasks, category)
track_status(current_task, task_name, task_status)
track_task_progress(...)
```

---

## Code Examples - Correct Usage

### ✅ Correct Example

```r
# Register a task
register_task(
  stage = "DAILY",
  name = "DAILY_01_BDC_Locations.R",
  type = "R",
  total_subtasks = 56
)

# Track execution
track_init("DAILY_01_BDC_Locations.R", total_subtasks = 56)

for (i in seq_along(states)) {
  track_status(
    current_subtask = i,
    subtask_name = "Processing {states[i]}",
    subtask_status = "RUNNING"
  )
  
  process_state(states[i])
  
  track_subtask_progress(
    items_complete = i,
    items_total = length(states),
    message = "State {i} of {length(states)}"
  )
  
  track_status(subtask_status = "COMPLETED")
}

track_finish()
```

### ❌ Incorrect Example (deprecated)

```r
# DON'T DO THIS
track_init(script_name = "...", total_tasks = 56)
track_status(current_task = i, task_name = "...", task_status = "RUNNING")
track_task_progress(...)
```

---

## Verification Checklist

- [x] **TASKER_API_REFERENCE.md** - Uses correct terminology
- [x] **PIPELINE_STATUS_TRACKING_PACKAGE_PLAN.md** - Uses correct terminology  
- [x] **PIPELINE_STATUS_TRACKING_DESIGN.md** - Fixed to use correct terminology
- [x] SQL schemas use `task_*` and `subtask_*` fields
- [x] Function parameters use correct names
- [x] Code examples use correct terminology
- [x] Comments and documentation consistent

---

## Summary

**All documentation now uses consistent terminology:**

- **Stage** = Pipeline phase (e.g., PREREQ, DAILY)
- **Task** = Work unit being executed (e.g., script, process)
- **Subtask** = Progress items within a task (e.g., states, files)

**Field naming pattern:**
- `task_*` for task-related fields
- `subtask_*` for subtask-related fields  
- `*_stage` for stage grouping

**No more:**
- `script_*` fields
- `execution_*` for task identification
- `task_*` for what are actually subtasks

---

**Status:** ✅ **Terminology is now consistent across all documents**

