# GitHub Copilot Instructions for tasker-dev

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

## Common Gotchas

1. **Don't use renderUI() for content updates** - Use reactive data + renderText/renderUI for structure only
2. **Don't serialize connection objects** - Always return `NULL` from `clusterEvalQ()` when creating connections
3. **Use atomic increments** - `subtask_increment()` for parallel workers, not `subtask_update()`
4. **Cast COUNT() to INTEGER** - Avoid bigint conversion issues
5. **Run from project root** - Ensure renv and .Renviron are loaded
6. **Single quote shell commands** - Prevent shell variable expansion
7. **Export all needed variables** - Use `clusterExport()` for global variables needed by workers
