# tasker 0.6.0 (2026-01-14)

## Major Features

* **Automatic Script Detection**: `task_start()` can now automatically detect the executing script filename and look up the stage and task name from the database, eliminating the need to manually specify these parameters.

* **Optional Parameters**: `stage` and `task` parameters in `task_start()` are now optional (default: `NULL`). When omitted, the function attempts to:
  1. Detect the executing script filename using the `this.path` package
  2. Query the database for matching task registration
  3. Automatically populate stage and task names

* **Backward Compatibility**: Explicit `stage` and `task` parameters are still fully supported. Existing code continues to work without modification.

## New Functions

* `get_script_filename()`: Detects the currently executing R script filename using multiple detection methods (this.path, commandArgs, sys.frames)

* `lookup_task_by_script()`: Queries the database to find stage and task names based on script filename

## Infrastructure

* Added `this.path` package dependency for robust cross-platform script detection
* Added comprehensive unit tests (32 tests) covering auto-detection functionality
* Updated documentation with new usage patterns and examples

## Breaking Changes

None. All changes are backward compatible.

## Bug Fixes

* Fixed NA handling in `get_script_filename()` when `getSrcFilename()` returns NA
* Fixed SQLite UUID format to match PostgreSQL expectations (8-4-4-4-12 format)

---

# tasker 0.5.0

Previous version. See git history for details.
