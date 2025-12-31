# Enhanced Server Function with Dual Progress Bars and Integrated Task Details
# Implements features from SHINY_ENHANCEMENTS_SUMMARY.md

library(shiny)
library(DT)
library(tasker)
library(dplyr)

# Helper function: Create enhanced task row with dual progress bars
create_enhanced_task_row <- function(task, subtask_info) {
  task_status <- task$status
  task_progress <- if (!is.na(task$overall_percent_complete)) task$overall_percent_complete else 0
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

# Helper function: Create log output with correct file paths
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

# Main server function
server <- function(input, output, session) {
  
  # Reactive data for stages and tasks
  stage_data <- reactive({
    invalidateLater(if (input$auto_refresh) input$refresh_seconds * 1000 else NULL)
    
    tryCatch({
      tasker::get_stages()
    }, error = function(e) {
      message("Error getting stages: ", e$message)
      NULL
    })
  })
  
  task_data <- reactive({
    invalidateLater(if (input$auto_refresh) input$refresh_seconds * 1000 else NULL)
    
    tryCatch({
      tasker::get_active_tasks()
    }, error = function(e) {
      message("Error getting tasks: ", e$message)  
      NULL
    })
  })
  
  # Manual refresh trigger
  observeEvent(input$refresh_now, {
    stage_data()
    task_data()
  })
  
  # Update stage filter choices
  observe({
    stages <- stage_data()
    if (!is.null(stages) && nrow(stages) > 0) {
      choices <- c("all" = "all")
      choices <- c(choices, setNames(stages$stage_name, stages$stage_name))
      updateSelectInput(session, "stage_filter", choices = choices, 
                       selected = input$stage_filter)
    }
  })
  
  # Main pipeline status UI with dual progress bars
  output$pipeline_status_ui <- renderUI({
    stages <- stage_data()
    tasks <- task_data()
    
    if (is.null(stages) || nrow(stages) == 0) {
      return(div(class = "no-data", 
                h3("No pipeline data available"),
                p("Check your database connection and configuration.")))
    }
    
    # Filter stages if specified
    if (input$stage_filter != "all") {
      stages <- stages[stages$stage_name == input$stage_filter, , drop = FALSE]
    }
    
    # Create stage sections with enhanced task rows
    stage_sections <- lapply(seq_len(nrow(stages)), function(i) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      
      # Get tasks for this stage
      stage_tasks <- if (!is.null(tasks) && nrow(tasks) > 0) {
        stage_task_subset <- tasks[tasks$stage_name == stage_name, , drop = FALSE]
        
        # Filter by status if specified
        if (input$status_filter != "all") {
          stage_task_subset <- stage_task_subset[stage_task_subset$status == input$status_filter, , drop = FALSE]
        }
        
        stage_task_subset
      } else {
        data.frame()
      }
      
      # Calculate stage statistics
      total_tasks <- nrow(stage_tasks)
      if (total_tasks > 0) {
        completed_tasks <- sum(stage_tasks$status == "COMPLETED", na.rm = TRUE)
        running_tasks <- sum(stage_tasks$status == "RUNNING", na.rm = TRUE)
        failed_tasks <- sum(stage_tasks$status == "FAILED", na.rm = TRUE)
        started_tasks <- sum(stage_tasks$status == "STARTED", na.rm = TRUE)
        
        # Determine stage status
        if (failed_tasks > 0) {
          stage_status <- "FAILED"
        } else if (running_tasks > 0) {
          stage_status <- "RUNNING"
        } else if (started_tasks > 0) {
          stage_status <- "STARTED"
        } else if (completed_tasks == total_tasks) {
          stage_status <- "COMPLETED"
        } else {
          stage_status <- "NOT_STARTED"
        }
        
        stage_progress <- if (total_tasks > 0) {
          round(100 * completed_tasks / total_tasks, 1)
        } else {
          0
        }
      } else {
        stage_status <- "NOT_STARTED"
        stage_progress <- 0
        completed_tasks <- 0
        running_tasks <- 0
        failed_tasks <- 0
        started_tasks <- 0
      }
      
      # Create enhanced task rows with dual progress bars and integrated details
      task_rows <- if (total_tasks > 0) {
        lapply(seq_len(nrow(stage_tasks)), function(j) {
          task <- stage_tasks[j, ]
          
          # Get subtask info for this task (for item progress calculation)
          subtask_info <- tryCatch({
            if (!is.na(task$run_id)) {
              tasker::get_subtask_progress(task$run_id)
            } else {
              NULL
            }
          }, error = function(e) {
            message("Error getting subtasks for ", task$run_id, ": ", e$message)
            NULL
          })
          
          # Use the enhanced task row creation function
          create_enhanced_task_row(task, subtask_info)
        })
      } else {
        list(div(class = "no-tasks", "No tasks available"))
      }
      
      # Stage container with expandable task list
      div(class = "stage-container",
          # Stage header with progress bar
          div(class = paste("stage-header", paste0("status-", stage_status)),
              div(class = "stage-header-content",
                  h3(stage_name),
                  tags$span(class = paste("stage-status-badge", paste0("status-", stage_status)),
                           stage_status),
                  div(class = "stage-progress",
                      div(class = paste("stage-progress-fill", paste0("status-", stage_status)),
                          style = sprintf("width: %.1f%%", stage_progress),
                          sprintf("%.1f%%", stage_progress))
                  ),
                  div(class = "stage-stats",
                      sprintf("%d/%d", completed_tasks, total_tasks))
              ),
              tags$span(class = "stage-toggle", "▼")
          ),
          
          # Stage tasks with enhanced dual progress display
          div(class = "stage-tasks",
              id = paste0("stage_", gsub("[^a-zA-Z0-9]", "_", stage_name)),
              task_rows
          )
      )
    })
    
    div(class = "pipeline-content", stage_sections)
  })
  
  # Create log outputs for all tasks with log files (live log viewing)
  observe({
    tasks <- task_data()
    if (!is.null(tasks) && nrow(tasks) > 0) {
      tasks_with_logs <- tasks[
        !is.na(tasks$log_path) & 
        !is.na(tasks$log_filename) & 
        !is.na(tasks$run_id), 
        , drop = FALSE
      ]
      
      if (nrow(tasks_with_logs) > 0) {
        for (i in seq_len(nrow(tasks_with_logs))) {
          task <- tasks_with_logs[i, ]
          create_log_output(task$run_id, task, input, output)
        }
      }
    }
  })
  
  # Error display
  output$error_display <- renderText({
    ""  # No errors to display currently
  })
  
  # Last update timestamp
  output$last_update <- renderText({
    format(Sys.time(), "%H:%M:%S EST")
  })
}