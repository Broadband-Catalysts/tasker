# Tasker Auto-Detection Enhancement - Summary

## What Was Implemented

Added automatic script filename detection and database lookup to tasker, eliminating the need for manual stage/task specification in scripts.

## Changes Made

### 1. New Functions ([get_script_filename.R](R/get_script_filename.R))

- **`get_script_filename()`**: Detects the currently executing script filename using `this.path` package with fallbacks
- **`lookup_task_by_script()`**: Queries database to find stage/task associated with a script filename

### 2. Enhanced task_start() ([task_start.R](R/task_start.R))

- Made `stage` and `task` parameters optional (default: `NULL`)
- Auto-detects script filename when parameters not provided  
- Looks up stage/task from database using script_filename
- Provides clear error messages if auto-detection fails
- **Backward compatible**: Explicit parameters still work

### 3. Added Dependency ([DESCRIPTION](DESCRIPTION))

- Added `this.path` to Imports for robust script detection

### 4. Documentation & Examples

- [auto_detect_demo.R](inst/examples/auto_detect_demo.R): Working demonstration script
- [README_auto_detect.md](inst/examples/README_auto_detect.md): Complete usage guide
- Updated Copilot instructions in both tasker-dev and fccData

## Usage Examples

### New Way (Auto-Detection - Zero Configuration!)

```r
# Just call task_start() - everything else is automatic!
task_start()
subtask_start("Processing items", items_total = 100)
# ... do work ...
subtask_complete()
task_complete()
```

### Old Way (Explicit - Still Supported)

```r
script_file <- "03_ANNUAL_SEPT_03_Road_Lengths_Hex.R"
stage <- "ANNUAL_SEPT"  
task_name <- "Road Lengths (Hexagons)"
task_start(stage = stage, task = task_name)
# ... rest of script ...
```

## Requirements for Auto-Detection

1. **Register tasks with script_filename**:
```r
register_task(
  stage = "ANNUAL_SEPT",
  name = "Road Lengths",
  type = "R",
  script_filename = "03_ANNUAL_SEPT_03_Road_Lengths_Hex.R",
  # ... other parameters ...
)
```

2. **Run scripts via Rscript or R CMD BATCH** (not interactive sessions)

## Benefits

1. **Zero redundancy**: Stage/task defined once during registration, not in every script
2. **No typos**: Can't mismatch script file with wrong stage/task  
3. **Simpler scripts**: 3-5 lines of boilerplate replaced with 1 line
4. **Consistency**: All scripts use identical pattern
5. **Backward compatible**: Existing scripts continue working

## Migration Path

1. **Phase 1**: Add `script_filename` to all task registrations (update `register_pipeline_tasks.R`)
2. **Phase 2**: Test auto-detection with a few scripts  
3. **Phase 3**: Gradually migrate scripts as they're modified
4. **No breaking changes**: Old explicit method continues to work indefinitely

## Testing

Test the implementation:

```bash
cd /home/warnes/src/tasker-dev
Rscript inst/examples/auto_detect_demo.R
```

## Files Modified

**tasker-dev:**
- `R/get_script_filename.R` (new)
- `R/task_start.R` (enhanced)
- `DESCRIPTION` (added this.path dependency)
- `inst/examples/auto_detect_demo.R` (new demo)
- `inst/examples/README_auto_detect.md` (new documentation)
- `.github/copilot-instructions.md` (updated patterns)

**fccData:**
- `.github/copilot-instructions.md` (updated patterns)

## Next Steps

1. Install `this.path` package in environments:
   ```r
   install.packages("this.path")
   ```

2. Update `register_pipeline_tasks.R` in fccData to include `script_filename` for all tasks

3. Test with one or two scripts before wider adoption

4. Document in tasker README.md

## Notes

- Linter warnings about "unused variables" in SQL queries are false positives (variables ARE used in glue_sql)
- The `this.path` package handles all edge cases (Rscript, R CMD BATCH, source(), RStudio, etc.)
- Fallback detection methods ensure compatibility even if `this.path` unavailable
