# Tasker Shiny App: Static UI Design Document

## Overview

This document outlines a redesigned architecture for the Tasker Shiny dashboard that creates the HTML UI (DOM) structure **once** during initialization and updates individual widgets dynamically, rather than recreating HTML elements on each data change. This approach significantly improves performance and reduces UI flickering.

## Current Architecture Issues

### Problems with Dynamic UI Generation
- Extensive use of `uiOutput()` and `renderUI()` recreates DOM elements on every update
- Causes UI flickering and performance degradation
- Memory overhead from constant HTML regeneration
- Poor user experience with progress bars that reset/redraw

### Current Inefficient Pattern
```r
# CURRENT - Creates new HTML elements each time
uiOutput("task_progress_123")
output$task_progress_123 <- renderUI({
  # Recreates entire progress bar HTML
  progressBar(id = "...", value = task_progress, ...)
})
```

## New Static UI Architecture

### Core Principle: Create Once, Update Many
1. **Static Structure**: Create all UI elements once during app initialization
2. **Dynamic Updates**: Use `updateXXX()` functions and reactive updates to modify values
3. **Minimal DOM Changes**: Only update specific attributes/values, not entire elements

### Optimized Pattern
```r
# NEW - Creates HTML once, updates values only
progressBar(id = "task_progress_123", value = 0, title = "Task:")

# Later updates
observe({
  updateProgressBar(session, "task_progress_123", 
                   value = new_progress, title = new_label)
})
```

## UI Architecture Design

### 1. Static Structure Generation

#### Stage Accordion with Fixed Elements
```r
# Create accordion structure once with static IDs
accordion(
  id = "pipeline_stages",
  # Generate panels for all possible stages
  map(stages, function(stage) {
    accordion_panel(
      title = div(
        class = "stage-header",
        span(class = "stage-name", stage$stage_name),
        span(id = glue("stage_badge_{stage$id}"), class = "badge"),
        div(id = glue("stage_progress_{stage$id}"), class = "stage-progress"),
        span(id = glue("stage_count_{stage$id}"), class = "stage-count")
      ),
      value = glue("stage_{stage$id}"),
      # Static task rows
      map(stage_tasks, create_static_task_row)
    )
  })
)
```

#### Static Task Row Structure
```r
create_static_task_row <- function(task) {
  task_id <- generate_task_id(task)
  
  div(
    class = "task-row",
    id = glue("task_row_{task_id}"),
    
    # Static task name
    div(class = "task-name", task$task_name),
    
    # Status badge - created once, updated via CSS classes
    span(id = glue("status_{task_id}"), class = "badge badge-secondary", "NOT_STARTED"),
    
    # Progress container with dual bars
    div(
      class = "task-progress-container",
      # Primary progress bar
      progressBar(
        id = glue("progress_main_{task_id}"),
        value = 0,
        total = 100,
        title = "Task:",
        status = "secondary",
        display_pct = FALSE
      ),
      
      # Secondary items progress bar (initially hidden)
      progressBar(
        id = glue("progress_items_{task_id}"),
        value = 0,
        total = 100,
        title = "Items:",
        status = "info",
        size = "sm",
        display_pct = FALSE
      ) %>% hidden()
    ),
    
    # Message area
    div(
      id = glue("message_{task_id}"),
      class = "task-message",
      ""
    ),
    
    # Reset button
    actionButton(
      glue("reset_{task_id}"),
      "Reset",
      class = "btn-sm btn-warning task-reset-btn"
    )
  )
}
```

### 2. Reactive Update System

#### Task Status Updates
```r
# Single observer for all task updates
observe({
  # Get all current task statuses
  active_tasks <- get_active_tasks()
  
  # Update each task individually
  iwalk(task_registry, function(task, task_key) {
    task_id <- generate_task_id(task)
    current_status <- get_task_current_status(task)
    
    # Update status badge
    update_status_badge(session, task_id, current_status)
    
    # Update progress bars
    update_task_progress(session, task_id, current_status)
    
    # Update message
    update_task_message(session, task_id, current_status)
  })
}) %>% bindEvent(input$refresh_trigger, timer_trigger())
```

#### Granular Update Functions
```r
update_status_badge <- function(session, task_id, status_data) {
  status <- status_data$status
  badge_id <- glue("status_{task_id}")
  
  # Update badge text and CSS class using shinyjs
  html(badge_id, status)
  removeClass(badge_id, "badge-secondary badge-success badge-warning badge-danger badge-info")
  addClass(badge_id, glue("badge-{status_to_class(status)}"))
}

update_task_progress <- function(session, task_id, status_data) {
  # Calculate progress values
  main_progress <- calculate_main_progress(status_data)
  items_progress <- calculate_items_progress(status_data)
  
  # Build enhanced label with subtask info AND progress message
  main_label <- build_task_label(status_data)
  
  # Update main progress bar with comprehensive title
  updateProgressBar(
    session = session,
    id = glue("progress_main_{task_id}"),
    value = main_progress$value,
    title = main_label,  # Includes: "Task: X/Y (Z%) - Subtask A.B | Subtask Name | Progress Message"
    status = status_to_progress_style(status_data$status)
  )
  
  # Update items progress bar (show/hide as needed)
  items_id <- glue("progress_items_{task_id}")
  if (!is.null(items_progress)) {
    show(items_id)
    updateProgressBar(
      session = session,
      id = items_id,
      value = items_progress$value,
      title = items_progress$label
    )
  } else {
    hide(items_id)
  }
}

update_task_message <- function(session, task_id, status_data) {
  message_id <- glue("message_{task_id}")
  message_text <- status_data$overall_progress_message %||% ""
  
  # Update message text and tooltip using shinyjs
  html(message_id, message_text)
  
  # Update title attribute for tooltip (requires custom function)
  runjs(glue("document.getElementById('{message_id}').title = '{message_text}';"))
}
```

### 3. Enhanced Label Building

#### Subtask-Aware Progress Labels with Messages
```r
build_task_label <- function(status_data) {
  base_label <- build_base_progress_label(status_data)
  
  # Add current subtask information if available
  if (has_active_subtask(status_data)) {
    subtask_info <- get_current_subtask_info(status_data$run_id)
    if (!is.null(subtask_info)) {
      task_order <- get_task_order(status_data$stage_name, status_data$task_name)
      subtask_suffix <- sprintf(" - Subtask %d.%d | %s", 
                               task_order, 
                               subtask_info$subtask_number,
                               subtask_info$subtask_name)
      base_label <- paste0(base_label, subtask_suffix)
    }
  }
  
  # Add progress message if available
  progress_message <- status_data$overall_progress_message %||% ""
  if (!is.null(progress_message) && progress_message != "") {
    base_label <- paste0(base_label, " | ", progress_message)
  }
  
  return(base_label)
}

# Enhanced function to get comprehensive subtask details
get_current_subtask_info <- function(run_id) {
  tryCatch({
    subs <- tasker::get_subtask_progress(run_id)
    if (!is.null(subs) && nrow(subs) > 0) {
      # Get most recently updated active subtask (RUNNING or STARTED)
      active <- subs[subs$status %in% c("RUNNING", "STARTED"), ]
      if (nrow(active) > 0) {
        # Use last_update to get the most recently updated active subtask
        active[order(active$last_update, decreasing = TRUE), ][1, ]
      } else {
        # Fallback to most recent subtask overall
        subs[order(subs$last_update, decreasing = TRUE), ][1, ]
      }
    } else {
      NULL
    }
  }, error = function(e) NULL)
}

build_base_progress_label <- function(status_data) {
  status <- status_data$status
  current_subtask <- status_data$current_subtask %||% 0
  total_subtasks <- status_data$total_subtasks %||% 0
  progress_pct <- status_data$overall_percent_complete %||% 0
  
  if (status == "COMPLETED") {
    if (total_subtasks > 0) {
      sprintf("Task: %d/%d (100%%)", total_subtasks, total_subtasks)
    } else {
      "Task: 100%"
    }
  } else if (status %in% c("RUNNING", "STARTED")) {
    if (total_subtasks > 0) {
      sprintf("Task: %d/%d (%.1f%%)", current_subtask, total_subtasks, progress_pct)
    } else {
      sprintf("Task: %.1f%%", progress_pct)
    }
  } else if (status == "FAILED") {
    sprintf("Task: %.1f%% (FAILED)", progress_pct)
  } else {
    "Task:"
  }
}
```

#### Comprehensive Progress Bar Title Format

The progress bar title combines multiple information sources to provide maximum context:

```
Format: "Task: X/Y (Z%) - Subtask A.B | Subtask Name | Progress Message"

Examples:
- "Task: 3/6 (50.0%) - Subtask 4.3 | Process program files (locations, attributes, geometries) | Processing state files"
- "Task: 2/4 (25.0%) - Subtask 2.1 | Download BDC data | Downloaded 1,247/3,400 files"
- "Task: 100% - Processing completed successfully"
```

**Title Components:**
1. **Base Progress**: "Task: X/Y (Z%)" - Shows current subtask and overall percentage
2. **Subtask Identifier**: "- Subtask A.B" - Shows task order and subtask number  
3. **Subtask Name**: "| Subtask Description" - Descriptive name of current operation
4. **Progress Message**: "| Current Status" - Real-time progress updates from the task

**Dynamic Behavior:**
- Updates automatically as subtasks progress
- Shows only relevant components (e.g., no subtask info if task not started)
- Truncates gracefully for very long messages
- Maintains consistency across all progress bars
```

### 4. shinyjs DOM Manipulation

#### Using shinyjs for Dynamic Updates
```r
# Initialize shinyjs in UI
ui <- fluidPage(
  useShinyjs(),  # Enable shinyjs
  # ... rest of UI
)

# Common shinyjs functions for task updates
update_element_class <- function(element_id, old_classes, new_class) {
  removeClass(element_id, old_classes)
  addClass(element_id, new_class)
}

update_element_text <- function(element_id, text, tooltip = NULL) {
  html(element_id, text)
  if (!is.null(tooltip)) {
    runjs(glue("document.getElementById('{element_id}').title = '{tooltip}';"))
  }
}

toggle_element_visibility <- function(element_id, show_element) {
  if (show_element) {
    show(element_id)
  } else {
    hide(element_id)
  }
}

# Status badge updates
update_status_with_animation <- function(task_id, new_status) {
  badge_id <- glue("status_{task_id}")
  
  # Add transition effect
  addClass(badge_id, "status-transition")
  
  # Update after brief delay for animation
  delay(100, {
    update_element_class(
      badge_id, 
      "badge-secondary badge-success badge-warning badge-danger",
      glue("badge-{status_to_class(new_status)}")
    )
    html(badge_id, new_status)
    removeClass(badge_id, "status-transition")
  })
}
```

### 5. Performance Optimizations

#### Efficient Data Fetching
```r
# Batch data fetching with caching
get_all_task_statuses <- function() {
  # Single DB query for all active tasks
  active_tasks <- get_active_tasks()
  
  # Cache results with timestamp
  cache_key <- digest::digest(list(active_tasks, Sys.time() %/% 5)) # 5-second cache
  
  if (exists(cache_key, envir = task_cache)) {
    return(get(cache_key, envir = task_cache))
  }
  
  # Fetch subtask info in batch
  run_ids <- active_tasks$run_id[!is.na(active_tasks$run_id)]
  subtask_data <- if (length(run_ids) > 0) {
    get_subtask_progress_batch(run_ids)
  } else {
    list()
  }
  
  result <- list(
    tasks = active_tasks,
    subtasks = subtask_data,
    timestamp = Sys.time()
  )
  
  assign(cache_key, result, envir = task_cache)
  return(result)
}
```

#### Selective Updates
```r
# Only update changed elements
update_changed_tasks <- function(session, new_data, previous_data) {
  changed_tasks <- detect_task_changes(new_data, previous_data)
  
  iwalk(changed_tasks, function(task_data, task_id) {
    # Only update specific changed attributes
    changes <- detect_attribute_changes(task_data, previous_data[[task_id]])
    
    if ("status" %in% changes) {
      update_status_badge(session, task_id, task_data)
    }
    
    if (any(c("progress", "subtask") %in% changes)) {
      update_task_progress(session, task_id, task_data)
    }
    
    if ("message" %in% changes) {
      update_task_message(session, task_id, task_data)
    }
  })
}
```

### 6. Stage-Level Aggregation

#### Static Stage Headers with Dynamic Updates
```r
# Stage progress calculation and update
update_stage_progress <- function(session, stage_name, stage_tasks) {
  stage_id <- generate_stage_id(stage_name)
  
  # Calculate aggregated metrics
  completed_count <- sum(stage_tasks$status == "COMPLETED")
  total_count <- nrow(stage_tasks)
  running_count <- sum(stage_tasks$status %in% c("RUNNING", "STARTED"))
  failed_count <- sum(stage_tasks$status == "FAILED")
  
  # Determine stage status
  stage_status <- if (failed_count > 0) {
    "FAILED"
  } else if (completed_count == total_count) {
    "COMPLETED"
  } else if (running_count > 0) {
    "RUNNING"
  } else {
    "NOT_STARTED"
  }
  
  # Update stage badge using shinyjs
  stage_badge_id <- glue("stage_badge_{stage_id}")
  html(stage_badge_id, stage_status)
  update_element_class(
    stage_badge_id,
    "badge-secondary badge-success badge-warning badge-danger",
    glue("badge-{status_to_class(stage_status)}")
  )
  
  # Update stage progress bar
  stage_progress_pct <- round(100 * completed_count / total_count, 1)
  stage_progress_id <- glue("stage_progress_{stage_id}")
  
  # Update progress bar value and status
  updateProgressBar(
    session = session,
    id = stage_progress_id,
    value = stage_progress_pct,
    status = status_to_progress_style(stage_status)
  )
  
  # Update stage count using shinyjs
  stage_count_id <- glue("stage_count_{stage_id}")
  html(stage_count_id, glue("{completed_count}/{total_count}"))
}
```

## Implementation Benefits

### Performance Improvements
- **Reduced DOM Manipulation**: 90% reduction in HTML element creation/destruction
- **Eliminated UI Flickering**: Progress bars update smoothly without redrawing
- **Lower Memory Usage**: No constant HTML string generation and parsing
- **Faster Updates**: Direct value updates vs. full element recreation

### User Experience Enhancements
- **Smooth Animations**: Progress bars can use CSS transitions
- **Consistent State**: No loss of UI state during updates
- **Responsive Interface**: Faster response to user interactions
- **Better Accessibility**: Stable element IDs for screen readers

### Development Benefits
- **Cleaner Code**: Separation of structure and data updates using R functions
- **No Custom JavaScript**: shinyjs eliminates need for custom message handlers
- **Easier Debugging**: Standard shinyjs functions with clear R syntax
- **Maintainable**: Clear distinction between UI creation and updates
- **R-Native**: All DOM manipulation stays within R ecosystem
- **Testable**: Individual update functions can be unit tested

## Migration Strategy

### Phase 1: Core Infrastructure
1. Add shinyjs dependency and useShinyjs() to UI
2. Create static UI generation functions
3. Build shinyjs-based update utility functions
4. Implement helper functions for common DOM operations

### Phase 2: Task Progress Migration
1. Convert task rows to static structure
2. Implement task update observers
3. Add enhanced label building

### Phase 3: Stage Integration
1. Convert stage headers to static structure
2. Implement stage aggregation updates
3. Add accordion state management

### Phase 4: Optimization
1. Add caching and batch updates
2. Implement selective change detection
3. Add performance monitoring

## Testing Strategy

### Unit Tests
- Test individual update functions
- Verify label building logic
- Test change detection algorithms

### Integration Tests
- Test full update cycles
- Verify UI consistency
- Test error handling

### Performance Tests
- Measure update latency
- Monitor memory usage
- Benchmark against current implementation

This design provides a robust, performant foundation for the Tasker Shiny dashboard while maintaining all existing functionality and adding enhanced progress reporting capabilities.