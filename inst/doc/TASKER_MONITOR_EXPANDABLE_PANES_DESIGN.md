# Tasker Monitor - Expandable Sub-Panes Design Document

**Version:** 1.2  
**Date:** 2026-01-04  
**Status:** Approved - Ready for Implementation  

## Executive Summary

This document describes the design for integrating expandable sub-panes into the Tasker Monitor's main "Pipeline Status" tab. The enhancement will add two collapsible panels beneath each task row:

1. **Process Status Pane** - Shows detailed process and sub-process information
2. **Log Viewer Pane** - Displays task log files with live updates

These features will eliminate the need for separate tabs (Task Details, Log Viewer) by providing contextual information directly within each task row.

---

## Current Architecture

### UI Structure

The Tasker Monitor currently uses a **single-tab layout**:

**File:** [inst/shiny/ui.R](../shiny/ui.R)
```
- titlePanel (with build info)
- sidebarLayout
  ├─ sidebarPanel (filters, refresh controls)
  └─ mainPanel
      └─ tabsetPanel (id="main_tabs")
          └─ tabPanel("Pipeline Status")
              └─ accordion structure (#pipeline_stages_accordion)
```

### Server-Side Architecture

**File:** [inst/shiny/server.R](../shiny/server.R)

#### 1. **Data Management**
- **`pipeline_structure`**: ReactiveVal storing stages and registered tasks (loaded once at startup)
- **`task_reactives`**: ReactiveValues storing per-task status (updated on poll)
- **`stage_reactives`**: ReactiveValues storing aggregated stage statistics
- **`task_data()`**: Reactive that polls `tasker::get_task_status()` every N seconds

#### 2. **Static UI Generation** (Lines 590-680)
- Builds entire accordion HTML structure once when `pipeline_structure()` loads
- Creates empty placeholder divs for dynamic content:
  ```html
  <div id="task_status_{task_id}"></div>
  <div id="task_progress_{task_id}"></div>
  <div id="task_message_{task_id}"></div>
  <div id="task_reset_{task_id}"></div>
  ```

#### 3. **Reactive Content Updates** (Lines 690-840)
- Uses `shinyjs::html()` to update individual elements
- Each task component (status badge, progress bars, message, reset button) has its own reactive observer
- Updates only occur when underlying data changes

#### 4. **Progress Tracking**
The app displays:
- **Task-level progress**: Overall percentage and subtask completion (X/Y)
- **Item-level progress**: For subtasks with `items_total > 0` (e.g., "28/56 counties")
- **Dual progress bars**: When items exist and task is running
- **Subtask information**: Current subtask name and number

#### 5. **Existing Log Viewer** (Lines 1316-1450)
Currently in a **separate tab**:
- Dropdown to select task
- Configuration: number of lines, tail mode, auto-refresh
- Color-coded log lines (ERROR=red, WARNING=yellow, INFO=cyan)
- Updates every 3 seconds when auto-refresh enabled

### Data Flow

```
Database (PostgreSQL)
    ↓
tasker::get_task_status() [every 5s]
    ↓
task_data() reactive
    ↓
Observer updates task_reactives[[key]]
    ↓
Individual reactive observers per component
    ↓
shinyjs::html() updates DOM elements
```

### Styling

**File:** [inst/shiny/www/styles.css](../shiny/www/styles.css)

- Uses Bootstrap 5 accordion for stage collapsing
- Custom CSS for:
  - Status badges (color-coded by task status)
  - Progress bars (animated stripes for RUNNING tasks)
  - Task rows with flexbox layout
  - Log viewer formatting

---

## Proposed Enhanced Design

### Overview

Transform each task row from a **simple status display** into an **expandable panel** with two sub-panes:

```
[Task Row] ◀───────────────────────────────────────────────────────
│ [📊][📄] Task Name | Status Badge | Progress | Message | [Reset]
│  ^  ^
│  |  +-- Log viewer toggle (background changes when expanded: gray→blue)
│  +------ Process info toggle (background changes when expanded: gray→green)
│
├─ [Process Status Pane] ◀─ Toggleable with [📊] button
│  │ ┌─ Main Process Info
│  │ │  • PID: 12345
│  │ │  • Hostname: server.example.com
│  │ │  • CPU: 145% (across all processes)
│  │ │  • Memory: 8.5 GB
│  │ │  • Process Count: 12 (1 main + 11 workers)
│  │ └─ Child Process Tree (if parallel processing)
│  │    • [Worker 1] PID: 12346, CPU: 12%, Mem: 650MB
│  │    • [Worker 2] PID: 12347, CPU: 11%, Mem: 680MB
│  │    • ... (collapsible list)
│  │
│  └─ [Subtask Progress Table]
│     ┌─────────────────────────────────────────────────────────┐
│     │ # │ Subtask Name │ Status │ Progress │ Items │ Duration │
│     ├─────────────────────────────────────────────────────────┤
│     │ 1 │ Load data    │ DONE   │ 100%     │ 56/56 │ 2m 15s   │
│     │ 2 │ Transform    │ RUNNING│ 45.2%    │ 28/62 │ 1m 8s    │
│     │ 3 │ Finalize     │ PENDING│ 0%       │ 0/1   │ -        │
│     └─────────────────────────────────────────────────────────┘
│
└─ [Log Viewer Pane] ◀─ Toggleable with [📄] button
   │ ┌─ Controls
   │ │  [Last 100 lines ▼] [Tail Mode ☑] [Auto-refresh ☑] [Refresh]
   │ └─ Log Content (scrollable, syntax-highlighted)
   │    2026-01-04 14:32:15 INFO: Starting task...
   │    2026-01-04 14:32:16 INFO: Processing county 01001...
   │    2026-01-04 14:32:45 WARNING: Missing data for...
   │    2026-01-04 14:33:12 INFO: Completed 28/56 counties
   │    ... (live-updating content)
```

### UI Changes

#### 1. **Task Row Enhancements** (in `server.R`)

Modify the task row HTML generation (around line 640) to add **TWO SEPARATE** toggle buttons **grouped on the left side**:

```html
<div class="task-row" data-task-id="{task_id}">
  <!-- Toggle buttons grouped on the left -->
  <div class="task-toggle-buttons">
    <!-- Process info toggle button (graph icon) -->
    <button class="btn-expand-process" id="btn_expand_process_{task_id}" 
            onclick="Shiny.setInputValue('toggle_process_pane', '{task_id}', {priority: 'event'})">
      <i class="fa fa-chart-bar"></i>
    </button>
    
    <!-- Log viewer toggle button (file icon) -->
    <button class="btn-expand-log" id="btn_expand_log_{task_id}"
            onclick="Shiny.setInputValue('toggle_log_pane', '{task_id}', {priority: 'event'})">
      📄
    </button>
  </div>
  
  <div class="task-name">{task_name}</div>
  <div id="task_status_{task_id}" class="task-status-badge"></div>
  <div id="task_progress_{task_id}" class="task-progress-container"></div>
  <div id="task_message_{task_id}" class="task-message"></div>
  <div id="task_reset_{task_id}" class="task-reset-button"></div>
</div>

<!-- Process Status Sub-Pane (initially hidden) -->
<div id="process_pane_{task_id}" class="task-subpane process-pane" style="display: none;">
  <div id="process_content_{task_id}"></div>
</div>

<!-- Log Viewer Sub-Pane (initially hidden) -->
<div id="log_pane_{task_id}" class="task-subpane log-pane" style="display: none;">
  <div class="log-controls-container">
    <!-- Per-task log controls -->
    <div class="log-controls" id="log_controls_{task_id}">
      <select id="log_lines_{task_id}" class="form-control form-control-sm" style="width: auto;">
        <option value="50">50 lines</option>
        <option value="100" selected>100 lines</option>
        <option value="250">250 lines</option>
        <option value="500">500 lines</option>
        <option value="1000">1000 lines</option>
      </select>
      <label>
        <input type="checkbox" id="log_tail_{task_id}" checked> Tail mode
      </label>
      <label>
        <input type="checkbox" id="log_auto_refresh_{task_id}" checked> Auto-refresh
      </label>
      <input type="text" id="log_filter_{task_id}" placeholder="Filter/search..." 
             class="form-control form-control-sm" style="width: 200px;">
      <button class="btn btn-sm btn-primary" 
              onclick="Shiny.setInputValue('log_refresh_{task_id}', Date.now(), {priority: 'event'})">
        Refresh
      </button>
    </div>
  </div>
  <div id="log_content_{task_id}" class="log-content-container"></div>
</div>
```

**Key Points:**
- **TWO buttons grouped together on the left:** `btn-expand-process` (graph icon 📊) and `btn-expand-log` (file icon 📄)
- Each button triggers a separate Shiny input event
- Panes can be opened/closed independently
- **Visual state indicators:**
  - Process button: Background color changes when expanded (light gray → light green)
  - Log button: Background color changes when expanded (light gray → blue)
- Each log pane has its own set of controls with unique IDs

#### 2. **New CSS Classes** (in `www/styles.css`)

```css
/* Toggle buttons container */
.task-toggle-buttons {
  display: flex;
  gap: 4px;
  align-items: center;
  margin-right: 8px;
}

/* Process toggle button (graph icon) */
.btn-expand-process {
  border: 1px solid #ccc;
  background: #f8f9fa;
  padding: 4px 8px;
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s;
  display: flex;
  align-items: center;
  min-width: 28px;
  justify-content: center;
}

.btn-expand-process:hover {
  background: #e9ecef;
  border-color: #999;
}

/* Visual change when process pane is expanded */
.btn-expand-process.expanded {
  background: #d4edda;
  border-color: #c3e6cb;
  color: #155724;
}

/* Log toggle button (file icon) */
.btn-expand-log {
  border: 1px solid #ccc;
  background: #f8f9fa;
  padding: 4px 8px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  transition: all 0.2s;
  display: flex;
  align-items: center;
  min-width: 28px;
  justify-content: center;
}

.btn-expand-log:hover {
  background: #e9ecef;
  border-color: #999;
}

/* Visual change when log pane is expanded */
.btn-expand-log.expanded {
  background: #007bff;
  border-color: #007bff;
  color: white;
}

/* Sub-panes */
.task-subpane {
  margin: 10px 0 10px 40px;
  padding: 15px;
  background: #fff;
  border-left: 3px solid #007bff;
  border-radius: 4px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  animation: slideDown 0.3s ease-out;
}

@keyframes slideDown {
  from {
    opacity: 0;
    max-height: 0;
  }
  to {
    opacity: 1;
    max-height: 2000px;
  }
}

.task-subpane.process-pane {
  border-left-color: #007bff;
}

.task-subpane.log-pane {
  border-left-color: #6c757d;
}

/* Process validation error */
.process-error-warning {
  background: #fff3cd;
  border: 1px solid #ffc107;
  padding: 10px;
  margin-bottom: 15px;
  border-radius: 4px;
  color: #856404;
}

.process-error-warning strong {
  color: #dc3545;
}

/* Process info table */
.process-info-table {
  width: 100%;
  margin-bottom: 15px;
}

.process-info-table th {
  text-align: left;
  padding: 4px 8px;
  width: 150px;
  color: #666;
  font-weight: 600;
}

.process-info-table td {
  padding: 4px 8px;
}

/* Child process list */
.child-process-list {
  max-height: 200px;
  overflow-y: auto;
  font-family: monospace;
  font-size: 12px;
  background: #f8f9fa;
  padding: 10px;
  border-radius: 4px;
  margin-top: 10px;
}

.child-process-item {
  padding: 2px 0;
  display: flex;
  justify-content: space-between;
}

.child-process-item:nth-child(even) {
  background: #ffffff;
}

/* Subtask table */
.subtask-table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 10px;
}

.subtask-table th,
.subtask-table td {
  border: 1px solid #dee2e6;
  padding: 8px;
  text-align: left;
  font-size: 13px;
}

.subtask-table th {
  background: #f8f9fa;
  font-weight: 600;
}

.subtask-table tr:hover {
  background: #f8f9fa;
}

/* Log viewer controls */
.log-controls-container {
  margin-bottom: 10px;
}

.log-controls {
  display: flex;
  gap: 10px;
  align-items: center;
  flex-wrap: wrap;
  padding: 10px;
  background: #f8f9fa;
  border-radius: 4px;
  border: 1px solid #dee2e6;
}

.log-content-container {
  position: relative;
}

.log-output-pane {
  max-height: 400px;
  overflow-y: auto;
  overflow-x: auto;
  font-family: 'Courier New', monospace;
  font-size: 12px;
  background: #1e1e1e;
  color: #d4d4d4;
  padding: 10px;
  border-radius: 4px;
  white-space: pre;
  line-height: 1.4;
}

/* Log line styling */
.log-line {
  padding: 1px 0;
}

.log-line-error {
  color: #ff6b6b;
  font-weight: 500;
}

.log-line-warning {
  color: #ffd93d;
}

.log-line-info {
  color: #6bcfff;
}

/* Scroll position indicator */
.log-scroll-indicator {
  position: absolute;
  top: 5px;
  right: 5px;
  background: rgba(0, 123, 255, 0.8);
  color: white;
  padding: 3px 8px;
  border-radius: 3px;
  font-size: 11px;
  z-index: 10;
}
```

### Server-Side Implementation

#### 1. **Reactive State Management**

Add to `rv` reactiveValues (around line 220):

```r
rv <- reactiveValues(
  selected_task_id = NULL,
  last_update = NULL,
  expanded_stages = c(),
  error_message = NULL,
  force_refresh = 0,
  reset_pending_stage = NULL,
  reset_pending_task = NULL,
  # NEW: Track which sub-panes are expanded
  expanded_process_panes = c(),  # vector of task_ids
  expanded_log_panes = c()       # vector of task_ids
)
```

#### 2. **Toggle Event Handlers**

```r
# Toggle process pane
observeEvent(input$toggle_process_pane, {
  task_id <- input$toggle_process_pane
  
  if (task_id %in% rv$expanded_process_panes) {
    # Close pane
    rv$expanded_process_panes <- setdiff(rv$expanded_process_panes, task_id)
    shinyjs::hide(paste0("process_pane_", task_id))
    shinyjs::runjs(sprintf("$('#btn_expand_process_%s').removeClass('expanded')", task_id))
  } else {
    # Open pane
    rv$expanded_process_panes <- c(rv$expanded_process_panes, task_id)
    shinyjs::show(paste0("process_pane_", task_id))
    shinyjs::runjs(sprintf("$('#btn_expand_process_%s').addClass('expanded')", task_id))
  }
})

# Toggle log pane
observeEvent(input$toggle_log_pane, {
  task_id <- input$toggle_log_pane
  
  if (task_id %in% rv$expanded_log_panes) {
    rv$expanded_log_panes <- setdiff(rv$expanded_log_panes, task_id)
    shinyjs::hide(paste0("log_pane_", task_id))
  } else {
    rv$expanded_log_panes <- c(rv$expanded_log_panes, task_id)
    shinyjs::show(paste0("log_pane_", task_id))
  }
})
```

#### 3. **Process Status Content**

Create reactive observers that update process pane content when expanded:

```r
# Update process status panes for expanded tasks
observe({
  if (length(rv$expanded_process_panes) == 0) return()
  
  struct <- pipeline_structure()
  if (is.null(struct)) return()
  
  data <- task_data()
  if (is.null(data) || nrow(data) == 0) return()
  
  lapply(rv$expanded_process_panes, function(task_id) {
    # Get task data
    task_key <- gsub("_", "||", task_id, fixed = FALSE)  # Reverse transformation
    task_data_item <- task_reactives[[task_key]]
    
    if (is.null(task_data_item) || is.na(task_data_item$run_id)) {
      content <- "<div class='alert alert-info'>No active execution</div>"
    } else {
      # Fetch full task details
      task_row <- data[data$run_id == task_data_item$run_id, ]
      
      if (nrow(task_row) == 0) {
        content <- "<div class='alert alert-warning'>Task data not found</div>"
      } else {
        # Build process info HTML
        content <- build_process_status_html(task_row, task_data_item$run_id)
      }
    }
    
    shinyjs::html(paste0("process_content_", task_id), content)
  })
})
```

Helper function to build process status HTML:

```r
build_process_status_html <- function(task_row, run_id) {
  # Main process info
  main_info <- sprintf('
    <h4>Process Information</h4>
    <table class="process-info-table">
      <tr><th>Run ID:</th><td>%s</td></tr>
      <tr><th>Hostname:</th><td>%s</td></tr>
      <tr><th>Main PID:</th><td>%s</td></tr>
      <tr><th>Status:</th><td>%s</td></tr>
      <tr><th>Started:</th><td>%s</td></tr>
      <tr><th>Duration:</th><td>%s</td></tr>
    </table>',
    run_id,
    task_row$hostname %||% "N/A",
    task_row$process_id %||% "N/A",
    task_row$status,
    format(task_row$start_time, "%Y-%m-%d %H:%M:%S"),
    format_duration(task_row$start_time, task_row$last_update)
  )
  
  # Resource usage (if available)
  resource_info <- ""
  if (!is.na(task_row$process_count) && task_row$process_count > 0) {
    resource_info <- sprintf('
      <h4>Resource Usage</h4>
      <table class="process-info-table">
        <tr><th>Total Processes:</th><td>%d</td></tr>
        <tr><th>CPU Usage:</th><td>%.1f%%</td></tr>
        <tr><th>Memory:</th><td>%.2f GB</td></tr>
      </table>',
      task_row$process_count,
      task_row$cpu_percent %||% 0,
      (task_row$memory_mb %||% 0) / 1024
    )
  }
  
  # Subtask progress table
  subtasks <- tryCatch({
    tasker::get_subtask_progress(run_id)
  }, error = function(e) NULL)
  
  subtask_table <- ""
  if (!is.null(subtasks) && nrow(subtasks) > 0) {
    rows <- sapply(seq_len(nrow(subtasks)), function(i) {
      st <- subtasks[i, ]
      sprintf('
        <tr>
          <td>%d</td>
          <td>%s</td>
          <td><span class="badge status-%s">%s</span></td>
          <td>%.1f%%</td>
          <td>%d / %d</td>
          <td>%s</td>
          <td>%s</td>
        </tr>',
        st$subtask_number,
        st$subtask_name,
        st$status, st$status,
        st$percent_complete %||% 0,
        st$items_complete %||% 0,
        st$items_total %||% 0,
        st$progress_message %||% "",
        format_duration(st$start_time, st$last_update)
      )
    })
    
    subtask_table <- sprintf('
      <h4>Subtask Progress</h4>
      <table class="subtask-table">
        <thead>
          <tr>
            <th>#</th>
            <th>Subtask Name</th>
            <th>Status</th>
            <th>Progress</th>
            <th>Items</th>
            <th>Message</th>
            <th>Duration</th>
          </tr>
        </thead>
        <tbody>
          %s
        </tbody>
      </table>',
      paste(rows, collapse = "\n")
    )
  }
  
  paste(main_info, resource_info, subtask_table, sep = "\n")
}
```

#### 4. **Log Viewer Content**

```r
# Update log viewer panes for expanded tasks
observe({
  if (length(rv$expanded_log_panes) == 0) return()
  
  # Auto-refresh every 3 seconds for logs
  invalidateLater(3000)
  
  data <- task_data()
  if (is.null(data) || nrow(data) == 0) return()
  
  lapply(rv$expanded_log_panes, function(task_id) {
    # Get task data
    stage_task <- gsub("^(.+?)_(.+)$", "\\1||\\2", task_id)
    task_data_item <- task_reactives[[stage_task]]
    
    if (is.null(task_data_item) || is.na(task_data_item$run_id)) {
      content <- "<div class='alert alert-info'>No log file available</div>"
    } else {
      task_row <- data[data$run_id == task_data_item$run_id, ]
      
      if (nrow(task_row) == 0 || is.na(task_row$log_path) || is.na(task_row$log_filename)) {
        content <- "<div class='alert alert-info'>No log file configured</div>"
      } else {
        content <- build_log_viewer_html(task_row, task_id)
      }
    }
    
    shinyjs::html(paste0("log_content_", task_id), content)
  })
})
```

Helper function to build log viewer HTML:

```r
build_log_viewer_html <- function(task_row, task_id) {
  log_file <- file.path(task_row$log_path, task_row$log_filename)
  
  if (!file.exists(log_file)) {
    return(sprintf(
      '<div class="alert alert-warning">Log file not found: %s</div>',
      htmltools::htmlEscape(log_file)
    ))
  }
  
  # Read last 100 lines (tail mode)
  all_lines <- tryCatch({
    readLines(log_file, warn = FALSE)
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(all_lines) || length(all_lines) == 0) {
    return('<div class="alert alert-info">Log file is empty</div>')
  }
  
  # Get last 100 lines
  num_lines <- 100
  total_lines <- length(all_lines)
  start_line <- max(1, total_lines - num_lines + 1)
  lines <- all_lines[start_line:total_lines]
  
  # Format with syntax highlighting
  formatted_lines <- sapply(lines, function(line) {
    line <- htmltools::htmlEscape(line)
    
    class_attr <- ""
    if (grepl("ERROR|Error|FAIL|Failed", line, ignore.case = FALSE)) {
      class_attr <- " log-line-error"
    } else if (grepl("WARN|Warning", line, ignore.case = FALSE)) {
      class_attr <- " log-line-warning"
    } else if (grepl("INFO|Info", line, ignore.case = FALSE)) {
      class_attr <- " log-line-info"
    }
    
    paste0("<div class='log-line", class_attr, "'>", line, "</div>")
  })
  
  # Controls header
  controls <- sprintf('
    <div class="log-controls">
      <small><strong>File:</strong> %s</small>
      <small><strong>Lines:</strong> %d (last %d shown)</small>
      <small><strong>Updated:</strong> %s</small>
    </div>',
    htmltools::htmlEscape(basename(log_file)),
    total_lines,
    length(lines),
    format(Sys.time(), "%H:%M:%S")
  )
  
  log_content <- sprintf('
    <div class="log-output-pane">
      %s
    </div>',
    paste(formatted_lines, collapse = "")
  )
  
  paste(controls, log_content, sep = "\n")
}
```

---

## Data Requirements

### Database Queries

The implementation will use existing tasker functions:

1. **`tasker::get_task_status()`** - Already provides:
   - `run_id`, `hostname`, `process_id`, `status`
   - `start_time`, `end_time`, `last_update`
   - `log_path`, `log_filename`
   - `process_count`, `cpu_percent`, `memory_mb` (if available)

2. **`tasker::get_subtask_progress(run_id)`** - Provides subtask details:
   - `subtask_number`, `subtask_name`, `status`
   - `percent_complete`, `items_complete`, `items_total`
   - `progress_message`, `start_time`, `last_update`

3. **Log File Reading** - Direct file system access:
   - Read from `file.path(log_path, log_filename)`
   - Tail last N lines for efficiency

### Resource Monitoring

**Note:** The current tasker schema includes `process_count`, `cpu_percent`, and `memory_mb` fields in `task_runs`, but these may not be populated by all tasks. The process status pane will gracefully handle missing data.

If detailed child process monitoring is required, the tasker package has functions like `get_process_tree_resources()` which could be integrated.

---

## Performance Considerations

### Selective Updates

- **Only update expanded panes**: Check `rv$expanded_process_panes` and `rv$expanded_log_panes` before running observers
- **Debounce log updates**: Use `invalidateLater(3000)` to prevent excessive file reads
- **Limit log lines**: Default to last 100 lines, configurable

### Memory Management

- **Keep sub-panes collapsed by default**: Reduces initial rendering load
- **Lazy-load content**: Generate HTML only when pane is first expanded
- **Cleanup closed panes**: Consider removing from `expanded_*` vectors after a timeout

### File System Impact

- **Log file caching**: Consider caching log file reads with invalidation on file mtime
- **Read optimization**: Use `readLines(n = N)` for head mode, tail via R vector slicing

---

## Migration Plan

### Phase 1: Core Infrastructure (Hours 1-3)
1. Add toggle buttons to task rows
2. Create sub-pane HTML structure in static UI
3. Implement toggle event handlers
4. Add CSS styling for sub-panes

### Phase 2: Process Status Pane (Hours 4-6)
1. Implement `build_process_status_html()` function
2. Create reactive observers for process content updates
3. Add subtask progress table rendering
4. Test with running tasks

### Phase 3: Log Viewer Pane (Hours 7-9)
1. Implement `build_log_viewer_html()` function
2. Create reactive observers for log content updates
3. Add auto-refresh logic for active tasks
4. Test with various log file scenarios

### Phase 4: Testing & Refinement (Hours 10-12)
1. Test with multiple expanded panes
2. Verify performance with many tasks
3. Test edge cases (missing logs, no subtasks, etc.)
4. Refinement based on user feedback

### Phase 5: Cleanup (Optional)
1. Remove obsolete "Task Details" tab code
2. Remove obsolete "Log Viewer" tab code
3. Update documentation

---

## Approved Requirements (Answers from Review)

### 1. **Process Status Pane Content**
**APPROVED:** Option B - Detailed

Include individual child process listings with per-process CPU/memory

### 2. **Child Process Monitoring**
**APPROVED:** Option B - Yes, basic

List PIDs and status if available for parallel worker processes

### 3. **Process State Validation**
**NEW REQUIREMENT:** If a task is marked as "Started" or "Running" but the process is not present in the system, display the state as 'ERROR' with a warning message in the process pane.

### 4. **Subtask Display**
**APPROVED:** Conditional display - Only show subtask table section if `total_subtasks > 0`

### 5. **Log Viewer Configuration**
**APPROVED:** Option B - Per-task

Each task remembers its own settings (stored in ReactiveValues)

**User Controls:**
- ✅ Change number of lines displayed
- ✅ Toggle between head/tail mode
- ✅ Search/filter log content

### 6. **Auto-Refresh Behavior**
**APPROVED:** Custom Option D

Auto-refresh if the controlling process (or any sub-processes) are active.

**CRITICAL SCROLL POSITION HANDLING:**
- Preserve user's scroll position intelligently
- If viewing most recent line → keep scrolling to show new most recent line (tail mode)
- If viewing oldest line → keep showing oldest line
- If viewing middle section (e.g., lines 74-124) → preserve that exact view position

Implementation: Track scroll position as percentage or line numbers, not just pixel offset

### 7. **Default State**
**APPROVED:** Auto-expand for running tasks

When page loads, automatically expand process and log panes for tasks with status 'RUNNING' or 'STARTED'

### 8. **Multiple Expansions**
**APPROVED:** Option B - Independent (unlimited)

Users can expand as many task panes as desired simultaneously

### 9. **Integration with Existing Tabs**
**APPROVED:** Option A - Remove entirely

Delete obsolete "Task Details" and "Log Viewer" tabs after sub-panes are working

### 10. **Toggle Button Design**
**NEW REQUIREMENT:** Provide separate toggle buttons to open/close the process info pane and the log viewer pane independently.

Layout:
```
[▼] Task Name | Status | Progress | Message | [📊] [📄] [Reset]
     ^                                          ^    ^
     |                                          |    +-- Log viewer toggle
     |                                          +------- Process info toggle
     +-- Stage collapse (existing)
```

### 11. **Mobile/Responsive Considerations**
**APPROVED:** Option C - Full responsive design

Same functionality with adjusted layout for mobile devices

### 12. **Performance Thresholds**
**APPROVED:** No hard limits initially, monitor performance in production

---

## Success Criteria

The implementation will be considered successful when:

1. ✅ Users can independently toggle process status and log viewer panes for any task
2. ✅ Process status shows accurate PID, hostname, timing, and resource usage
3. ✅ Process status includes child process listings with PIDs when available
4. ✅ Process status detects when task is RUNNING/STARTED but process is dead (shows ERROR state)
5. ✅ Subtask progress displays correctly when `total_subtasks > 0`
6. ✅ Log viewer has per-task settings (lines, head/tail mode)
7. ✅ Log viewer includes search/filter functionality
8. ✅ Log content auto-refreshes intelligently when process is active
9. ✅ Scroll position is preserved correctly:
   - Tail mode: auto-scroll to show new lines
   - Head mode: stay at top
   - Middle view: preserve exact line range
10. ✅ Tasks with RUNNING/STARTED status auto-expand on page load
11. ✅ Multiple panes can be expanded simultaneously without performance degradation
12. ✅ UI remains responsive with 50+ tasks and 5-10 expanded panes
13. ✅ Existing stage accordion functionality is preserved
14. ✅ Works correctly when tasks have no logs, no subtasks, or dead processes
15. ✅ Old "Task Details" and "Log Viewer" tabs are removed

---

## Next Steps

✅ **Design Approved** - All questions answered, ready for implementation

### Implementation Order:

1. **Phase 1: Core Infrastructure** (Complete task row modifications)
   - Add separate toggle buttons for process and log panes
   - Create sub-pane HTML structure
   - Implement toggle event handlers with state tracking

2. **Phase 2: Process Status Pane** (Full detail with child processes)
   - Implement process validation (detect dead processes)
   - Build process info display with child process listings
   - Add subtask progress table (conditional)
   - Test with active and dead processes

3. **Phase 3: Log Viewer Pane** (Per-task settings with search)
   - Implement per-task settings storage (lines, head/tail, filter)
   - Build log viewer UI with controls
   - Implement intelligent scroll position tracking
   - Add search/filter functionality
   - Test scroll preservation in all modes

4. **Phase 4: Auto-Refresh & Auto-Expand**
   - Implement auto-refresh for active processes
   - Add scroll position preservation logic
   - Implement auto-expand for RUNNING/STARTED tasks on load
   - Test refresh behavior with multiple panes

5. **Phase 5: Cleanup**
   - Remove obsolete "Task Details" tab code
   - Remove obsolete "Log Viewer" tab code
   - Remove obsolete "Stage Summary" and "Timeline" tab code
   - Update documentation

---

## Appendix: Mockup HTML

Example of what a fully expanded task would look like with **BOTH toggle buttons**:

```html
<div class="task-row" data-task-id="STATIC_Load_Census_Blocks">
  <!-- Both toggle buttons grouped on the left -->
  <div class="task-toggle-buttons">
    <!-- Process info toggle (chevron rotated 90° when expanded) -->
    <button class="btn-expand-process expanded" id="btn_expand_process_STATIC_Load_Census_Blocks">
      <i class="fa fa-chevron-right"></i> <!-- Rotated to point down when expanded -->
    </button>
    
    <!-- Log viewer toggle (blue background when expanded) -->
    <button class="btn-expand-log expanded" id="btn_expand_log_STATIC_Load_Census_Blocks">
      📄
    </button>
  </div>
  
  <div class="task-name">Load Census Blocks</div>
  <div class="task-status-badge">
    <span class="badge bg-warning">RUNNING</span>
  </div>
  <div class="task-progress-container">
    <!-- Progress bars here -->
  </div>
  <div class="task-message">Processing subtask 2/3: Transform data</div>
  <button class="btn btn-sm btn-warning">Reset</button>
</div>

<!-- Expanded Process Status Pane -->
<div id="process_pane_STATIC_Load_Census_Blocks" class="task-subpane process-pane" style="display: block;">
  <h4>Process Information</h4>
  <table class="process-info-table">
    <tr><th>Run ID:</th><td>a1b2c3d4-5678-90ab-cdef-1234567890ab</td></tr>
    <tr><th>Hostname:</th><td>server.example.com</td></tr>
    <tr><th>Main PID:</th><td>45678 ✓ (Active)</td></tr>
    <tr><th>Status:</th><td>RUNNING</td></tr>
    <tr><th>Started:</th><td>2026-01-04 14:30:22</td></tr>
    <tr><th>Duration:</th><td>05:42</td></tr>
  </table>
  
  <h4>Resource Usage</h4>
  <table class="process-info-table">
    <tr><th>Total Processes:</th><td>17 (1 main + 16 workers)</td></tr>
    <tr><th>CPU Usage:</th><td>1420% (across all cores)</td></tr>
    <tr><th>Memory:</th><td>12.8 GB</td></tr>
  </table>
  
  <h4>Child Processes</h4>
  <div class="child-process-list">
    <div class="child-process-item">
      <span>Worker 1 - PID: 45679</span>
      <span>CPU: 89.2% | Mem: 756 MB</span>
    </div>
    <div class="child-process-item">
      <span>Worker 2 - PID: 45680</span>
      <span>CPU: 91.1% | Mem: 812 MB</span>
    </div>
    <div class="child-process-item">
      <span>Worker 3 - PID: 45681</span>
      <span>CPU: 87.5% | Mem: 798 MB</span>
    </div>
    <!-- ... more workers ... -->
    <div class="child-process-item">
      <span>Worker 16 - PID: 45694</span>
      <span>CPU: 88.9% | Mem: 765 MB</span>
    </div>
  </div>
  
  <h4>Subtask Progress</h4>
  <table class="subtask-table">
    <thead>
      <tr>
        <th>#</th>
        <th>Subtask Name</th>
        <th>Status</th>
        <th>Progress</th>
        <th>Items</th>
        <th>Message</th>
        <th>Duration</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>1</td>
        <td>Load source data</td>
        <td><span class="badge bg-success">COMPLETED</span></td>
        <td>100.0%</td>
        <td>56 / 56</td>
        <td>All counties loaded</td>
        <td>02:15</td>
      </tr>
      <tr>
        <td>2</td>
        <td>Transform geometries</td>
        <td><span class="badge bg-warning">RUNNING</span></td>
        <td>62.5%</td>
        <td>35 / 56</td>
        <td>Processing county 01035</td>
        <td>03:27</td>
      </tr>
      <tr>
        <td>3</td>
        <td>Write to database</td>
        <td><span class="badge bg-secondary">NOT_STARTED</span></td>
        <td>0.0%</td>
        <td>0 / 1</td>
        <td></td>
        <td>-</td>
      </tr>
    </tbody>
  </table>
</div>

<!-- Expanded Log Viewer Pane -->
<div id="log_pane_STATIC_Load_Census_Blocks" class="task-subpane log-pane" style="display: block;">
  <div class="log-controls-container">
    <div class="log-controls">
      <select id="log_lines_STATIC_Load_Census_Blocks" class="form-control form-control-sm">
        <option value="50">50 lines</option>
        <option value="100" selected>100 lines</option>
        <option value="250">250 lines</option>
        <option value="500">500 lines</option>
      </select>
      <label>
        <input type="checkbox" id="log_tail_STATIC_Load_Census_Blocks" checked> Tail mode
      </label>
      <label>
        <input type="checkbox" id="log_auto_refresh_STATIC_Load_Census_Blocks" checked> Auto-refresh
      </label>
      <input type="text" id="log_filter_STATIC_Load_Census_Blocks" 
             placeholder="Filter/search..." class="form-control form-control-sm">
      <button class="btn btn-sm btn-primary">Refresh</button>
      <small style="margin-left: auto;"><strong>File:</strong> STATIC_02_Census_Blocks.Rout</small>
      <small><strong>Lines:</strong> 3,482 (last 100 shown)</small>
      <small><strong>Updated:</strong> 14:36:04</small>
    </div>
  </div>
  
  <div class="log-content-container">
    <div class="log-scroll-indicator">📍 Tail Mode - Auto-scrolling</div>
    <div class="log-output-pane" id="log_output_STATIC_Load_Census_Blocks">
      <div class="log-line">2026-01-04 14:30:22 INFO: Starting census block load</div>
      <div class="log-line">2026-01-04 14:30:23 INFO: Connecting to database</div>
      <div class="log-line">2026-01-04 14:30:24 INFO: Found 56 counties to process</div>
      <div class="log-line log-line-warning">2026-01-04 14:32:15 WARNING: County 01003 has partial data</div>
      <div class="log-line">2026-01-04 14:33:42 INFO: Completed county 01001</div>
      <div class="log-line">2026-01-04 14:34:18 INFO: Completed county 01003</div>
      <div class="log-line">2026-01-04 14:35:22 INFO: Processing county 01035 (35/56)</div>
      <!-- ... more log lines ... -->
    </div>
  </div>
</div>
```

### Example: Task with Dead Process (ERROR State)

```html
<div class="task-row" data-task-id="ANNUAL_SEPT_03_Road_Lengths">
  <div class="task-toggle-buttons">
    <button class="btn-expand-process expanded">
      <i class="fa fa-chevron-right"></i> <!-- Rotated down -->
    </button>
    <button class="btn-expand-log">📄</button> <!-- Not expanded, gray background -->
  </div>
  <div class="task-name">ANNUAL_SEPT_03 Road Lengths</div>
  <div class="task-status-badge">
    <span class="badge bg-danger">ERROR</span>
  </div>
  <div class="task-progress-container">
    <!-- Progress bars showing partial completion -->
  </div>
  <div class="task-message">Process terminated unexpectedly</div>
  <button class="btn btn-sm btn-warning">Reset</button>
</div>

<!-- Process pane showing error -->
<div class="task-subpane process-pane">
  <div class="process-error-warning">
    <strong>⚠ Process Not Found</strong><br>
    Task is marked as RUNNING but process PID 23456 is no longer active.
    The process may have crashed or been terminated.
  </div>
  
  <h4>Last Known Process Information</h4>
  <table class="process-info-table">
    <tr><th>Run ID:</th><td>xyz-789-abc-def</td></tr>
    <tr><th>Hostname:</th><td>server.example.com</td></tr>
    <tr><th>Main PID:</th><td>23456 ✗ (Not Found)</td></tr>
    <tr><th>Status:</th><td><span class="badge bg-danger">ERROR</span> (was RUNNING)</td></tr>
    <tr><th>Started:</th><td>2026-01-04 10:15:30</td></tr>
    <tr><th>Last Update:</th><td>2026-01-04 12:42:18</td></tr>
  </table>
  
  <h4>Subtask Progress (Last Known State)</h4>
  <table class="subtask-table">
    <tbody>
      <tr>
        <td>1</td>
        <td>Load counties</td>
        <td><span class="badge bg-success">COMPLETED</span></td>
        <td>100.0%</td>
        <td>56 / 56</td>
        <td>All loaded</td>
        <td>00:45</td>
      </tr>
      <tr>
        <td>2</td>
        <td>Process roads</td>
        <td><span class="badge bg-danger">FAILED</span></td>
        <td>32.1%</td>
        <td>18 / 56</td>
        <td>Process died at county 01019</td>
        <td>01:57</td>
      </tr>
    </tbody>
  </table>
</div>
```

---

**End of Design Document**
