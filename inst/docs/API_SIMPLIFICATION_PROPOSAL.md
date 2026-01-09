# Tasker API Simplification Proposal

**Date**: January 8, 2026  
**Status**: Proposal  
**Target Version**: tasker 2.0

## Executive Summary

This proposal outlines strategies to simplify the tasker package API by reducing the number of required function calls and parameters while maintaining full functionality. The primary focus is on reducing boilerplate code, improving the parallel processing experience, and making the package more intuitive for new users.

## Current API Pain Points

### 1. Repetitive `run_id` Parameter Passing

**Problem**: Every function requires passing `run_id`, creating verbose and error-prone code:

```r
run_id <- task_start("STATIC", "Process Data")
subtask_start(run_id, 1, "Load files", items_total = 100)
subtask_update(run_id, 1, "RUNNING", items_complete = 50)
subtask_complete(run_id, 1)
task_complete(run_id)
```

**Impact**: High - affects every tasker function call throughout scripts.

### 2. Complex Parallel Worker Setup

**Problem**: Setting up parallel workers requires multiple steps and careful handling of non-serializable objects:

```r
cl <- makeCluster(16)
clusterEvalQ(cl, { library(tasker); devtools::load_all(); NULL })
clusterExport(cl, c("run_id", "var1", "var2"), envir = environment())
clusterEvalQ(cl, { con <- dbConnectBBC(mode="rw"); NULL })
results <- parLapply(cl, items, worker_function)
stopCluster(cl)
```

**Impact**: High - parallel processing is a core use case, but setup is complex and error-prone.

### 3. Verbose Subtask Number Tracking

**Problem**: Users must manually track subtask numbers across a script:

```r
subtask_start(run_id, 1, "First step")
subtask_complete(run_id, 1)
subtask_start(run_id, 2, "Second step")  # Manual numbering
subtask_complete(run_id, 2)
subtask_start(run_id, 3, "Third step")   # Easy to lose count
subtask_complete(run_id, 3)
```

**Impact**: Medium - causes errors in long scripts with many subtasks.

### 4. Database Connection Management

**Problem**: Connection parameter `conn` is optional but requires manual management:

```r
# Sometimes users want to control connections:
conn <- get_db_connection()
task_start("STAGE", "Task", conn = conn)
subtask_start(run_id, 1, "Step", conn = conn)
subtask_complete(run_id, 1, conn = conn)
DBI::dbDisconnect(conn)
```

**Impact**: Medium - adds complexity without clear benefit in most cases.

### 5. Configuration Boilerplate

**Problem**: Every script needs configuration setup:

```r
library(tasker)
tasker_config()
setup_tasker_db()  # Or check if schema exists
```

**Impact**: Low-Medium - required in every script but relatively simple.

## Proposed Solutions

### Solution 1: Session-Based Run Context

**Priority**: ⭐⭐⭐ HIGH  
**User Impact**: 🚀 Very High - Reduces every function call  
**Implementation Complexity**: 🟢 Low-Medium

#### Design

Store the active `run_id` in a private package environment (not `options()` to avoid polluting user's global options):

```r
# Internal environment (not exported)
.tasker_env <- new.env(parent = emptyenv())

# New function to set active run
tasker_context <- function(run_id = NULL) {
  if (!is.null(run_id)) {
    .tasker_env$active_run_id <- run_id
    invisible(run_id)
  } else {
    .tasker_env$active_run_id
  }
}

# Helper to get run_id (used internally)
get_active_run_id <- function() {
  run_id <- .tasker_env$active_run_id
  if (is.null(run_id)) {
    stop("No active task run. Call task_start() first or use tasker_context(run_id).",
         call. = FALSE)
  }
  run_id
}
```

#### Modified API

Update all functions to make `run_id` optional, defaulting to the active context:

```r
# Before
task_start <- function(stage, task, ...) {
  run_id <- generate_run_id()
  # ... existing code ...
  return(run_id)
}

# After
task_start <- function(stage, task, ..., .active = TRUE) {
  run_id <- generate_run_id()
  # ... existing code ...
  if (.active) {
    tasker_context(run_id)  # Set as active
  }
  return(run_id)
}

# Before
subtask_start <- function(run_id, subtask_number, ...)

# After  
subtask_start <- function(run_id = tasker_context(), subtask_number, ...)
```

#### User Experience

```r
# NEW: Simplified workflow
library(tasker)

# Start task - automatically becomes active context
task_start("STATIC", "Process Data")

# No more run_id parameter needed!
subtask_start(1, "Load files", items_total = 100)
subtask_update(1, "RUNNING", items_complete = 50)
subtask_complete(1)

subtask_start(2, "Transform data")
subtask_complete(2)

task_complete()

# OLD: Still works for backwards compatibility
run_id <- task_start("STATIC", "Process Data", .active = FALSE)
subtask_start(run_id, 1, "Load files")
```

#### Backward Compatibility

- All existing code continues to work (explicit `run_id` parameter)
- New code can omit `run_id` (defaults to active context)
- Multiple concurrent runs supported via explicit `run_id`

#### Parallel Worker Considerations

Workers need the run context initialized:

```r
# Export active run_id to workers
run_id <- tasker_context()  # Get current run_id
clusterExport(cl, "run_id")

# Workers set their context
clusterEvalQ(cl, {
  library(tasker)
  tasker_context(run_id)  # Initialize worker context
})

# Now workers can use simplified API
worker_function <- function(item) {
  # No run_id parameter needed!
  subtask_increment(1, increment = 1)
}
```

---

### Solution 2: Simplified Parallel Processing Helper

**Priority**: ⭐⭐⭐ HIGH  
**User Impact**: 🚀 Very High - Dramatically simplifies common pattern  
**Implementation Complexity**: 🟡 Medium

#### Design

Create a high-level helper that encapsulates parallel worker setup:

```r
#' Initialize parallel cluster with tasker configuration
#'
#' @param ncores Number of cores (default: detectCores() - 2)
#' @param packages Character vector of packages to load
#' @param export Character vector of objects to export
#' @param setup_expr Expression to evaluate on each worker (e.g., database connections)
#' @param envir Environment to export from (default: parent.frame())
#' @return Cluster object
#' @export
tasker_cluster <- function(ncores = NULL, 
                           packages = NULL,
                           export = NULL,
                           setup_expr = NULL,
                           envir = parent.frame()) {
  
  if (is.null(ncores)) {
    ncores <- max(1, parallel::detectCores() - 2)
  }
  
  cl <- parallel::makeCluster(ncores)
  
  # Load tasker on all workers
  parallel::clusterEvalQ(cl, { library(tasker); NULL })
  
  # Load additional packages
  if (!is.null(packages)) {
    for (pkg in packages) {
      parallel::clusterCall(cl, library, package = pkg, character.only = TRUE)
    }
  }
  
  # Export active run context
  run_id <- tasker_context()
  if (!is.null(run_id)) {
    parallel::clusterExport(cl, "run_id", envir = environment())
    parallel::clusterEvalQ(cl, { tasker::tasker_context(run_id); NULL })
  }
  
  # Export additional objects
  if (!is.null(export)) {
    parallel::clusterExport(cl, export, envir = envir)
  }
  
  # Run setup expression
  if (!is.null(setup_expr)) {
    parallel::clusterEvalQ(cl, { eval(setup_expr); NULL })
  }
  
  # Store cluster info for cleanup
  attr(cl, "tasker_managed") <- TRUE
  
  return(cl)
}

#' Stop tasker cluster
#'
#' @param cl Cluster object
#' @export
stop_tasker_cluster <- function(cl) {
  if (!is.null(cl)) {
    parallel::stopCluster(cl)
  }
}
```

#### User Experience

```r
# BEFORE: Complex setup
cl <- makeCluster(16)
clusterEvalQ(cl, { library(tasker); devtools::load_all(); NULL })
clusterExport(cl, c("run_id", "var1", "var2"), envir = environment())
clusterEvalQ(cl, { con <- dbConnectBBC(mode="rw"); NULL })
results <- parLapply(cl, items, worker_function)
stopCluster(cl)

# AFTER: One-line setup
cl <- tasker_cluster(
  ncores = 16,
  export = c("var1", "var2"),
  setup_expr = quote({ devtools::load_all(); con <- dbConnectBBC(mode="rw") })
)
results <- parLapply(cl, items, worker_function)
stop_tasker_cluster(cl)

# Even simpler with defaults:
cl <- tasker_cluster()  # Auto-detect cores, export run_id
results <- parLapply(cl, items, worker_function)
stop_tasker_cluster(cl)
```

---

### Solution 3: Automatic Subtask Numbering

**Priority**: ⭐⭐ MEDIUM  
**User Impact**: 🔥 High - Reduces errors in multi-subtask workflows  
**Implementation Complexity**: 🟢 Low

#### Design

Track the current subtask number in the run context:

```r
# Store in environment
.tasker_env$subtask_counter <- list()

# Helper functions
get_next_subtask <- function(run_id = tasker_context()) {
  if (is.null(.tasker_env$subtask_counter[[run_id]])) {
    .tasker_env$subtask_counter[[run_id]] <- 0
  }
  .tasker_env$subtask_counter[[run_id]] <- .tasker_env$subtask_counter[[run_id]] + 1
  .tasker_env$subtask_counter[[run_id]]
}

# Modified functions
subtask_start <- function(run_id = tasker_context(), 
                         subtask_number = NULL,
                         subtask_name, ...) {
  if (is.null(subtask_number)) {
    subtask_number <- get_next_subtask(run_id)
  }
  # ... rest of implementation ...
}
```

#### User Experience

```r
# BEFORE: Manual numbering
subtask_start(run_id, 1, "Load data")
subtask_complete(run_id, 1)
subtask_start(run_id, 2, "Transform")
subtask_complete(run_id, 2)
subtask_start(run_id, 3, "Save")
subtask_complete(run_id, 3)

# AFTER: Auto-increment
subtask_start("Load data")      # Automatically subtask 1
subtask_complete()              # Uses last started subtask
subtask_start("Transform")      # Automatically subtask 2  
subtask_complete()
subtask_start("Save")           # Automatically subtask 3
subtask_complete()
```

#### Backward Compatibility

Explicit subtask numbers still work - auto-numbering is opt-in by omitting the parameter.

---

### Solution 4: Task Context Manager (with-style)

**Priority**: ⭐ LOW-MEDIUM  
**User Impact**: 🎯 Medium - Improves code organization  
**Implementation Complexity**: 🟡 Medium

#### Design

Implement a context manager pattern using R6 or base R closures:

```r
#' Create a task context manager
#'
#' @param stage Stage name
#' @param task Task name
#' @param ... Additional parameters for task_start()
#' @return TaskContext object
#' @export
with_task <- function(stage, task, ...) {
  run_id <- task_start(stage, task, ...)
  tasker_context(run_id)
  
  # Return object with methods
  context <- list(
    run_id = run_id,
    subtask = function(name, ..., expr) {
      subtask_start(name, ...)
      on.exit(subtask_complete())
      eval(expr, envir = parent.frame())
    },
    complete = function(message = NULL) {
      task_complete(message = message)
    }
  )
  
  class(context) <- "TaskContext"
  return(context)
}
```

#### User Experience

```r
# AFTER: Scoped context
ctx <- with_task("STATIC", "Process Data")

ctx$subtask("Load files", items_total = 100, expr = {
  # Subtask automatically starts and completes
  data <- load_files()
})

ctx$subtask("Transform", expr = {
  transformed <- transform_data(data)
})

ctx$complete("All done!")
```

---

### Solution 5: Smart Connection Pooling

**Priority**: ⭐ LOW  
**User Impact**: 📊 Low-Medium - Mostly internal optimization  
**Implementation Complexity**: 🔴 High

#### Design

Implement connection pooling internally so users never need to pass `conn`:

```r
# Internal connection pool
.tasker_env$conn_pool <- NULL

get_pooled_connection <- function() {
  if (is.null(.tasker_env$conn_pool)) {
    .tasker_env$conn_pool <- pool::dbPool(
      drv = get_db_driver(),
      host = config$database$host,
      # ... other params ...
    )
  }
  return(.tasker_env$conn_pool)
}

# All functions use pooled connections
task_start <- function(stage, task, ...) {
  conn <- get_pooled_connection()
  # No longer accept conn parameter
  # ...
}
```

#### User Experience

```r
# BEFORE: Optional connection management
conn <- get_db_connection()
task_start("STAGE", "Task", conn = conn)
# ...
dbDisconnect(conn)

# AFTER: Automatic connection management
task_start("STAGE", "Task")
# Connections handled internally
```

---

### Solution 6: Configuration Auto-Detection and Caching

**Priority**: ⭐ LOW  
**User Impact**: 📊 Low - Mostly convenience  
**Implementation Complexity**: 🟢 Low

#### Design

Auto-detect and cache configuration on first use:

```r
# Modify ensure_configured() to be more automatic
ensure_configured <- function() {
  if (is.null(getOption("tasker.config"))) {
    # Try to auto-configure
    tryCatch({
      tasker_config()  # Auto-discover
      message("Tasker configuration auto-loaded")
    }, error = function(e) {
      stop("Tasker not configured. Run tasker_config() or create .tasker.yml",
           call. = FALSE)
    })
  }
}
```

#### User Experience

```r
# BEFORE: Explicit configuration
library(tasker)
tasker_config()
run_id <- task_start(...)

# AFTER: Auto-configuration
library(tasker)
run_id <- task_start(...)  # Auto-configures on first use
```

---

### Solution 7: Fluent/Chainable API

**Priority**: ⭐ LOW  
**User Impact**: 🎯 Low - Alternative style  
**Implementation Complexity**: 🟡 Medium

#### Design

Support method chaining for fluent API style:

```r
tasker() %>%
  start_task("STATIC", "Process Data") %>%
  add_subtask("Load files", items_total = 100) %>%
  update_subtask(items_complete = 50) %>%
  complete_subtask() %>%
  add_subtask("Transform") %>%
  complete_subtask() %>%
  complete_task()
```

**Note**: This is a stylistic preference and adds complexity. Lower priority unless there's strong user demand.

---

## Priority Ranking

| Rank | Solution | User Impact | Complexity | ROI | Recommended |
|------|----------|-------------|------------|-----|-------------|
| 1 | Session-Based Run Context | ⭐⭐⭐ Very High | 🟢 Low-Med | ⭐⭐⭐ | ✅ YES |
| 2 | Parallel Processing Helper | ⭐⭐⭐ Very High | 🟡 Medium | ⭐⭐⭐ | ✅ YES |
| 3 | Auto Subtask Numbering | ⭐⭐ High | 🟢 Low | ⭐⭐⭐ | ✅ YES |
| 4 | Task Context Manager | ⭐ Medium | 🟡 Medium | ⭐ | 🤔 MAYBE |
| 5 | Smart Connection Pooling | ⭐ Low-Med | 🔴 High | ⭐ | ⏸️ DEFER |
| 6 | Auto-Configuration | ⭐ Low | 🟢 Low | ⭐⭐ | ✅ YES |
| 7 | Fluent/Chainable API | ⭐ Low | 🟡 Medium | ⭐ | ❌ NO |

## Recommended Implementation Phases

### Phase 1: Core Simplifications (High ROI, Low Risk)
**Target: tasker 2.0**

1. **Session-Based Run Context** (Solution 1)
   - Add `.tasker_env` internal environment
   - Add `tasker_context()` function
   - Make `run_id` optional in all functions (default to context)
   - Full backward compatibility

2. **Auto-Configuration** (Solution 6)
   - Enhance `ensure_configured()` to auto-detect config
   - Reduce boilerplate in scripts

3. **Auto Subtask Numbering** (Solution 3)
   - Track current subtask in run context
   - Make `subtask_number` optional
   - Support explicit numbers for backward compatibility

**Impact**: Reduces 50-70% of boilerplate code in typical scripts.

### Phase 2: Parallel Processing Improvements (High User Demand)
**Target: tasker 2.1**

4. **Parallel Processing Helper** (Solution 2)
   - Add `tasker_cluster()` function
   - Add `stop_tasker_cluster()` function
   - Integrate with run context for automatic worker setup
   - Document best practices

**Impact**: Simplifies parallel processing setup from 8-10 lines to 1-2 lines.

### Phase 3: Advanced Features (If Demand Exists)
**Target: tasker 2.2+**

5. **Task Context Manager** (Solution 4) - If user feedback is positive
6. **Connection Pooling** (Solution 5) - If performance issues emerge

## Migration Strategy

### Backward Compatibility Guarantees

1. **All existing code continues to work** - No breaking changes to function signatures
2. **Explicit parameters take precedence** - If user passes `run_id`, use it (ignore context)
3. **Clear error messages** - If context needed but not set, provide helpful error
4. **Documentation** - Show both old and new patterns side-by-side

### Example Migration

```r
# OLD CODE (still works in 2.0)
library(tasker)
tasker_config()

run_id <- task_start("STATIC", "Process")
subtask_start(run_id, 1, "Load")
subtask_complete(run_id, 1)
task_complete(run_id)

# NEW CODE (simplified in 2.0)
library(tasker)

task_start("STATIC", "Process")  # Auto-configures, sets context
subtask_start("Load")             # Auto-numbered, uses context
subtask_complete()                # Uses context
task_complete()                   # Uses context

# HYBRID (mix old and new)
run_id <- task_start("STATIC", "Process")  # Get run_id explicitly
subtask_start("Load")                      # But use context for calls
```

### Deprecation Timeline

**No functions will be deprecated.** All current APIs remain supported. We're adding convenience, not removing functionality.

### Documentation Updates

1. Update README with simplified examples (but show both styles)
2. Add "API 2.0 Migration Guide" vignette
3. Update all function documentation with new optional parameters
4. Add "Best Practices for Parallel Processing" guide using new helpers
5. Create "Comparison: Old vs New API" document

## Testing Strategy

### Unit Tests

- Test all functions with context-based calls
- Test all functions with explicit `run_id` (existing tests)
- Test context isolation between runs
- Test worker context initialization
- Test edge cases (no context set, wrong context)

### Integration Tests

- Full pipeline using new API
- Parallel processing with `tasker_cluster()`
- Mixed old/new API usage
- Multiple concurrent runs

### Performance Tests

- Compare connection pooling vs manual connections
- Benchmark context lookup overhead
- Measure parallel setup time reduction

## Documentation Requirements

### New Documentation

1. **`vignettes/api-2.0-guide.Rmd`** - Complete guide to simplified API
2. **`inst/docs/PARALLEL_PROCESSING_GUIDE.md`** - Enhanced parallel guide
3. **`inst/docs/MIGRATION_GUIDE.md`** - Old to new API migration
4. **`inst/docs/API_SIMPLIFICATION_PROPOSAL.md`** - This document

### Updated Documentation

1. All function `.Rd` files - Add new optional parameters and examples
2. `README.md` - Show simplified API as primary examples
3. `inst/examples/example_pipeline.R` - Add new-style version
4. GitHub Copilot instructions - Document new patterns

## Success Metrics

After implementing Phase 1, measure:

1. **Lines of Code Reduction**: Target 50-70% reduction in boilerplate
2. **New User Onboarding**: Time to first successful task tracking
3. **Error Rate**: Reduction in common mistakes (wrong run_id, etc.)
4. **Community Feedback**: Survey users on API usability

After implementing Phase 2, measure:

5. **Parallel Setup Complexity**: Reduction from ~10 lines to ~2 lines
6. **Parallel Setup Errors**: Fewer serialization and export errors
7. **Time to Parallel**: Faster development of parallel workflows

## Risks and Mitigations

### Risk 1: Context Confusion with Nested Tasks

**Problem**: If a function internally starts a task, it might override the user's context.

**Mitigation**: 
- Document that library functions should use explicit `run_id`
- Add `.active = FALSE` parameter to `task_start()` for library use
- Provide `tasker_save_context()` / `tasker_restore_context()` for advanced users

### Risk 2: Parallel Worker Context Issues

**Problem**: Workers might have stale or wrong context.

**Mitigation**:
- `tasker_cluster()` automatically initializes worker context
- Document pattern: "Always use `tasker_cluster()` or manually initialize context"
- Add diagnostic function: `tasker_check_context()` for debugging

### Risk 3: Increased Implicit Behavior

**Problem**: Magic behavior can confuse users debugging issues.

**Mitigation**:
- Clear error messages when context is missing
- Verbose logging option: `options(tasker.verbose = TRUE)`
- Debug helpers: `tasker_context()` returns current context for inspection

### Risk 4: Backward Compatibility Complexity

**Problem**: Supporting both APIs might complicate code.

**Mitigation**:
- Clean abstraction: functions first check explicit params, then fall back to context
- Comprehensive test suite covering both styles
- Internal helper: `resolve_run_id(explicit, context)` used everywhere

## Open Questions

1. **Should `subtask_complete()` auto-detect the last started subtask?**
   - Pro: Even simpler API
   - Con: More implicit magic, could be confusing

2. **Should parallel helpers support other backends (future, etc)?**
   - Pro: More flexible
   - Con: Added complexity, less focus

3. **Should we provide a `tasker_reset_context()` function?**
   - Pro: Useful for interactive development
   - Con: Encourages messy context management

4. **Should configuration be cached globally or per-session?**
   - Current: Per R session (in `options()`)
   - Alternative: Global cache file for faster startup

## Appendix A: Complete Example Comparison

### Before (Current API)

```r
#!/usr/bin/env Rscript
library(tasker)
library(parallel)

# Configuration
tasker_config()

# Register tasks
register_task("PROCESS", "County Analysis", "R")

# Start task
run_id <- task_start("PROCESS", "County Analysis", total_subtasks = 2)

# Subtask 1: Load data
subtask_start(run_id, 1, "Load county list", items_total = 3143)
counties <- get_county_list()
subtask_complete(run_id, 1)

# Subtask 2: Process counties in parallel
subtask_start(run_id, 2, "Process counties", items_total = length(counties))

# Set up parallel cluster
cl <- makeCluster(16)
clusterEvalQ(cl, { library(tasker); devtools::load_all(); NULL })
clusterExport(cl, c("run_id", "counties"), envir = environment())
clusterEvalQ(cl, { con <- dbConnectBBC(mode="rw"); NULL })

# Worker function
process_county <- function(county_fips) {
  tryCatch({
    result <- analyze_county(county_fips)
    subtask_increment(run_id, 2, increment = 1, quiet = TRUE)
    return("success")
  }, error = function(e) {
    return(as.character(e))
  })
}

# Process in parallel
results <- parLapplyLB(cl, counties, process_county)
stopCluster(cl)

# Complete
subtask_complete(run_id, 2)
task_complete(run_id, "Analysis complete")
```

**Line count**: 38 lines  
**Boilerplate**: ~18 lines (47%)

### After (Simplified API)

```r
#!/usr/bin/env Rscript
library(tasker)

# Register tasks
register_task("PROCESS", "County Analysis", "R")

# Start task (auto-configures, sets context)
task_start("PROCESS", "County Analysis")

# Subtask 1: Load data (auto-numbered)
subtask_start("Load county list", items_total = 3143)
counties <- get_county_list()
subtask_complete()

# Subtask 2: Process counties in parallel (auto-numbered)
subtask_start("Process counties", items_total = length(counties))

# Set up parallel cluster (one line!)
cl <- tasker_cluster(
  ncores = 16,
  export = "counties",
  setup_expr = quote({ devtools::load_all(); con <- dbConnectBBC(mode="rw") })
)

# Worker function (uses context, no run_id needed)
process_county <- function(county_fips) {
  tryCatch({
    result <- analyze_county(county_fips)
    subtask_increment(increment = 1, quiet = TRUE)
    return("success")
  }, error = function(e) {
    return(as.character(e))
  })
}

# Process in parallel
results <- parLapplyLB(cl, counties, process_county)
stop_tasker_cluster(cl)

# Complete (uses context)
subtask_complete()
task_complete("Analysis complete")
```

**Line count**: 32 lines  
**Boilerplate**: ~5 lines (16%)

**Reduction**: 6 lines total (16%), 13 boilerplate lines removed (72% boilerplate reduction)

## Appendix B: API Function Changes Summary

| Function | Current Signature | New Signature | Change |
|----------|------------------|---------------|---------|
| `task_start()` | `(stage, task, ...)` | `(stage, task, ..., .active=TRUE)` | Returns run_id, optionally sets context |
| `task_update()` | `(run_id, ...)` | `(run_id=tasker_context(), ...)` | run_id optional |
| `task_complete()` | `(run_id, ...)` | `(run_id=tasker_context(), ...)` | run_id optional |
| `subtask_start()` | `(run_id, subtask_number, ...)` | `(run_id=tasker_context(), subtask_number=NULL, ...)` | Both optional |
| `subtask_update()` | `(run_id, subtask_number, ...)` | `(run_id=tasker_context(), subtask_number=NULL, ...)` | Both optional |
| `subtask_complete()` | `(run_id, subtask_number, ...)` | `(run_id=tasker_context(), subtask_number=NULL, ...)` | Both optional |
| `subtask_increment()` | `(run_id, subtask_number, ...)` | `(run_id=tasker_context(), subtask_number=NULL, ...)` | Both optional |
| `tasker_context()` | N/A | `(run_id=NULL)` | **NEW** - Get/set context |
| `tasker_cluster()` | N/A | `(ncores=NULL, packages=NULL, export=NULL, setup_expr=NULL, envir=parent.frame())` | **NEW** - Parallel helper |
| `stop_tasker_cluster()` | N/A | `(cl)` | **NEW** - Cleanup helper |

## Conclusion

The proposed API simplifications will dramatically improve the user experience of the tasker package while maintaining full backward compatibility. By implementing these changes in phases, we can deliver immediate value (Phase 1) while gathering feedback for more advanced features (Phases 2-3).

**Recommended Next Steps**:

1. ✅ Review and approve this proposal
2. 📝 Create GitHub issues for Phase 1 implementations
3. 🔬 Prototype Session-Based Run Context in branch
4. 📊 Gather user feedback on prototypes
5. 🚀 Implement Phase 1 for tasker 2.0 release
6. 📚 Update all documentation and examples
7. 🎉 Announce and promote simplified API

**Questions or Feedback**: Please discuss in the tasker repository or reach out to the development team.
