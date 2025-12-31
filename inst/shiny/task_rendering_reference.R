# Reference Implementation: Enhanced Task Rendering with Item Progress
# This file shows the key pattern for rendering tasks with:
# 1. Dual progress bars (task + items)
# 2. Clickable rows that expand to show details
# 3. Integrated log viewer with correct file paths
# 4. Real-time updates

# Key changes needed in app.R around line 750:

# ==============================================================================
# TASK ROW RENDERING WITH ITEM PROGRESS AND INTEGRATED DETAILS
# ==============================================================================

create_enhanced_task_row <- function(task, subtask_info) {
  task_status <- task$status
  task_progress <- task$overall_percent_complete
  run_id <- task$run_id
  
  # Calculate item progress from subtask info
  items_complete <- 0
  items_total <- 0
  items_pct <- 0
  
  if (!is.null(subtask_info) && nrow(subtask_info) > 0) {
    # Find current/most recent subtask with items
    for (i in seq_len(nrow(subtask_info))) {
      st <- subtask_info[i, ]
      if (!is.na(st$items_total) && st$items_total > 0) {
        items_total <- st$items_total
        items_complete <- if (!is.na(st$items_complete)) st$items_complete else 0
        items_pct <- round(100 * items_complete / items_total, 1)
        break  # Use first subtask with items
      }
    }
  }
  
  div(class = "task-container",
      `data-task-id` = if (!is.na(run_id)) run_id else "",
      
      # Clickable task row with dual progress bars
      div(class = "task-row",
          div(class = "task-row-main",
              tags$span(class = "expand-icon", "▶"),
              div(class = "task-name", title = task$task_name, task$task_name),
              tags$span(class = paste("task-status-badge", paste0("status-", task_status)),
                       task_status),
              
              # Progress bars container
              div(class = "task-progress-bars",
                  # PRIMARY: Task progress bar
                  div(class = "progress-bar-row",
                      div(class = "progress-label", 
                          sprintf("Task: %.1f%%", task_progress)),
                      div(class = "task-progress",
                          if (task_status %in% c("RUNNING", "STARTED") && task_progress > 0) {
                            div(class = paste("task-progress-fill", paste0("status-", task_status)),
                                style = sprintf("width: %.1f%%; line-height: 18px;", task_progress),
                                sprintf("%.1f%%", task_progress))
                          } else if (task_status == "COMPLETED") {
                            div(class = "task-progress-fill status-COMPLETED",
                                style = "width: 100%; line-height: 18px;", "100%")
                          } else {
                            NULL
                          }
                      )
                  ),
                  
                  # SECONDARY: Item progress bar (only if items exist)
                  if (items_total > 0) {
                    div(class = "progress-bar-row",
                        div(class = "progress-label", 
                            sprintf("Items: %d/%d (%.1f%%)", items_complete, items_total, items_pct)),
                        div(class = "item-progress-bar",
                            div(class = "item-progress-fill",
                                style = sprintf("width: %.1f%%; line-height: 14px;", items_pct),
                                sprintf("%d/%d", items_complete, items_total))
                        )
                    )
                  }
              )
          )
      ),
      
      # Task details panel (expands on click)
      if (!is.na(run_id)) {
        div(class = "task-details-panel",
            
            # Section 1: Task Metadata
            div(class = "details-section",
                h4("Task Details"),
                tags$table(class = "details-table",
                           tags$tr(tags$td("Run ID:"), tags$td(run_id)),
                           tags$tr(tags$td("Status:"), tags$td(task_status)),
                           tags$tr(tags$td("Hostname:"), 
                                  tags$td(if (!is.na(task$hostname)) task$hostname else "N/A")),
                           tags$tr(tags$td("Started:"), 
                                  tags$td(if (!is.na(task$start_time)) 
                                            format(task$start_time, "%Y-%m-%d %H:%M:%S") else "N/A"))
                )
            ),
            
            # Section 2: Subtask Progress Table
            if (!is.null(subtask_info) && nrow(subtask_info) > 0) {
              div(class = "details-section",
                  h4("Subtask Progress"),
                  tags$table(class = "subtasks-table",
                             tags$thead(
                               tags$tr(
                                 tags$th("#"), tags$th("Name"), tags$th("Status"),
                                 tags$th("Progress"), tags$th("Items")
                               )
                             ),
                             tags$tbody(
                               lapply(seq_len(nrow(subtask_info)), function(k) {
                                 st <- subtask_info[k, ]
                                 items_str <- if (!is.na(st$items_total) && st$items_total > 0) {
                                   sprintf("%d / %d", 
                                          if (!is.na(st$items_complete)) st$items_complete else 0,
                                          st$items_total)
                                 } else "--"
                                 
                                 tags$tr(
                                   tags$td(st$subtask_number),
                                   tags$td(st$subtask_name),
                                   tags$td(st$status),
                                   tags$td(if (!is.na(st$percent_complete)) 
                                             sprintf("%.1f%%", st$percent_complete) else "--"),
                                   tags$td(items_str)
                                 )
                               })
                             )
                  )
              )
            },
            
            # Section 3: Live Log Viewer
            # CRITICAL: Use correct log file path from database
            if (!is.na(task$log_path) && !is.na(task$log_filename)) {
              # Create unique IDs for this task's log viewer
              log_id <- gsub("[^a-zA-Z0-9]", "_", run_id)
              
              div(class = "details-section",
                  h4("Log File"),
                  div(class = "log-viewer-controls",
                      checkboxInput(
                        paste0("log_auto_", log_id), 
                        "Auto-refresh", 
                        value = task_status %in% c("RUNNING", "STARTED")
                      ),
                      numericInput(
                        paste0("log_lines_", log_id), 
                        "Lines:", 
                        value = 100, min = 10, max = 1000, step = 50, 
                        width = "120px"
                      ),
                      actionButton(
                        paste0("log_refresh_", log_id),
                        "Refresh", 
                        class = "btn-sm btn-primary"
                      )
                  ),
                  div(class = "log-output",
                      id = paste0("log_output_", log_id),
                      uiOutput(paste0("log_content_", log_id))
                  )
              )
            }
        )
      }
  )
}

# ==============================================================================
# LOG CONTENT RENDERING (Server-side)
# ==============================================================================

# For each task with a log file, create a reactive output
# This should be in the server function:

create_log_output <- function(run_id, task, input, output) {
  log_id <- gsub("[^a-zA-Z0-9]", "_", run_id)
  
  output[[paste0("log_content_", log_id)]] <- renderUI({
    # Trigger on refresh button
    input[[paste0("log_refresh_", log_id)]]
    
    # Auto-refresh if enabled
    if (!is.null(input[[paste0("log_auto_", log_id)]]) && 
        input[[paste0("log_auto_", log_id)]]) {
      invalidateLater(3000)  # Refresh every 3 seconds
    }
    
    tryCatch({
      # CORRECT LOG FILE PATH: Use log_path + log_filename from database
      log_file <- file.path(task$log_path, task$log_filename)
      
      if (!file.exists(log_file)) {
        return(HTML(paste0(
          "<div class='log-line log-line-warning'>Log file not found: ",
          htmltools::htmlEscape(log_file), "</div>"
        )))
      }
      
      # Read log lines
      num_lines <- if (!is.null(input[[paste0("log_lines_", log_id)]])) {
        input[[paste0("log_lines_", log_id)]]
      } else {
        100
      }
      
      # Tail mode: read last N lines
      all_lines <- readLines(log_file, warn = FALSE)
      total_lines <- length(all_lines)
      start_line <- max(1, total_lines - num_lines + 1)
      lines <- all_lines[start_line:total_lines]
      
      if (length(lines) == 0) {
        return(HTML("<div class='log-line'>Log file is empty</div>"))
      }
      
      # Format lines with syntax highlighting
      formatted_lines <- sapply(lines, function(line) {
        line <- htmltools::htmlEscape(line)
        
        class_attr <- ""
        if (grepl("ERROR|Error|error|FAIL|Failed|failed", line)) {
          class_attr <- " log-line-error"
        } else if (grepl("WARN|Warning|warning", line)) {
          class_attr <- " log-line-warning"
        } else if (grepl("INFO|Info", line)) {
          class_attr <- " log-line-info"
        }
        
        paste0("<div class='log-line", class_attr, "'>", line, "</div>")
      })
      
      # Header with file info
      header <- paste0(
        "<div class='log-line log-line-info'>",
        "File: ", htmltools::htmlEscape(log_file), 
        " | Lines: ", length(lines), " of ", total_lines,
        " | Updated: ", format(Sys.time(), "%H:%M:%S"),
        "</div><div class='log-line'>", paste(rep("─", 70), collapse=""), "</div>"
      )
      
      HTML(paste0(header, paste(formatted_lines, collapse = "")))
      
    }, error = function(e) {
      HTML(paste0(
        "<div class='log-line log-line-error'>Error reading log: ",
        htmltools::htmlEscape(e$message), "</div>"
      ))
    })
  })
}

# ==============================================================================
# INTEGRATION INSTRUCTIONS
# ==============================================================================

# 1. Replace task row rendering logic (around line 750-850) with create_enhanced_task_row()
# 2. In server function, after creating pipeline_status_ui output, add log output creation:
#    - Loop through all tasks with log files
#    - Call create_log_output() for each to set up reactive log viewers
# 3. Remove all server logic for removed tabs (Task Details, Stage Summary, Timeline, Log Viewer)
# 4. Test with a running pipeline to verify:
#    - Item progress bars appear when items_total > 0
#    - Task rows expand/collapse on click
#    - Log viewer shows correct file path
#    - Auto-refresh works for active tasks
