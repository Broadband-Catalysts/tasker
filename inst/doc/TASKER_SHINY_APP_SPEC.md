# tasker Shiny Monitoring App - Specification

**Date:** 2025-12-21  
**Purpose:** Detailed specification for the tasker package Shiny monitoring dashboard

---

## Overview

The `tasker` Shiny app provides a real-time, interactive dashboard for monitoring task execution across all pipeline stages. It features expandable task details with live log tailing for running tasks and static log viewing for completed/failed tasks.

---

## Table of Contents

1. [UI Layout](#ui-layout)
2. [Main Dashboard View](#main-dashboard-view)
3. [Task Details Modal](#task-details-modal)
4. [Log Display Features](#log-display-features)
5. [Server Logic](#server-logic)
6. [Database Queries](#database-queries)
7. [Implementation Code](#implementation-code)

---

## UI Layout

### Page Structure

```
┌─────────────────────────────────────────────────────────────┐
│  tasker Pipeline Monitor                    [Refresh: 10s ▼] │
├─────────────────────────────────────────────────────────────┤
│  Stage: [All ▼]  Status: [All ▼]  [Refresh Now]             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ PREREQ (2 tasks)                                       │  │
│  │  ✓ Install System Dependencies - COMPLETED  [Details] │  │
│  │  ✓ Install R - COMPLETED                    [Details] │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ DAILY (8 tasks)                                        │  │
│  │  ⟳ DAILY_01_BDC_Locations.R - RUNNING       [Details] │  │
│  │    [████████████░░░░░░░░░░░░░░░░] 42% (24/56)         │  │
│  │    Subtask: "Processing Delaware" (38%)                │  │
│  │    Started: 2h 15m ago | Est. remaining: 3h 10m        │  │
│  │                                                         │  │
│  │  ● DAILY_02_Provider_Tables.R - NOT_STARTED [Details] │  │
│  │  ✓ DAILY_03_Combine_Data.R - COMPLETED     [Details]  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Status Icons

- **⟳** RUNNING (spinning animation)
- **✓** COMPLETED (green)
- **✗** FAILED (red)
- **●** NOT_STARTED (gray)
- **⏸** PAUSED (orange)

---

## Main Dashboard View

### Task Card Components

Each task displays:

1. **Status Icon** - Visual indicator with color coding
2. **Task Name** - Bold, clickable to open details
3. **Status Text** - Current execution status
4. **Details Button** - Opens modal with full information
5. **Progress Bar** (if running)
   - Overall progress (0-100%)
   - Subtask count (e.g., "24/56")
6. **Current Subtask** (if running)
   - Subtask name and percentage
7. **Timing Info** (if running)
   - Elapsed time
   - Estimated remaining (based on expected_duration_minutes)
8. **Last Run** (if completed/failed)
   - Timestamp of last execution

### Filters

```r
# Stage filter
selectInput("stage_filter", "Stage:",
  choices = c("All", "PREREQ", "DAILY", "MONTHLY", "ANNUAL_DEC")
)

# Status filter  
selectInput("status_filter", "Status:",
  choices = c("All", "RUNNING", "COMPLETED", "FAILED", "NOT_STARTED")
)

# Auto-refresh interval
selectInput("refresh_interval", "Refresh:",
  choices = c("5s" = 5, "10s" = 10, "30s" = 30, "1m" = 60, "Manual" = 0),
  selected = 10
)
```

---

## Task Details Modal

### Modal Structure

When "Details" button is clicked, open a modal dialog showing:

```
┌─────────────────────────────────────────────────────────────┐
│  Task Details: DAILY_01_BDC_Locations.R           [×] Close │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  OVERVIEW                                                     │
│  ├─ Task Name:     DAILY_01_BDC_Locations.R                  │
│  ├─ Stage:         DAILY                                     │
│  ├─ Type:          R                                         │
│  ├─ Status:        RUNNING                                   │
│  ├─ Description:   Load BDC location data for all states     │
│  └─ Schedule:      0 2 * * * (Daily at 2:00 AM)              │
│                                                               │
│  EXECUTION CONTEXT                                            │
│  ├─ Run ID:        550e8400-e29b-41d4-a716-446655440000      │
│  ├─ Hostname:      pipeline-server-01                        │
│  ├─ Process ID:    12345                                     │
│  ├─ User:          pipeline_user                             │
│  ├─ Started:       2025-12-21 02:00:15 (2h 15m ago)          │
│  ├─ Last Update:   2025-12-21 04:15:42 (5 sec ago)           │
│  └─ Duration:      2h 15m 27s                                │
│                                                               │
│  FILE LOCATIONS                                               │
│  ├─ Script:        /home/pipeline/scripts/DAILY/             │
│  │                 DAILY_01_BDC_Locations.R                  │
│  │                 [Open Script] [Copy Path]                 │
│  └─ Log:           /home/pipeline/logs/DAILY/                │
│                    DAILY_01_BDC_Locations.Rout               │
│                    [Download Log] [Copy Path]                │
│                                                               │
│  PROGRESS                                                     │
│  ├─ Overall:       [████████████░░░░░░░░] 42% (24/56)        │
│  │                 "Processing state location data"          │
│  └─ Subtask:       [███████████░░░░░░░░░] 38% (3/8 files)   │
│                    "Loading Delaware file"                   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ LOG OUTPUT                    [Live Tail] [Scroll ▼] │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │ [04:15:37] Loading file 3 of 8: DE_locations.csv    │    │
│  │ [04:15:38] Reading 12,543 rows...                   │    │
│  │ [04:15:39] Validating coordinates...                │    │
│  │ [04:15:40] Processing FIPS codes...                 │    │
│  │ [04:15:41] Writing to database...                   │    │
│  │ [04:15:42] ✓ Delaware processed successfully        │    │
│  │                                                      │    │
│  │ ▌ (Live - updating every 2 seconds)                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
│  RESOURCE USAGE                                               │
│  ├─ Memory:        1,248 MB                                  │
│  └─ CPU:           --                                        │
│                                                               │
│  METADATA                                                     │
│  ├─ Git Commit:    a3f5c8d                                   │
│  └─ Environment:   {"R_VERSION":"4.3.1","DB":"geodb"}        │
│                                                               │
│                                     [Close]                   │
└─────────────────────────────────────────────────────────────┘
```

### Details Modal Sections

#### 1. Overview
- Task identification
- Stage and type
- Current status
- Description (from registered_tasks)
- Schedule (cron format)

#### 2. Execution Context
- Run ID (UUID)
- Hostname
- Process ID
- User
- Timestamps (start, last update, duration)

#### 3. File Locations
- **Script path and file**
  - Full path display
  - "Open Script" button (if accessible)
  - "Copy Path" button
- **Log path and file**
  - Full path display
  - "Download Log" button
  - "Copy Path" button

#### 4. Progress
- Overall progress bar with percentage
- Overall progress message
- Subtask progress bar with percentage  
- Subtask progress message

#### 5. Log Output
- **Live tail mode** (for RUNNING tasks)
  - Auto-updates every 2 seconds
  - Shows last 20-50 lines
  - Auto-scrolls to bottom
  - "Live Tail" indicator
- **Static view** (for COMPLETED/FAILED tasks)
  - Shows last 100 lines
  - Manual scroll
  - Option to download full log

#### 6. Resource Usage
- Memory (MB)
- CPU percentage (if tracked)

#### 7. Metadata
- Git commit hash
- Environment variables (JSONB)

#### 8. Error Details (for FAILED tasks only)
- Error message
- Error detail/stack trace
- Line where failure occurred

---

## Log Display Features

### Live Log Tailing (RUNNING tasks)

```r
# Auto-updating log display
output$task_log <- renderUI({
  # Trigger reactive update
  invalidateLater(2000, session)  # Update every 2 seconds
  
  task_details <- get_execution_details(input$selected_run_id)
  
  if (task_details$execution$status == "RUNNING") {
    # Read last N lines of log
    log_path <- file.path(
      task_details$files$log_path,
      task_details$files$log_file
    )
    
    if (file.exists(log_path)) {
      log_lines <- tail(readLines(log_path, warn = FALSE), 50)
      
      # Add timestamps and formatting
      formatted_lines <- paste(log_lines, collapse = "\n")
      
      div(
        class = "log-display live",
        tags$div(
          class = "log-header",
          tags$span(class = "live-indicator", "⟳ Live"),
          tags$span(class = "log-info", 
                   sprintf("Last 50 lines | Updated: %s", 
                          format(Sys.time(), "%H:%M:%S")))
        ),
        tags$pre(
          class = "log-content",
          id = "log-content-live",
          formatted_lines
        ),
        tags$script("
          // Auto-scroll to bottom
          var logDiv = document.getElementById('log-content-live');
          logDiv.scrollTop = logDiv.scrollHeight;
        ")
      )
    } else {
      div(class = "log-error", 
          "Log file not found: ", log_path)
    }
  }
})
```

### Static Log View (COMPLETED/FAILED tasks)

```r
output$task_log_static <- renderUI({
  task_details <- get_execution_details(input$selected_run_id)
  
  log_path <- file.path(
    task_details$files$log_path,
    task_details$files$log_file
  )
  
  if (file.exists(log_path)) {
    # For failed tasks, show more context
    n_lines <- if (task_details$execution$status == "FAILED") 200 else 100
    log_lines <- tail(readLines(log_path, warn = FALSE), n_lines)
    
    # Highlight error lines
    if (task_details$execution$status == "FAILED") {
      log_lines <- highlight_errors(log_lines)
    }
    
    formatted_lines <- paste(log_lines, collapse = "\n")
    
    div(
      class = "log-display static",
      tags$div(
        class = "log-header",
        tags$span(class = "log-info", 
                 sprintf("Last %d lines | Status: %s", 
                        n_lines, task_details$execution$status)),
        downloadButton("download_log", "Download Full Log", 
                      class = "btn-sm")
      ),
      tags$pre(
        class = "log-content",
        formatted_lines
      )
    )
  } else {
    div(class = "log-error", 
        "Log file not found: ", log_path)
  }
})

# Download handler for full log
output$download_log <- downloadHandler(
  filename = function() {
    task_details <- get_execution_details(input$selected_run_id)
    task_details$files$log_file
  },
  content = function(file) {
    task_details <- get_execution_details(input$selected_run_id)
    log_path <- file.path(
      task_details$files$log_path,
      task_details$files$log_file
    )
    file.copy(log_path, file)
  }
)
```

### Error Highlighting

```r
highlight_errors <- function(log_lines) {
  # Highlight lines with errors
  error_patterns <- c(
    "Error in",
    "Error:",
    "ERROR:",
    "FAILED",
    "Exception",
    "fatal:",
    "Traceback"
  )
  
  for (pattern in error_patterns) {
    matches <- grep(pattern, log_lines, ignore.case = TRUE)
    if (length(matches) > 0) {
      log_lines[matches] <- paste0(
        '<span class="log-error-line">',
        log_lines[matches],
        '</span>'
      )
    }
  }
  
  log_lines
}
```

---

## Server Logic

### Key Reactive Values

```r
server <- function(input, output, session) {
  
  # Reactive values for state management
  rv <- reactiveValues(
    current_status = NULL,
    selected_task = NULL,
    last_refresh = Sys.time()
  )
  
  # Auto-refresh based on interval
  observe({
    interval <- as.numeric(input$refresh_interval)
    if (interval > 0) {
      invalidateLater(interval * 1000, session)
      rv$last_refresh <- Sys.time()
    }
  })
  
  # Get current status with filters
  current_status <- reactive({
    rv$last_refresh  # Trigger on refresh
    
    status <- get_current_status()
    
    # Apply filters
    if (input$stage_filter != "All") {
      status <- status[status$task_stage == input$stage_filter, ]
    }
    
    if (input$status_filter != "All") {
      status <- status[status$execution_status == input$status_filter, ]
    }
    
    status
  })
  
  # Main dashboard output
  output$dashboard <- renderUI({
    status <- current_status()
    
    # Group by stage
    stages <- unique(status$task_stage)
    
    lapply(stages, function(stage) {
      stage_tasks <- status[status$task_stage == stage, ]
      
      render_stage_section(stage, stage_tasks)
    })
  })
  
  # Details modal
  observeEvent(input$show_details, {
    rv$selected_task <- input$show_details
    
    showModal(modalDialog(
      title = sprintf("Task Details: %s", rv$selected_task),
      size = "l",
      easyClose = TRUE,
      
      render_task_details(rv$selected_task)
    ))
  })
}
```

---

## Database Queries

### Get Current Status with Full Details

```sql
SELECT 
  e.run_id,
  e.task_name,
  e.task_stage,
  e.task_type,
  e.execution_status,
  e.execution_start,
  e.execution_end,
  e.last_update,
  e.hostname,
  e.process_id,
  e.user_name,
  e.script_path,
  e.script_file,
  e.log_path,
  e.log_file,
  e.total_subtasks,
  e.current_subtask,
  e.subtask_name,
  e.subtask_status,
  e.overall_percent_complete,
  e.overall_progress_message,
  e.subtask_percent_complete,
  e.subtask_progress_message,
  e.subtask_items_total,
  e.subtask_items_complete,
  e.memory_mb,
  e.error_message,
  e.error_detail,
  e.git_commit,
  e.environment,
  t.description,
  t.schedule,
  t.expected_duration_minutes,
  EXTRACT(EPOCH FROM (NOW() - e.execution_start))/60 as elapsed_minutes,
  CASE 
    WHEN e.execution_status = 'RUNNING' AND t.expected_duration_minutes IS NOT NULL
    THEN t.expected_duration_minutes - EXTRACT(EPOCH FROM (NOW() - e.execution_start))/60
    ELSE NULL
  END as remaining_minutes
FROM tasker.executions e
LEFT JOIN tasker.tasks t ON e.task_name = t.task_name
WHERE e.execution_end IS NULL 
   OR e.execution_end > NOW() - INTERVAL '1 day'
ORDER BY e.task_stage, e.task_name;
```

---

## Implementation Code

### inst/shiny/app.R

```r
library(shiny)
library(DBI)
library(RPostgres)
library(tasker)

# UI
ui <- fluidPage(
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
  
  tags$head(
    tags$style(HTML("
      .task-card {
        border: 1px solid #ddd;
        border-radius: 5px;
        padding: 15px;
        margin-bottom: 10px;
        background: white;
      }
      
      .task-card.running {
        border-left: 4px solid #3498db;
      }
      
      .task-card.completed {
        border-left: 4px solid #2ecc71;
      }
      
      .task-card.failed {
        border-left: 4px solid #e74c3c;
      }
      
      .stage-section {
        margin-bottom: 30px;
      }
      
      .stage-header {
        background: #f8f9fa;
        padding: 10px 15px;
        border-radius: 5px;
        margin-bottom: 15px;
        font-weight: bold;
      }
      
      .log-display {
        border: 1px solid #ddd;
        border-radius: 5px;
        margin-top: 15px;
      }
      
      .log-header {
        background: #2c3e50;
        color: white;
        padding: 8px 12px;
        border-radius: 5px 5px 0 0;
        display: flex;
        justify-content: space-between;
        align-items: center;
      }
      
      .log-content {
        background: #1e1e1e;
        color: #d4d4d4;
        padding: 15px;
        margin: 0;
        max-height: 400px;
        overflow-y: auto;
        font-family: 'Courier New', monospace;
        font-size: 12px;
        border-radius: 0 0 5px 5px;
      }
      
      .live-indicator {
        color: #2ecc71;
        animation: pulse 2s infinite;
      }
      
      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.5; }
      }
      
      .log-error-line {
        color: #e74c3c;
        font-weight: bold;
      }
      
      .progress-section {
        margin: 15px 0;
      }
      
      .info-grid {
        display: grid;
        grid-template-columns: 150px 1fr;
        gap: 8px;
        margin: 10px 0;
      }
      
      .info-label {
        font-weight: bold;
        color: #666;
      }
      
      .section-header {
        font-weight: bold;
        color: #2c3e50;
        margin-top: 20px;
        margin-bottom: 10px;
        padding-bottom: 5px;
        border-bottom: 2px solid #3498db;
      }
    "))
  ),
  
  titlePanel("tasker Pipeline Monitor"),
  
  fluidRow(
    column(3,
      selectInput("stage_filter", "Stage:",
        choices = c("All", "PREREQ", "DAILY", "MONTHLY", "ANNUAL_DEC")
      )
    ),
    column(3,
      selectInput("status_filter", "Status:",
        choices = c("All", "RUNNING", "COMPLETED", "FAILED", "NOT_STARTED")
      )
    ),
    column(3,
      selectInput("refresh_interval", "Refresh:",
        choices = c("5s" = 5, "10s" = 10, "30s" = 30, "1m" = 60, "Manual" = 0),
        selected = 10
      )
    ),
    column(3,
      actionButton("manual_refresh", "Refresh Now", 
                   class = "btn-primary", 
                   style = "margin-top: 25px;")
    )
  ),
  
  hr(),
  
  uiOutput("dashboard")
)

# Server
server <- function(input, output, session) {
  
  rv <- reactiveValues(
    last_refresh = Sys.time(),
    selected_run_id = NULL
  )
  
  # Auto-refresh
  observe({
    interval <- as.numeric(input$refresh_interval)
    if (interval > 0) {
      invalidateLater(interval * 1000, session)
      rv$last_refresh <- Sys.time()
    }
  })
  
  # Manual refresh
  observeEvent(input$manual_refresh, {
    rv$last_refresh <- Sys.time()
  })
  
  # Get current status
  current_status <- reactive({
    rv$last_refresh
    
    status <- get_current_status()
    
    if (input$stage_filter != "All") {
      status <- status[status$task_stage == input$stage_filter, ]
    }
    
    if (input$status_filter != "All") {
      status <- status[status$execution_status == input$status_filter, ]
    }
    
    status
  })
  
  # Render dashboard
  output$dashboard <- renderUI({
    status <- current_status()
    
    if (nrow(status) == 0) {
      return(div(
        class = "alert alert-info",
        "No tasks found matching filters."
      ))
    }
    
    stages <- unique(status$task_stage)
    
    lapply(stages, function(stage) {
      stage_tasks <- status[status$task_stage == stage, ]
      
      div(
        class = "stage-section",
        div(
          class = "stage-header",
          sprintf("%s (%d tasks)", stage, nrow(stage_tasks))
        ),
        lapply(1:nrow(stage_tasks), function(i) {
          task <- stage_tasks[i, ]
          render_task_card(task)
        })
      )
    })
  })
  
  # Task card renderer
  render_task_card <- function(task) {
    status_class <- tolower(task$execution_status)
    status_icon <- switch(task$execution_status,
      "RUNNING" = "⟳",
      "COMPLETED" = "✓",
      "FAILED" = "✗",
      "NOT_STARTED" = "●",
      "●"
    )
    
    div(
      class = sprintf("task-card %s", status_class),
      fluidRow(
        column(9,
          h4(sprintf("%s %s", status_icon, task$task_name)),
          if (task$execution_status == "RUNNING") {
            tagList(
              div(
                class = "progress-section",
                tags$div(
                  sprintf("Overall: %d%% (%d/%d)", 
                         round(task$overall_percent_complete), 
                         task$current_subtask, 
                         task$total_subtasks),
                  tags$div(
                    class = "progress",
                    style = "height: 25px;",
                    tags$div(
                      class = "progress-bar",
                      role = "progressbar",
                      style = sprintf("width: %d%%", 
                                    round(task$overall_percent_complete)),
                      sprintf("%d%%", round(task$overall_percent_complete))
                    )
                  )
                ),
                tags$div(
                  style = "margin-top: 5px;",
                  sprintf("Subtask: %s (%d%%)", 
                         task$subtask_name,
                         round(task$subtask_percent_complete))
                )
              )
            )
          }
        ),
        column(3,
          actionButton(
            sprintf("details_%s", task$run_id),
            "Details",
            class = "btn-info btn-sm",
            style = "margin-top: 10px;",
            onclick = sprintf("Shiny.setInputValue('show_details', '%s')", 
                            task$run_id)
          )
        )
      )
    )
  }
  
  # Details modal
  observeEvent(input$show_details, {
    rv$selected_run_id <- input$show_details
    
    task_details <- get_execution_details(rv$selected_run_id)
    
    showModal(modalDialog(
      title = sprintf("Task Details: %s", task_details$task$name),
      size = "l",
      easyClose = TRUE,
      
      render_task_details_ui(task_details)
    ))
  })
  
  # Render task details
  render_task_details_ui <- function(details) {
    tagList(
      # Overview
      div(
        class = "section-header",
        "OVERVIEW"
      ),
      div(
        class = "info-grid",
        div(class = "info-label", "Task Name:"),
        div(details$task$name),
        div(class = "info-label", "Stage:"),
        div(details$task$stage),
        div(class = "info-label", "Type:"),
        div(details$task$type),
        div(class = "info-label", "Status:"),
        div(tags$span(
          class = sprintf("badge bg-%s", 
                         switch(details$execution$status,
                               "RUNNING" = "primary",
                               "COMPLETED" = "success",
                               "FAILED" = "danger",
                               "secondary")),
          details$execution$status
        ))
      ),
      
      # Execution Context
      div(
        class = "section-header",
        "EXECUTION CONTEXT"
      ),
      div(
        class = "info-grid",
        div(class = "info-label", "Run ID:"),
        div(tags$code(details$execution$run_id)),
        div(class = "info-label", "Hostname:"),
        div(details$execution$hostname),
        div(class = "info-label", "Process ID:"),
        div(details$execution$process_id),
        div(class = "info-label", "User:"),
        div(details$execution$user),
        div(class = "info-label", "Started:"),
        div(format(details$execution$start, "%Y-%m-%d %H:%M:%S")),
        div(class = "info-label", "Duration:"),
        div(format_duration(details$execution$duration_minutes))
      ),
      
      # File Locations
      div(
        class = "section-header",
        "FILE LOCATIONS"
      ),
      div(
        class = "info-grid",
        div(class = "info-label", "Script:"),
        div(
          tags$code(file.path(details$files$script_path, 
                              details$files$script_file)),
          actionButton("copy_script_path", "Copy Path", 
                      class = "btn-sm btn-outline-secondary",
                      style = "margin-left: 10px;")
        ),
        div(class = "info-label", "Log:"),
        div(
          tags$code(file.path(details$files$log_path, 
                              details$files$log_file)),
          downloadButton("download_log", "Download", 
                        class = "btn-sm"),
          actionButton("copy_log_path", "Copy Path", 
                      class = "btn-sm btn-outline-secondary")
        )
      ),
      
      # Progress
      if (!is.null(details$progress$total_subtasks)) {
        tagList(
          div(
            class = "section-header",
            "PROGRESS"
          ),
          div(
            class = "progress-section",
            div(
              sprintf("Overall: %d%% (%d/%d)", 
                     round(details$progress$overall_percent), 
                     details$progress$current_subtask, 
                     details$progress$total_subtasks)
            ),
            tags$div(
              class = "progress",
              style = "height: 25px;",
              tags$div(
                class = "progress-bar",
                role = "progressbar",
                style = sprintf("width: %d%%", 
                              round(details$progress$overall_percent)),
                sprintf("%d%%", round(details$progress$overall_percent))
              )
            ),
            if (!is.null(details$progress$subtask_percent)) {
              tagList(
                div(
                  style = "margin-top: 10px;",
                  sprintf("Subtask: %d%%", 
                         round(details$progress$subtask_percent))
                ),
                tags$div(
                  class = "progress",
                  style = "height: 20px;",
                  tags$div(
                    class = "progress-bar bg-info",
                    role = "progressbar",
                    style = sprintf("width: %d%%", 
                                  round(details$progress$subtask_percent)),
                    sprintf("%d%%", round(details$progress$subtask_percent))
                  )
                )
              )
            }
          )
        )
      },
      
      # Log Output
      div(
        class = "section-header",
        "LOG OUTPUT"
      ),
      uiOutput("task_log_display")
    )
  }
  
  # Log display (live or static)
  output$task_log_display <- renderUI({
    req(rv$selected_run_id)
    
    task_details <- get_execution_details(rv$selected_run_id)
    
    if (task_details$execution$status == "RUNNING") {
      # Live tail mode
      invalidateLater(2000, session)
      render_live_log(task_details)
    } else {
      # Static view
      render_static_log(task_details)
    }
  })
  
  # Helper function to format duration
  format_duration <- function(minutes) {
    if (is.na(minutes)) return("--")
    
    hours <- floor(minutes / 60)
    mins <- floor(minutes %% 60)
    secs <- round((minutes %% 1) * 60)
    
    if (hours > 0) {
      sprintf("%dh %dm %ds", hours, mins, secs)
    } else if (mins > 0) {
      sprintf("%dm %ds", mins, secs)
    } else {
      sprintf("%ds", secs)
    }
  }
}

# Run app
shinyApp(ui, server)
```

---

## CSS Styling

Additional CSS for polished appearance:

```css
/* Add to tags$style() in UI */

.task-card:hover {
  box-shadow: 0 2px 8px rgba(0,0,0,0.15);
  transition: box-shadow 0.3s ease;
}

.details-button {
  transition: all 0.2s ease;
}

.details-button:hover {
  transform: translateY(-2px);
}

.log-content::-webkit-scrollbar {
  width: 8px;
}

.log-content::-webkit-scrollbar-track {
  background: #2c3e50;
}

.log-content::-webkit-scrollbar-thumb {
  background: #34495e;
  border-radius: 4px;
}

.log-content::-webkit-scrollbar-thumb:hover {
  background: #4a5f7f;
}

.badge {
  padding: 5px 10px;
  border-radius: 3px;
}
```

---

## Benefits

1. **Real-time monitoring** - Auto-refresh shows live progress
2. **Detailed inspection** - Full context for each task
3. **Log access** - Direct view of logs without SSH
4. **Live tailing** - See logs update in real-time for running tasks
5. **Error debugging** - Highlighted errors in failed task logs
6. **File traceability** - Know exactly where scripts and logs are
7. **User-friendly** - Clean, intuitive interface
8. **Responsive** - Works on desktop and tablet

---

## Future Enhancements

- [ ] Log search/filter functionality
- [ ] Historical execution timeline view
- [ ] Performance charts (duration trends)
- [ ] Email/Slack notifications
- [ ] Task kill/restart buttons
- [ ] Multi-server support
- [ ] Export status reports
- [ ] Custom alerts/thresholds

---

**Status:** ✅ **Specification Complete - Ready for Implementation**
