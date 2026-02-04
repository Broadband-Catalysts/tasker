# GitHub Copilot Instructions for tasker-dev

# 🛑🛑🛑 STOP - MANDATORY PRE-FLIGHT - READ THIS BEFORE RESPONDING 🛑🛑🛑

☐ State which user and project copilot-instructions.md sections apply to this request
☐ Check if any Agent Skills apply (list them explicitly)
☐ If multi-step work: Create todo list with #manage_todo_list
☐ Mark tasks in-progress and completed as you work
☐ Use #code-review before finalizing ANY code changes
☐ Use "we" collaborative language and refer to user as "Dr. Greg"
☐ Monitor and report token usage at checkpoints (700K/850K/950K)

**If you cannot check ALL boxes above, STOP and ask for clarification.**

**Example Response Format:**
```
**Following copilot-instructions.md sections: Shiny Patterns, Database Patterns**
**Applicable Agent Skills: #code-review, #git-commit-message**
**Will use #manage_todo_list for multi-step tracking**

Dr. Greg, we need to...
```

---

**Last Updated:** 2026-02-04 15:30 EST

# 📖 REQUIRED READING

**ALWAYS read the user-level copilot-instructions.md file first:**
- **Location**: `/home/warnes/src/vscode-config/copilot-instructions.md`
- **Contains**: Communication style, token monitoring, cross-project development patterns
- **Why**: Establishes baseline behavior and standards across all projects

**This file (project-specific) provides:**
- Shiny application patterns and anti-patterns
- Database connection handling in parallel workers
- Unit testing requirements and code review standards
- Agent Skills specific to tasker-dev workflows

---

## Quick Skill Reference

- **#code-review** - REQUIRED before finalizing any code changes
- **#git-commit-message** - For commit message generation  
- **#user-markdown-formatting** - For markdown documentation formatting standards
- **#shiny-ui-patterns** - For Shiny UI updates without flickering
- **#database-patterns** - For database connection and query patterns
- **#r-script-execution** - For running scripts and managing packages
- **#unit-testing** - For creating and maintaining test coverage
- **#manage_todo_list** - For multi-step task tracking and planning

## 🔀 Development Workflow

**CRITICAL: tasker-dev vs tasker repositories**

- **tasker-dev** (`/home/warnes/src/tasker-dev`, devel branch): Development repository
  - **ALL code changes go here first**
  - Test and iterate in this repository
  - Both Shiny app and package code

- **tasker** (`/home/warnes/src/tasker`, main branch): Production repository  
  - **NEVER make direct code changes here**
  - Only receives changes via pull requests from devel → main
  - Used for ShinyProxy deployment only


**Complete Workflow:**
1. **Develop** in `tasker-dev` (devel branch):
   - Make all code changes here
   - Create/update unit tests
   - Ensure all tests pass
   - Commit changes to devel branch
2. **Test thoroughly** before merging:
   - All unit tests must pass
   - Integration tests with dependent projects (fccData, etc.)
   - Verify Shiny app functionality
3. **Create PR** from devel → main when ready for production
4. **Review and merge** the pull request
5. **Deploy to production**:
   - `cd ~/src/tasker && git pull` to update production repository
   - Restart ShinyProxy or dependent services as needed

**Why:** Prevents accidental production changes, enables proper review process, maintains clean deployment history, ensures all changes are tested before production deployment.

## ⚠️ CRITICAL WORKFLOW CHECKLIST

**Before implementing ANY code changes, verify you will:**

1. ✅ **Create/update unit tests** - Code changes and tests must be implemented together
2. ✅ **Follow anti-patterns** - Check relevant sections below before coding
3. ✅ **Review changes** - Use systematic code review before finalizing
4. ✅ **Update documentation** - Regenerate docs if modifying exported functions

**After making changes, verify you have:**

1. ✅ **Tests passing** - All new/modified code has passing tests
2. ✅ **Documentation updated** - roxygen2 comments and .Rd files current
3. ✅ **No anti-patterns** - Reviewed against project-specific warnings
4. ✅ **User informed** - Confirmed completion to user

## Shiny Application Development

**See #shiny-ui-patterns skill for complete guidance.**

**CRITICAL REFERENCE:** Reactive dependency diagram at `inst/docs/reactive-dependencies.md` - **MUST UPDATE** when modifying reactive code in `inst/shiny/server.R`.

### CRITICAL Anti-Pattern: Never Use renderUI() for Content Updates

**Causes:** UI flickering, lost scroll position, memory overhead, poor performance.

**✅ CORRECT:** Static structure + reactive content
```r
# UI - Created once
ui <- fluidPage(
  div(class = "log-terminal", htmlOutput("log_content"))
)

# Server - Only content updates
server <- function(input, output, session) {
  output$log_content <- renderUI({
    rv$trigger  # Reactive dependency
    HTML(read_and_format_log())
  })
}
```

**❌ INCORRECT:** renderUI() recreates entire structure on every update.

**For details:** See #shiny-ui-patterns skill for update patterns, updateXXX() functions, shinyjs, reactive triggers.

## Parallel Processing with Database Connections

### Critical: clusterEvalQ Connection Serialization

**See #r-anti-patterns skill for complete guidance** on avoiding connection serialization errors in parallel processing.

**Quick reference:** When using `clusterEvalQ()` with database connections, ensure the expression returns `NULL` or another serializable value, not the connection object itself.

**Preferred Pattern:** Use `tasker_cluster()` with `setup_expr` parameter for automatic handling.

### Atomic Operations for Parallel Workers

Use `subtask_increment()` for atomic counter updates from parallel workers:

```r
# ✅ CORRECT - Atomic increment (safe for parallel execution)
process_item <- function(item) {
  # ... do work ...
  subtask_increment(run_id, subtask_number, increment = 1)
}

# ❌ INCORRECT - Race condition (parallel workers overwrite each other)
process_item <- function(item) {
  # ... do work ...
  current <- get_count()  # Worker A reads 10
  subtask_update(run_id, subtask_number, items_complete = current + 1)  # Workers overwrite
}
```

## Task Registration Patterns

### CRITICAL: Auto-Detected Paths Are Normalized to Absolute

**Problem:** When scripts self-register using `register_task()` without explicit paths, the function auto-detects the script location. Previously, these paths could be stored as relative paths (e.g., `"inst/oneoff"`), causing the Shiny app to fail finding log files because it runs in a different working directory.

**Solution:** As of tasker v0.9.0, `register_task()` applies `normalizePath()` to all auto-detected paths, ensuring they are stored as absolute paths in the database.

```r
# ✅ CORRECT - Auto-detection now normalizes to absolute
register_task(
  stage = "ONEOFF",
  name = "My Migration Task",
  stage_order = 1
  # script_path and log_path auto-detected and normalized to:
  # "/home/warnes/src/fccData/inst/oneoff" (absolute)
)

# ✅ ALSO CORRECT - Explicit relative paths still work (backward compatibility)
register_task(
  stage = "DAILY",
  name = "Daily Task",
  stage_order = 1,
  script_path = "inst/scripts",  # Relative path preserved if explicitly provided
  script_filename = "task.R"
)
```

**Why:** The Shiny monitoring app runs in the tasker-dev project context, not the project where scripts execute. Relative paths like `"inst/oneoff"` cannot be resolved because the Shiny app doesn't know which project root they're relative to. Absolute paths work universally.

**Implementation Details:**
- `normalizePath()` is applied in lines 99 and 108 of `R/register_task.R`
- Only affects **auto-detected** paths (from `--file=` or `this.path::this.path()`)
- **Explicit** paths provided by user are preserved as-is for backward compatibility
- Tested in `tests/testthat/test-register_task_absolute_paths.R`

## Database Patterns

**See #database-patterns skill for complete guidance.**

### Critical Anti-Patterns

**COUNT() casting:**
```r
# ✅ CORRECT
dbGetQuery(con, "SELECT COUNT(*)::INTEGER as n FROM table")

# ❌ INCORRECT - Returns bigint
dbGetQuery(con, "SELECT COUNT(*) as n FROM table")
```

**Connection management:**
- `dbConnectBBC(mode="rw")` - Read-write
- `dbConnectBBC(mode="r")` - Read-only (note: 'r', not 'ro')
- Use read-write for monitoring/status updates

**Database-agnostic SQL patterns:**

Remember: tasker must support PostgreSQL, SQLite, and MySQL/MariaDB.

Either use database-agnostic SQL syntax or handle each database's dialect appropriately:

```r
# ✅ CORRECT - Database-agnostic case-insensitive matching
WHERE UPPER(column_name) LIKE UPPER('%pattern%')

# ✅ ALSO CORRECT - Dialect-specific with fallback
if (driver == "postgresql") {
  WHERE column_name ILIKE '%pattern%'
} else {
  WHERE UPPER(column_name) LIKE UPPER('%pattern%')
}

# ❌ INCORRECT - PostgreSQL-only without handling other databases
WHERE column_name ILIKE '%pattern%'
```

**For complete database patterns:** See #database-patterns skill for detailed examples, query patterns, schema operations.

**Why:** `ILIKE` is PostgreSQL-specific and will fail on SQLite/MySQL with "syntax error". Use `UPPER(column) LIKE UPPER(pattern)` for case-insensitive matching across all supported databases.

**For details:** See #database-patterns skill.

## Error Handling Patterns

### Parallel Processing Error Handling

```r
flag <- try({
  # ... processing code ...
  "success"
})
return(flag)  # Returns either "success" or error object
```

### Retry Loop Pattern

Scripts support automatic retry for failed items:
- Test item processed first for validation
- Up to 5 retry attempts for failed items
- Failure tracking with detailed error messages

## Running R Scripts

**See #r-script-execution skill for complete guidance.**

### Critical Patterns

**Always run from project root:**
```bash
cd /home/warnes/src/tasker-dev && Rscript inst/scripts/my_script.R
```

**Shell quoting:**
```bash
Rscript -e 'cat("Use single quotes!\n")'  # ✅ Correct
```

**Use argparse for arguments:**
```r
library(argparse)
parser <- ArgumentParser(description = "...")
parser$add_argument("--input", type = "character", required = TRUE)
args <- parser$parse_args()
```

**Use tee for test/script output monitoring:**
```bash
# ✅ CORRECT - Allows user monitoring + agent analysis
Rscript -e 'devtools::load_all(); test_file("tests/testthat/test-file.R")' |& tee /tmp/output.log
grep "FAIL" /tmp/output.log

# ❌ INCORRECT - User can't monitor progress
Rscript -e 'test_file("tests/testthat/test-file.R")' 2>&1 | grep "FAIL"
```

**Why:** Piping directly to grep/head/tail prevents user from observing unanticipated errors or issues during execution. Using tee allows simultaneous user monitoring and agent analysis of specific output.

**For details:** See #r-script-execution skill.

## Code Review Practices

For systematic code review before finalizing changes, use the **#code-review** skill. It provides comprehensive guidance for:
- **R syntax validation** - Parse files to catch syntax errors before review
- **Indentation enforcement** - Verify standard block structure with commented braces
- Identifying errors, omissions, and anti-patterns
- Checking design issues and performance problems
- Following a systematic file-by-file review process
- Reporting findings to users with specific issue details

**Critical requirement:** Always review all modified files before finalizing changes and inform the user that you have done so, including any issues found or confirmation that no issues were detected.

**See #code-review skill for complete validation steps including R syntax parsing and indentation standards.**

### Review Modified Files

**After validation, review all modified files for errors, omissions, anti-patterns, or other issues:**

- **Errors**: Syntax errors, logic bugs, incorrect function calls, type mismatches
- **Omissions**: Missing error handling, incomplete implementations, forgotten edge cases
- **Anti-patterns**: 
  - `renderUI()` for dynamic content updates
  - Non-atomic updates in parallel code
  - Inefficient queries, missing indexes
  - Hardcoded values, race conditions
- **Design Issues**: Unhandled concurrency, missing constraints, poor naming, lack of documentation
- **Performance Issues**: Unbounded queries, N+1 queries, unnecessary data copies, inefficient loops

Use systematic review process:
1. **Parse all R files** for syntax errors
2. **Check indentation** (2 spaces) and block comments
3. Check each modified file for completeness
4. Verify error handling is present
5. Look for potential race conditions or concurrency issues
6. Ensure database constraints are appropriate
7. Validate function signatures match their usage
8. Confirm documentation matches implementation

## Documentation Standards

### Function Documentation

All exported functions must have roxygen2 documentation:

```r
#' Update subtask progress atomically
#'
#' Performs database-level atomic increment of items_complete counter.
#' Safe for concurrent use by multiple parallel workers.
#'
#' @param run_id Run ID from task_start()
#' @param subtask_number Subtask number (1-based)
#' @param increment Number of items to add (default: 1)
#' @param quiet Suppress messages (default: TRUE)
#' @param conn Database connection (optional)
#'
#' @return TRUE on success
#' @export
#'
#' @examples
#' run_id <- task_start("STAGE", "Task Name")
#' subtask_start(run_id, 1, "Process items", items_total = 100)
#' 
#' # Safe for parallel workers
#' parLapply(cl, items, function(item) {
#'   process_item(item)
#'   subtask_increment(run_id, 1, increment = 1)
#' })
subtask_increment <- function(run_id, subtask_number, increment = 1, quiet = TRUE, conn = NULL) {
  # Implementation
}
```

## Unit Tests

**Always create or update unit tests when creating or modifying functions:**

- **New functions**: Create test file in `tests/testthat/test-{function_name}.R`
- **Modified functions**: Update existing tests to cover new behavior
- **Bug fixes**: Add test case that reproduces the bug before fixing

**Test structure using testthat:**
```r
# tests/testthat/test-my_function.R
test_that("my_function validates input", {
  expect_error(my_function(NULL), "input.*required")
  expect_error(my_function("invalid"), "must be numeric")
})

test_that("my_function handles edge cases", {
  expect_equal(my_function(0), expected_result)
  expect_equal(my_function(c()), numeric(0))
})

test_that("my_function produces correct output", {
  result <- my_function(valid_input)
  expect_true(is.numeric(result))
  expect_equal(length(result), expected_length)
  expect_equal(result, expected_value)
})
```

**What to test:**
- **Input validation**: Invalid/missing parameters, type checking, boundary conditions
- **Edge cases**: Empty inputs, NULL values, single element vectors, large datasets
- **Core functionality**: Expected outputs for typical inputs
- **Error handling**: Proper error messages and graceful failures
- **Side effects**: Database operations, file I/O (use mocking when appropriate)

**Test coverage guidelines:**
- All exported functions must have tests
- Critical internal functions should have tests
- Bug fixes must include regression tests
- Aim for >80% code coverage on new code

**Run tests before committing:**
```r
# Run all tests
devtools::test()

# Run specific test file
testthat::test_file("tests/testthat/test-my_function.R")

# Check test coverage
covr::package_coverage()
```

## Git Commit Messages

### Summarizing Changes

**When preparing a commit message, briefly summarize all changed files using a small number of high-level bullet points:**

```bash
# ✅ CORRECT - High-level summary
feat: Simplify API with context-based tracking

- Add session context management for run_id
- Make subtask numbering automatic
- Add parallel cluster helpers
- Update documentation with v2.0 examples

# ❌ INCORRECT - Too detailed or missing context
Update R/task_update.R
Update R/subtask_start.R
Update R/subtask_update.R
...
```

**Guidelines:**
- **Use high-level themes** instead of listing individual file changes
- **Group related changes** into conceptual bullet points (3-5 bullets)
- **Focus on user-facing changes** and their benefits
- **Include context** about why changes were made when relevant
- Review output from `get_changed_files` to ensure all changes are represented

## Common Gotchas

1. **Register tasks with script_filename** - Required for auto-detection to work
2. **Don't use renderUI() for content updates** - Use reactive data + renderText/renderUI for structure only
3. **Don't serialize connection objects** - Always return `NULL` from `clusterEvalQ()` when creating connections
4. **Use atomic increments** - `subtask_increment()` for parallel workers, not `subtask_update()`
5. **Cast COUNT() to INTEGER** - Avoid bigint conversion issues
6. **Run from project root** - Ensure renv and .Renviron are loaded
7. **Single quote shell commands** - Prevent shell variable expansion
8. **Export all needed variables** - Use `clusterExport()` for global variables needed by workers
