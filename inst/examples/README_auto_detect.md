# Automatic Script Detection

The tasker package can automatically detect the executing script filename and look up the associated stage and task from the database.

## How It Works

1. **Script Detection**: Uses the `this.path` package to detect the script filename
2. **Database Lookup**: Queries the `tasks` table using `script_filename` 
3. **Automatic Tracking**: Starts task tracking without manual configuration

## Usage

### New Way: Auto-Detection (Zero Configuration!)

```r
# Just call task_start() with no parameters!
task_start()
subtask_start("Processing")
# ... do work ...
subtask_complete()
task_complete()
```

### Old Way: Explicit Parameters (Still Supported)

```r
# Traditional explicit parameters
task_start("ANNUAL_SEPT", "Road Lengths")
subtask_start("Processing")
# ... do work ...
subtask_complete()
task_complete()
```

## Requirements

1. **Register tasks with script_filename**: When using `register_task()`, include the `script_filename` parameter:

```r
register_task(
  stage = "ANNUAL_SEPT",
  name = "Road Lengths",
  type = "R",
  script_filename = "03_ANNUAL_SEPT_03_Road_Lengths_Hex.R",
  description = "Calculate road lengths per hexagon"
)
```

2. **Run script via Rscript or R CMD BATCH**: Auto-detection works when scripts are executed via:
   - `Rscript script.R`
   - `R CMD BATCH script.R`
   - `make` targets that use the above
   - RStudio's "Source" button

## Benefits

- **No redundancy**: Stage/task defined once during registration
- **No typos**: Can't mismatch script file with wrong stage/task
- **Simpler scripts**: Less boilerplate at top of each script
- **Consistency**: All scripts use same pattern

## Example

See [auto_detect_demo.R](auto_detect_demo.R) for a complete working example.

## Migration Path

Existing scripts continue to work without changes. To adopt auto-detection:

1. **Add script_filename to registrations**: Update `register_pipeline_tasks.R`
2. **Simplify script headers**: Replace manual stage/task/script_file with just `task_start()`
3. **Test**: Run scripts to verify auto-detection works

**Before:**
```r
script_file <- "03_ANNUAL_SEPT_03_Road_Lengths_Hex.R"
stage <- "ANNUAL_SEPT"
task_name <- "Road Lengths (Hexagons)"

task_start(stage = stage, task = task_name)
```

**After:**
```r
task_start()  # Auto-detects everything!
```
