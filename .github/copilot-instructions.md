# GitHub Copilot Instructions for tasker-dev

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

## Cross-Project Development

**When making changes in other project directories, always check for and use project-specific guidance:**

- **`.github/copilot-instructions.md`** - Project-specific instructions, anti-patterns, and critical warnings
- **`.github/skills/`** - Agent Skills with step-by-step procedural patterns

These files contain critical project-specific context including:
- Database patterns and anti-patterns
- Technology-specific considerations (Shiny, R, Python, etc.)
- Code review standards
- Common gotchas and error patterns
- Development workflows

**Example workflow:**
```bash
# Before modifying fccData code from tasker-dev context:
1. Read /home/warnes/src/fccData/.github/copilot-instructions.md
2. Check /home/warnes/src/fccData/.github/skills/ for relevant patterns
3. Apply project-specific rules when making changes
```

## Shiny Application Development

### Critical: Avoid renderUI() Anti-Pattern

**NEVER use `renderUI()` for updating dynamic content.** It causes:
- UI flickering and poor user experience
- Loss of scroll position in scrollable containers
- Complete DOM reconstruction on every update
- Memory overhead and performance degradation
- Input focus loss and control state reset

### ✅ CORRECT: Static Structure + Reactive Updates

**Pattern:** Create UI elements once, update values through reactive expressions and `updateXXX()` functions.

```r
# ✅ CORRECT - UI structure created once
ui <- fluidPage(
  div(
    class = "log-terminal",
    htmlOutput("log_text")  # Container stays in DOM
  )
)

server <- function(input, output, session) {
  # Reactive data
  log_content <- reactive({
    # Depend on reactive trigger
    rv$log_refresh_trigger
    
    # Read and format data
    lines <- readLines(log_file)
    format_log_lines(lines)
  })
  
  # Render updates content only, not structure
  output$log_text <- renderUI({
    HTML(log_content())
  })
  
  # Trigger updates via reactive value
  observeEvent(input$refresh_button, {
    rv$log_refresh_trigger <- rv$log_refresh_trigger + 1
  })
}
```

### ❌ INCORRECT: renderUI() Recreates Everything

```r
# ❌ INCORRECT - Recreates entire UI structure on every update
output$log_content <- renderUI({
  tagList(
    div(class = "controls",
      selectInput(...),  # Recreated every time
      checkboxInput(...) # Recreated every time
    ),
    div(class = "log-terminal",
      HTML(format_log_lines(lines))  # Entire container recreated
    )
  )
})
```

### Preferred Update Patterns

#### 1. Split Static Structure from Dynamic Content

```r
# Static UI with controls (rendered once)
output$log_viewer <- renderUI({
  tagList(
    div(class = "controls",
      selectInput("num_lines", ...),
      actionButton("refresh", ...)
    ),
    div(class = "log-terminal",
      htmlOutput("log_content")  # Only this updates
    )
  )
})

# Dynamic content only
output$log_content <- renderUI({
  rv$trigger  # Reactive dependency
  HTML(read_and_format_log())
})
```

#### 2. Use updateXXX() Functions

```r
# For Shiny inputs, use update functions in observers
observeEvent(new_data(), {
  updateSelectInput(session, "task_filter", choices = new_choices)
  updateProgressBar(session, "progress_bar", value = new_progress)
  updateTextInput(session, "status_text", value = new_status)
})
```

#### 3. Use shinyjs for DOM Manipulation

```r
observeEvent(input$toggle_pane, {
  if (pane_visible) {
    shinyjs::hide("process_pane")
    shinyjs::removeClass("toggle_btn", "expanded")
  } else {
    shinyjs::show("process_pane")
    shinyjs::addClass("toggle_btn", "expanded")
  }
})
```

#### 4. Reactive Triggers for Content Updates

```r
# Use reactive value as trigger
rv <- reactiveValues(content_trigger = 0)

# Increment trigger to force re-render
observeEvent(input$update_button, {
  rv$content_trigger <- rv$content_trigger + 1
})

# Content depends on trigger
output$content <- renderUI({
  rv$content_trigger  # Re-renders when incremented
  generate_content()
})
```

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

### COUNT() Query Results

**Always cast COUNT() results to INTEGER** to avoid conversion issues:

```r
# ✅ CORRECT - Cast COUNT to INTEGER
dbGetQuery(con, "SELECT COUNT(*)::INTEGER as n FROM table_name")
dbGetQuery(con, "SELECT COUNT(DISTINCT column)::INTEGER as count FROM table_name")

# ❌ INCORRECT - Returns bigint which causes problems in R
dbGetQuery(con, "SELECT COUNT(*) as n FROM table_name")
```

**Why:** PostgreSQL's `COUNT()` returns bigint (int64), which R's RPostgres package converts to numeric, causing precision loss and scientific notation display.

### Connection Management

- Use `dbConnectBBC(mode="rw")` for read-write connections
- Use `dbConnectBBC(mode="r")` for read-only connections (note: 'r', not 'ro')
- Main process connection: `con <- dbConnectBBC(mode="rw")`
- Worker connections: Created in each worker via `clusterEvalQ()`
- Use read-write connections for monitoring progress/status updates

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

**Always run R and R scripts from the project root directory** to ensure proper environment setup:

```bash
# ✅ CORRECT - From project root
cd /home/warnes/src/tasker-dev
Rscript inst/scripts/my_script.R

# ❌ INCORRECT - From scripts directory (won't pick up renv or .Renviron)
cd /home/warnes/src/tasker-dev/inst/scripts
Rscript my_script.R
```

**Why:** Running from the project root ensures:
- `renv` package environment is activated
- `.Renviron` file is sourced for environment variables
- Relative paths work correctly
- `devtools::load_all()` can find the package source

**Avoid using `--vanilla` flag** with Rscript as it prevents loading of `.Renviron` and startup files.

### Shell Quoting for R Commands

**Always use single quotes `'...'` when passing R code to `R` or `Rscript` commands:**

```bash
# ✅ CORRECT - Single quotes prevent shell interpretation
Rscript -e 'cat("Hello!\n")'
R --slave -e 'result <- 2 + 2; print(result)'

# ❌ INCORRECT - Double quotes allow shell expansion
Rscript -e "cat('Hello!\n')"  # Shell interprets ! as history expansion
R --slave -e "result <- 2 + 2; print(result)"  # Variables like $var get expanded
```

**Why:** In bash, double quotes allow:
- Variable expansion: `$var` gets replaced with variable value
- Command substitution: `$(command)` gets executed
- History expansion: `!` triggers history substitution (if enabled)
- Escape sequences: `\n`, `\t` may be interpreted by shell

Single quotes preserve the literal string, preventing shell interpretation and ensuring R code is passed exactly as written.

### R Script Argument Handling

**Always use the `argparse` package for handling command-line arguments in R scripts:**

```r
# ✅ CORRECT - Use argparse for robust argument handling
library(argparse)

# Create argument parser
parser <- ArgumentParser(description = "Process data with configurable options")
parser$add_argument("--input", type = "character", required = TRUE,
                   help = "Input data file path")
parser$add_argument("--output", type = "character", required = TRUE,
                   help = "Output file path")
parser$add_argument("--ncores", type = "integer", default = 4,
                   help = "Number of parallel cores to use [default: 4]")
parser$add_argument("--overwrite", action = "store_true", default = FALSE,
                   help = "Overwrite existing output files")
parser$add_argument("--verbose", action = "store_true", default = FALSE,
                   help = "Enable verbose output")

# Parse arguments
args <- parser$parse_args()

# Use parsed arguments
if (args$verbose) {
  cat("Processing", args$input, "with", args$ncores, "cores...\n")
}

# ❌ INCORRECT - Manual argument parsing (fragile and error-prone)
args <- commandArgs(trailingOnly = TRUE)
input_file <- args[1]  # No validation, unclear meaning
ncores <- as.integer(args[2])  # May fail with no error handling
```

**Why use argparse:**
- **Automatic help generation**: `--help` flag automatically works
- **Type validation**: Ensures arguments are correct types
- **Required argument checking**: Fails with clear error if required args missing
- **Default values**: Clean handling of optional parameters
- **Clear documentation**: Help text makes script usage obvious
- **Standard conventions**: Follows common CLI patterns (`--flag`, `-f`)

**Example usage:**
```bash
# Script provides helpful usage information
Rscript my_script.R --help

# Clear, self-documenting command lines
Rscript my_script.R --input data.csv --output results.csv --ncores 8 --overwrite --verbose
```

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
