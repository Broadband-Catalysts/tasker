# GitHub Copilot Instructions for tasker-dev

# 🛑 STOP - READ THIS FIRST 🛑

**Before responding to ANY request involving code changes or multi-step work:**

☐ State which copilot-instructions.md sections apply to this request
☐ Check if any Agent Skills apply (list them explicitly)
☐ If multi-step work: Create todo list with #manage_todo_list
☐ Mark tasks in-progress and completed as you work
☐ Use #code-review before finalizing ANY code changes
☐ Use "we" collaborative language and refer to user as "Dr. Greg"

**If you cannot check ALL boxes above, STOP and ask for clarification.**

**Example Response Format:**
```
**Following copilot-instructions.md sections: Shiny Patterns, Database Patterns**
**Applicable Agent Skills: #code-review, #git-commit-message**
**Will use #manage_todo_list for multi-step tracking**

Dr. Greg, we need to...
```

---

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
- **#shiny-ui-patterns** - For Shiny UI updates without flickering
- **#database-patterns** - For database connection and query patterns
- **#r-script-execution** - For running scripts and managing packages
- **#unit-testing** - For creating and maintaining test coverage
- **#manage_todo_list** - For multi-step task tracking and planning

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

When creating database connections (or other non-serializable objects) in parallel workers using `clusterEvalQ()`, ensure the expression does **not** return the non-serializable object:

```r
# ✅ CORRECT - Returns NULL to avoid serialization
tmp <- clusterEvalQ(
  cl,
  { 
    con <- dbConnectBBC(mode="rw")
    NULL  # Prevents "Error in unserialize(socklist[[n]]) : error reading from connection"
  }
)

# ✅ ALSO CORRECT - Has other code after connection that returns serializable value
tmp <- clusterEvalQ(
  cl,
  {
    con <- dbConnectBBC(mode="rw")
    # ... other setup code ...
    "ready"  # Returns a serializable string instead of connection
  }
)

# ❌ INCORRECT - Last expression returns the connection object
tmp <- clusterEvalQ(cl, con <- dbConnectBBC(mode="rw"))
```

**Why:** Database connection objects (and other objects containing file descriptors, external pointers, or system resources) cannot be serialized across R processes. The `clusterEvalQ()` function returns the result of the **last expression** in the block.

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

### Review Modified Files

**Always review all modified files for errors, omissions, anti-patterns, or other issues before finalizing changes:**

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
1. Check each modified file for completeness
2. Verify error handling is present
3. Look for potential race conditions or concurrency issues
4. Ensure database constraints are appropriate
5. Validate function signatures match their usage
6. Confirm documentation matches implementation

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
