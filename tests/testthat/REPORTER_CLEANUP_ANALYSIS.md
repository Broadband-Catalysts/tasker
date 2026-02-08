# Reporter Process Cleanup - Root Cause Analysis

**Date:** 2026-02-05  
**Issue:** Test suite exhausting database connections  
**Severity:** Critical - blocks test execution

## Problem Summary

The tasker test suite was creating numerous orphaned reporter processes that maintained database connections indefinitely, eventually exhausting the PostgreSQL connection pool and causing "too many clients already" errors.

## Root Cause

### 1. **Reporter Process Lifecycle**

Reporter processes are spawned using `callr::r_bg()` as background R processes. By default, they run with `supervise = FALSE`, meaning they **persist independently** after the parent test process exits.

### 2. **Inadequate Cleanup in Tests**

Tests in `test-process-reporter.R` that call `start_reporter()` include `on.exit()` handlers to stop reporters:

```r
on.exit({
  tryCatch(stop_reporter(hostname, timeout = 10, con = con), error = function(e) NULL)
  cleanup_test_db()
}, add = TRUE)
```

**However**, when tests fail or are interrupted, these handlers may not execute reliably, especially:
- When hitting `Maximum number of failures exceeded` (testthat aborts)
- When database connection errors prevent `stop_reporter()` from working
- When the test database is cleaned up before reporters are stopped

### 3. **Database Connection Exhaustion Cascade**

Once several reporters are orphaned:

1. Each reporter maintains 1+ database connections
2. Subsequent tests trying to connect hit connection limits
3. Connection failures prevent cleanup functions from working
4. More reporters are orphaned, creating a vicious cycle
5. Eventually all connections are exhausted: "FATAL: sorry, too many clients already"

### 4. **Specific Test Patterns Contributing**

Tests like `"start_reporter respects force parameter"` and `"start_reporter supervise parameter is passed to callr::r_bg"` spawn multiple reporter processes in sequence:

```r
# Start first reporter
start_reporter(hostname = hostname, force = TRUE, ...) 
Sys.sleep(2)  # Wait for startup

# Start with force=FALSE (keeps first alive)
start_reporter(hostname = hostname, force = FALSE, ...)

# Start with force=TRUE (spawns new reporter)
start_reporter(hostname = hostname, force = TRUE, ...)
```

Each `force=TRUE` call spawns a **new** reporter process. If cleanup fails, **all** of these remain running.

## Impact

- **First test run:** 5-10 orphaned reporters
- **Second test run:** Another 5-10 reporters (cleanup already failing)
- **Third test run:** Connection pool exhausted, tests cannot run
- **Database impact:** 20-30 active connections from orphaned reporters
- **Required intervention:** Manual `pkill -f process_reporter` or database restart

## Solution

### 1. **Cleanup Utility Function** (`cleanup_test_reporters()`)

Created comprehensive cleanup function that:
- Finds all child R processes of the test runner
- Identifies reporter processes by command-line pattern matching
- Attempts graceful shutdown via database
- Force-kills processes that don't stop gracefully
- Reports cleanup statistics

Located in: `tests/testthat/helper-test.R`

### 2. **Teardown Hook**

Created `tests/testthat/teardown-reporters.R` that runs **after all test files complete**:
- Catches any reporters that escaped individual test cleanup
- Runs even when tests fail
- Provides visibility into cleanup status

### 3. **Per-File Cleanup**

Added cleanup call at end of `test-process-reporter.R`:
- Runs after all tests in the file
- Provides immediate feedback if reporters are leaking
- Prevents accumulation across test files

### 4. **Usage Pattern for Future Tests**

Tests that spawn reporters should use:

```r
test_that("test with reporter", {
  # Setup
  db_path <- setup_test_db()
  con <- get_test_db_connection()
  hostname <- "test-hostname"
  test_config <- create_test_config_file()
  
  # Cleanup - ALWAYS use both methods
  on.exit({
    # Method 1: Stop specific reporter
    tryCatch(stop_reporter(hostname, timeout = 5, con = con), error = function(e) NULL)
    
    # Method 2: Catch any orphans
    cleanup_test_reporters(quiet = TRUE)
    
    # Method 3: Clean up test resources
    if (file.exists(test_config)) unlink(test_config)
    tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    cleanup_test_db()
  }, add = TRUE)
  
  # Test code that spawns reporters...
})
```

## Prevention

To prevent future occurrences:

1. **Code review checklist:** Any test using `start_reporter()` must include `cleanup_test_reporters()`
2. **Documentation:** Added comprehensive docs to `cleanup_test_reporters()` function
3. **Teardown safety net:** Teardown file catches anything individual tests miss
4. **Monitoring:** Cleanup functions report statistics to detect leaks early

## Verification

After implementing these changes:

1. Run full test suite: `devtools::test()`
2. Check teardown output for orphaned reporters
3. Verify no R processes with "reporter" in command line: `ps aux | grep -i reporter | grep -v grep`
4. Monitor database connections: Check that count returns to baseline after tests

## Related Files

- `tests/testthat/helper-test.R` - Cleanup utility function
- `tests/testthat/teardown-reporters.R` - Post-test cleanup hook
- `tests/testthat/test-process-reporter.R` - Primary source of reporter tests
- `R/start_reporter.R` - Reporter spawning logic
- `R/stop_reporter.R` - Graceful shutdown logic

## Lessons Learned

1. **Background processes require explicit lifecycle management** - Don't rely solely on `on.exit()`
2. **Test failures can create cascading resource leaks** - Need cleanup that works even when things are broken
3. **Database-dependent cleanup is fragile** - Always have fallback force-kill option
4. **Process monitoring is essential** - Can't fix what you can't measure
5. **Defense in depth:** Multiple cleanup layers (per-test, per-file, teardown) catch different failure modes
