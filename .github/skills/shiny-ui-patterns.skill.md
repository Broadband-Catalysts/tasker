# Shiny UI Update Patterns Skill

## Purpose
Best practices for updating Shiny UI elements without causing flickering, performance issues, or poor user experience.

## When to Use
- Creating or modifying Shiny applications
- Implementing dynamic UI updates
- Fixing UI flickering or performance problems
- Updating displayed content reactively

## CRITICAL Anti-Pattern: Never Use renderUI() for Content Updates

### ❌ WRONG: renderUI() Recreates Everything

**This causes:**
- UI flickering and poor UX
- Loss of scroll position in containers
- Complete DOM reconstruction on every update
- Memory overhead and performance degradation
- Input focus loss and control state reset

```r
# ❌ INCORRECT - Don't do this!
output$log_content <- renderUI({
  tagList(
    div(class = "controls",
      selectInput("num_lines", "Lines", choices = c(50, 100, 200)),
      checkboxInput("auto_scroll", "Auto-scroll"),
      actionButton("refresh", "Refresh")
    ),
    div(class = "log-terminal",
      HTML(format_log_lines(lines))  # Entire container recreated on every update!
    )
  )
})
```

**Problems:**
1. Every time `lines` changes, the entire UI structure is destroyed and rebuilt
2. User's scroll position is lost
3. Input focus is lost if user was typing
4. Checkbox/select states may reset
5. Visual flicker as DOM elements are removed and re-added

## ✅ CORRECT Pattern: Static Structure + Reactive Content

### Principle: Separate Structure from Data

**Create UI elements once, update only their values:**

```r
# UI - Static structure (created once)
ui <- fluidPage(
  div(class = "controls",
    selectInput("num_lines", "Lines", choices = c(50, 100, 200)),
    checkboxInput("auto_scroll", "Auto-scroll"),
    actionButton("refresh", "Refresh")
  ),
  div(class = "log-terminal",
    htmlOutput("log_content")  # Only content inside updates
  )
)

# Server - Dynamic content only
server <- function(input, output, session) {
  # Reactive data
  log_lines <- reactive({
    input$refresh  # Dependency on refresh button
    
    # Read and format data
    lines <- readLines(log_file, n = as.integer(input$num_lines))
    format_log_lines(lines)
  })
  
  # Render updates content only, not structure
  output$log_content <- renderUI({
    HTML(log_lines())
  })
}
```

**Benefits:**
1. UI structure stays in DOM (no flickering)
2. Scroll position preserved
3. Input states maintained
4. Much better performance
5. Cleaner code separation

## Update Patterns

### Pattern 1: Split Static UI from Dynamic Content

When some UI needs to be conditionally rendered:

```r
# Static wrapper (rendered once, conditionally shown/hidden)
output$log_viewer_wrapper <- renderUI({
  # This runs only when visibility changes
  if (input$show_logs) {
    tagList(
      div(class = "controls",
        selectInput("num_lines", "Lines", choices = c(50, 100, 200)),
        actionButton("refresh", "Refresh")
      ),
      div(class = "log-terminal",
        htmlOutput("log_content")  # Dynamic content goes here
      )
    )
  }
})

# Dynamic content (updates frequently)
output$log_content <- renderUI({
  rv$trigger  # Reactive dependency
  HTML(read_and_format_log())
})
```

### Pattern 2: Use updateXXX() Functions

**For Shiny input controls, use update functions:**

```r
# ✅ CORRECT - Update controls without recreating them
observeEvent(new_task_data(), {
  # Update select input choices
  updateSelectInput(
    session, 
    "task_filter", 
    choices = get_task_list(),
    selected = input$task_filter  # Preserve selection
  )
  
  # Update text
  updateTextInput(session, "status_text", value = new_status())
  
  # Update numeric input
  updateNumericInput(session, "threshold", value = new_threshold())
})

# ❌ INCORRECT - Recreating controls
output$controls <- renderUI({
  new_task_data()  # Recreates on every change
  selectInput("task_filter", "Task", choices = get_task_list())
})
```

**Available update functions:**
- `updateSelectInput()` - Dropdown menus
- `updateCheckboxInput()` - Checkboxes
- `updateTextInput()` - Text fields
- `updateNumericInput()` - Numeric inputs
- `updateSliderInput()` - Sliders
- `updateRadioButtons()` - Radio buttons
- `updateDateInput()` - Date pickers

### Pattern 3: Use shinyjs for DOM Manipulation

```r
library(shinyjs)

# UI must include useShinyjs()
ui <- fluidPage(
  useShinyjs(),
  div(id = "process_pane", class = "pane", ...)
)

# Server - Show/hide/toggle elements
server <- function(input, output, session) {
  observeEvent(input$toggle_pane, {
    if (pane_visible()) {
      shinyjs::hide("process_pane")
      shinyjs::removeClass("toggle_btn", "expanded")
      shinyjs::disable("submit_btn")
    } else {
      shinyjs::show("process_pane")
      shinyjs::addClass("toggle_btn", "expanded")
      shinyjs::enable("submit_btn")
    }
  })
}
```

**shinyjs functions:**
- `show()` / `hide()` - Visibility
- `toggle()` - Toggle visibility
- `addClass()` / `removeClass()` - CSS classes
- `enable()` / `disable()` - Enable/disable inputs
- `html()` - Update innerHTML
- `runjs()` - Run custom JavaScript

### Pattern 4: Reactive Triggers for Content Updates

```r
# ✅ CORRECT - Use reactive value as trigger
server <- function(input, output, session) {
  rv <- reactiveValues(
    content_trigger = 0,
    data_version = 0
  )
  
  # Increment trigger to force re-render
  observeEvent(input$update_button, {
    rv$content_trigger <- rv$content_trigger + 1
  })
  
  # Periodic auto-update
  observe({
    invalidateLater(10000)  # Every 10 seconds
    rv$content_trigger <- rv$content_trigger + 1
  })
  
  # Content depends on trigger
  output$content <- renderUI({
    rv$content_trigger  # Re-renders when incremented
    HTML(generate_current_content())
  })
}
```

### Pattern 5: Conditional Rendering with req()

```r
# Only render when data is available
output$data_table <- renderTable({
  req(input$task_filter)  # Wait for selection
  
  task_id <- input$task_filter
  get_task_data(task_id)
})

# Multiple requirements
output$analysis <- renderPlot({
  req(input$start_date)
  req(input$end_date)
  req(input$start_date <= input$end_date)  # Validation
  
  generate_plot(input$start_date, input$end_date)
})
```

## Performance Best Practices

### 1. Debounce Rapid Changes

```r
# Debounce text input (wait for user to stop typing)
task_search <- reactive({
  input$search_text
}) %>% debounce(500)  # Wait 500ms after last keystroke

output$search_results <- renderTable({
  get_results(task_search())
})
```

### 2. Throttle High-Frequency Updates

```r
# Throttle slider updates (max once per 100ms)
slider_value <- reactive({
  input$threshold
}) %>% throttle(100)

output$filtered_data <- renderTable({
  filter_data(slider_value())
})
```

### 3. Use isolate() to Prevent Reactive Chains

```r
# Update plot only when button clicked, not on every slider change
output$plot <- renderPlot({
  input$update_plot  # Depends on button only
  
  # Read inputs without creating dependencies
  threshold <- isolate(input$threshold)
  color <- isolate(input$color_scheme)
  
  generate_plot(threshold, color)
})
```

### 4. Cache Expensive Computations

```r
# Memoize expensive function calls
library(memoise)

expensive_calculation <- memoise(function(param) {
  # ... complex computation ...
  result
})

# Use in reactive
output$result <- renderText({
  expensive_calculation(input$param)  # Cached automatically
})
```

## Common Mistakes

### Mistake 1: Nested renderUI()

```r
# ❌ INCORRECT - Multiple layers of renderUI
output$outer <- renderUI({
  div(
    uiOutput("inner")  # Another renderUI
  )
})

output$inner <- renderUI({
  div(
    uiOutput("innermost")  # Yet another!
  )
})

# ✅ CORRECT - Single static structure
ui <- div(
  div(
    htmlOutput("content")  # Just the content updates
  )
)
```

### Mistake 2: renderUI() in Loops

```r
# ❌ INCORRECT - Creating outputs in loop
lapply(1:n_tasks, function(i) {
  output[[paste0("task_", i)]] <- renderUI({
    # Recreates on every update!
    task_ui(task_list[[i]])
  })
})

# ✅ CORRECT - Use renderTable or renderUI once
output$task_list <- renderUI({
  lapply(task_list(), function(task) {
    task_ui(task)  # Simple HTML generation, not reactive
  })
})
```

### Mistake 3: Forgetting session$ for Updates

```r
# ❌ INCORRECT - Missing session parameter
observeEvent(input$reset, {
  updateTextInput("name", value = "")  # ERROR!
})

# ✅ CORRECT - Include session
observeEvent(input$reset, {
  updateTextInput(session, "name", value = "")
})
```

## When renderUI() IS Appropriate

**Use renderUI() only when:**

1. **Entire UI structure must change** (not just content):
   ```r
   output$dynamic_ui <- renderUI({
     if (input$ui_type == "table") {
       tableOutput("data_table")
     } else {
       plotOutput("data_plot")
     }
   })
   ```

2. **Number of UI elements is dynamic**:
   ```r
   output$param_inputs <- renderUI({
     n <- input$num_parameters
     lapply(1:n, function(i) {
       numericInput(paste0("param_", i), paste("Parameter", i), value = 0)
     })
   })
   ```

3. **UI depends on external file/config** that changes structure:
   ```r
   output$form <- renderUI({
     config <- read_config()
     generate_form_from_config(config)  # Structure varies by config
   })
   ```

## Summary

**Golden Rule:** Create UI structure once, update only the data/content that changes.

**Prefer:**
1. Static UI + `renderText()`, `renderTable()`, `renderPlot()`
2. `updateXXX()` functions for input controls
3. `shinyjs::show()` / `hide()` for visibility
4. Reactive triggers with `reactiveValues()`

**Avoid:**
1. `renderUI()` for frequent content updates
2. Nested `renderUI()` calls
3. Recreating static elements on every update
