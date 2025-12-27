library(shiny)
library(DT)
library(tasker)
library(dplyr)

# Configuration should already be loaded by run_monitor()
# Just verify it's available
if (is.null(getOption("tasker.config"))) {
  stop("Tasker configuration not loaded. Please run this app via tasker::run_monitor()")
}

ui <- fluidPage(
  titlePanel({
    config <- getOption("tasker.config")
    pipeline_name <- if (!is.null(config$pipeline$name)) config$pipeline$name else "Pipeline"
    paste(pipeline_name, "- Tasker Monitor")
  }),
  
  tags$head(
    tags$style(HTML("
      .status-NOT_STARTED { background-color: #f0f0f0; }
      .status-STARTED { background-color: #fff3cd; }
      .status-RUNNING { background-color: #cfe2ff; }
      .status-COMPLETED { background-color: #d1e7dd; }
      .status-FAILED { background-color: #f8d7da; }
      .status-SKIPPED { background-color: #e2e3e5; }
      .detail-box { 
        border: 1px solid #ddd; 
        padding: 10px; 
        margin: 10px 0; 
        background-color: #f9f9f9; 
      }
      .log-output {
        font-family: monospace;
        background-color: #000;
        color: #0f0;
        padding: 10px;
        max-height: 400px;
        overflow-y: auto;
        white-space: pre-wrap;
      }
      /* Pipeline Status Tab Styles */
      .pipeline-status-container {
        padding: 15px;
      }
      .stage-panel {
        margin-bottom: 15px;
        border: 1px solid #ddd;
        border-radius: 4px;
        background: #fff;
      }
      .stage-header {
        padding: 12px 15px;
        background: #f8f9fa;
        border-bottom: 1px solid #ddd;
        cursor: pointer;
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .stage-header:hover {
        background: #e9ecef;
      }
      .stage-name {
        font-weight: 600;
        font-size: 16px;
        flex: 0 0 auto;
        min-width: 120px;
      }
      .stage-badge {
        padding: 3px 8px;
        border-radius: 3px;
        font-size: 11px;
        font-weight: 600;
        text-transform: uppercase;
        flex: 0 0 auto;
      }
      .stage-badge.status-NOT_STARTED { background: #6c757d; color: white; }
      .stage-badge.status-STARTED { background: #ffc107; color: black; }
      .stage-badge.status-RUNNING { background: #0d6efd; color: white; }
      .stage-badge.status-COMPLETED { background: #198754; color: white; }
      .stage-badge.status-FAILED { background: #dc3545; color: white; }
      .stage-progress {
        flex: 1;
        height: 20px;
        background: #e9ecef;
        border-radius: 3px;
        overflow: hidden;
        position: relative;
      }
      .stage-progress-fill {
        height: 100%;
        transition: width 0.3s ease;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 11px;
        font-weight: 600;
        color: white;
      }
      .stage-progress-fill.status-NOT_STARTED { background: #adb5bd; }
      .stage-progress-fill.status-STARTED { background: #ffc107; }
      .stage-progress-fill.status-RUNNING { background: #0dcaf0; }
      .stage-progress-fill.status-COMPLETED { background: #20c997; }
      .stage-progress-fill.status-FAILED { background: #dc3545; }
      .stage-count {
        font-size: 13px;
        color: #666;
        flex: 0 0 auto;
        min-width: 60px;
        text-align: right;
      }
      .stage-body {
        padding: 10px 15px;
        display: none;
      }
      .stage-body.expanded {
        display: block;
      }
      .task-row {
        padding: 8px 10px;
        margin: 5px 0;
        background: #f8f9fa;
        border-radius: 3px;
        display: flex;
        align-items: center;
        gap: 10px;
        font-size: 14px;
      }
      .task-name {
        flex: 1;
        font-weight: 500;
      }
      .task-status-badge {
        padding: 2px 6px;
        border-radius: 2px;
        font-size: 10px;
        font-weight: 600;
        text-transform: uppercase;
        flex: 0 0 auto;
      }
      .task-status-badge.status-NOT_STARTED { background: #6c757d; color: white; }
      .task-status-badge.status-STARTED { background: #ffc107; color: black; }
      .task-status-badge.status-RUNNING { background: #0d6efd; color: white; }
      .task-status-badge.status-COMPLETED { background: #198754; color: white; }
      .task-status-badge.status-FAILED { background: #dc3545; color: white; }
      .task-progress {
        flex: 0 0 150px;
        height: 16px;
        background: #e9ecef;
        border-radius: 2px;
        overflow: hidden;
        position: relative;
      }
      .task-progress-fill {
        height: 100%;
        transition: width 0.3s ease;
        font-size: 10px;
        font-weight: 600;
        color: white;
        text-align: center;
        line-height: 16px;
      }
      .task-progress-fill.status-STARTED { background: #ffc107; }
      .task-progress-fill.status-RUNNING { background: #0dcaf0; }
      .task-progress-fill.status-COMPLETED { background: #20c997; }
      .task-message {
        flex: 0 0 200px;
        font-size: 12px;
        color: #666;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    "))
  ),
  
  tags$script(HTML("
    $(document).on('click', '.stage-header', function() {
      var stageBody = $(this).next('.stage-body');
      stageBody.toggleClass('expanded');
      
      // Get all currently expanded stage names
      var expanded = [];
      $('.stage-body.expanded').each(function() {
        var stageName = $(this).prev('.stage-header').find('.stage-name').text();
        expanded.push(stageName);
      });
      
      // Send to Shiny
      Shiny.setInputValue('expanded_stages', expanded, {priority: 'event'});
    });
  ")),
  
  tags$script(HTML("
    // After UI updates, restore expanded state
    $(document).on('shiny:value', function(event) {
      if (event.name === 'pipeline_status_ui') {
        setTimeout(function() {
          if (typeof Shiny !== 'undefined' && Shiny.inputBindings) {
            var expanded = Shiny.shinyapp.$inputValues.expanded_stages;
            if (expanded) {
              expanded.forEach(function(stageName) {
                $('.stage-name').filter(function() {
                  return $(this).text() === stageName;
                }).parent('.stage-header').next('.stage-body').addClass('expanded');
              });
            }
          }
        }, 50);
      }
    });
  ")),
  
  sidebarLayout(
    sidebarPanel(
      width = 2,
      selectInput("stage_filter", "Filter by Stage:", 
                  choices = c("All" = ""), multiple = TRUE),
      selectInput("status_filter", "Filter by Status:",
                  choices = c("All" = "", "NOT_STARTED", "STARTED", "RUNNING", 
                             "COMPLETED", "FAILED", "SKIPPED"),
                  multiple = TRUE),
      numericInput("refresh_interval", "Auto-refresh (seconds):", 
                   value = 5, min = 1, max = 60),
      checkboxInput("auto_refresh", "Auto-refresh", value = TRUE),
      hr(),
      actionButton("refresh", "Refresh Now", class = "btn-primary"),
      hr(),
      textOutput("last_update")
    ),
    
    mainPanel(
      width = 10,
      tabsetPanel(
        id = "main_tabs",
        tabPanel("Pipeline Status",
                 div(class = "pipeline-status-container",
                     uiOutput("pipeline_status_ui")
                 )
        ),
        tabPanel("Task Details",
                 DTOutput("task_table"),
                 hr(),
                 uiOutput("detail_panel")
        ),
        tabPanel("Stage Summary",
                 plotOutput("stage_progress_plot"),
                 hr(),
                 DTOutput("stage_summary_table")
        ),
        tabPanel("Timeline",
                 plotOutput("timeline_plot", height = "900px")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  
  # Reactive values
  rv <- reactiveValues(
    selected_task_id = NULL,
    last_update = NULL,
    expanded_stages = c()  # Track which stage accordions are expanded
  )
  
  # Track expanded stages from client-side JavaScript
  observeEvent(input$expanded_stages, {
    rv$expanded_stages <- input$expanded_stages
  }, ignoreNULL = FALSE)
  
  # Auto-refresh timer
  autoRefresh <- reactive({
    if (input$auto_refresh) {
      invalidateLater(input$refresh_interval * 1000)
    }
    input$refresh
  })
  
  # Fetch task data
  task_data <- reactive({
    autoRefresh()
    
    tryCatch({
      data <- tasker::get_task_status()
      rv$last_update <- Sys.time()
      
      # Apply filters
      if (!is.null(data) && nrow(data) > 0) {
        # Filter by stage (exclude empty string which means "All")
        stage_filters <- input$stage_filter[input$stage_filter != ""]
        if (length(stage_filters) > 0) {
          data <- data |> filter(stage_name %in% stage_filters)
        }
        # Filter by status (exclude empty string which means "All")
        status_filters <- input$status_filter[input$status_filter != ""]
        if (length(status_filters) > 0) {
          data <- data |> filter(status %in% status_filters)
        }
      }
      
      data
    }, error = function(e) {
      showNotification(paste("Error fetching data:", e$message), type = "error")
      NULL
    })
  })
  
  # Update stage filter choices dynamically from stages table
  observe({
    stages_data <- tryCatch({
      stages_data_raw <- tasker::get_stages()
      # Exclude TEST stage
      if (!is.null(stages_data_raw) && nrow(stages_data_raw) > 0) {
        stages_data_raw[stages_data_raw$stage_name != "TEST" & stages_data_raw$stage_order != 999, ]
      } else {
        stages_data_raw
      }
    }, error = function(e) NULL)
    
    if (!is.null(stages_data) && nrow(stages_data) > 0) {
      stage_values <- stages_data$stage_name
      names(stage_values) <- paste(stages_data$stage_order, ': ', stages_data$stage_name, sep = '')

      # Keep current selection if still valid
      current_selection <- input$stage_filter
      valid_selection <- current_selection[current_selection %in% stage_values]
      
      updateSelectInput(session, "stage_filter", 
                        choices = c("All" = "", stage_values),
                        selected = valid_selection)
    }
  })
  
  # Pipeline Status Tab - shows all stages and tasks
  output$pipeline_status_ui <- renderUI({
    autoRefresh()  # Trigger on refresh
    
    # Get all stages and tasks
    stages_data <- tryCatch({
      stages_data_raw <- tasker::get_stages()
      # Exclude TEST stage
      if (!is.null(stages_data_raw) && nrow(stages_data_raw) > 0) {
        stages_data_raw[stages_data_raw$stage_name != "TEST" & stages_data_raw$stage_order != 999, ]
      } else {
        stages_data_raw
      }
    }, error = function(e) NULL)
    
    if (is.null(stages_data) || nrow(stages_data) == 0) {
      return(div(class = "alert alert-info", "No stages configured"))
    }
    
    # Get all registered tasks (shows everything that's been registered)
    registered_tasks <- tryCatch({
      tasker::get_registered_tasks()
    }, error = function(e) NULL)
    
    if (is.null(registered_tasks) || nrow(registered_tasks) == 0) {
      return(div(class = "alert alert-info", "No tasks registered"))
    }
    
    # Get task execution status (only for tasks that have been run)
    task_status <- tryCatch({
      tasker::get_task_status()
    }, error = function(e) NULL)
    
    # Merge registered tasks with their status
    # Left join to keep all registered tasks even if they haven't run
    if (!is.null(task_status) && nrow(task_status) > 0) {
      all_tasks <- merge(
        registered_tasks,
        task_status,
        by.x = c("stage_name", "task_name"),
        by.y = c("stage_name", "task_name"),
        all.x = TRUE
      )
      # Fill in missing status fields
      all_tasks$status <- ifelse(is.na(all_tasks$status), "NOT_STARTED", all_tasks$status)
      all_tasks$overall_percent_complete <- ifelse(is.na(all_tasks$overall_percent_complete), 0, all_tasks$overall_percent_complete)
      all_tasks$overall_progress_message <- ifelse(is.na(all_tasks$overall_progress_message), "", all_tasks$overall_progress_message)
    } else {
      # No tasks have been run yet
      all_tasks <- registered_tasks
      all_tasks$status <- "NOT_STARTED"
      all_tasks$overall_percent_complete <- 0
      all_tasks$overall_progress_message <- ""
    }
    
    # Add stage_order from stages_data for proper ordering
    all_tasks <- merge(
      all_tasks,
      stages_data[, c("stage_name", "stage_order")],
      by = "stage_name",
      all.x = TRUE
    )
    
    # Ensure stages_data is ordered by stage_order
    stages_data <- stages_data[order(stages_data$stage_order), ]
    
    # Create stage panels
    stage_panels <- lapply(seq_len(nrow(stages_data)), function(i) {
      stage <- stages_data[i, ]
      stage_name <- stage$stage_name
      
      # Get tasks for this stage
      stage_tasks <- if (!is.null(all_tasks)) {
        tasks <- all_tasks[all_tasks$stage_name == stage_name, ]
        # Sort by task_order for consistent display
        if (nrow(tasks) > 0 && "task_order" %in% names(tasks)) {
          tasks <- tasks[order(tasks$task_order), ]
        }
        tasks
      } else {
        data.frame()
      }
      
      # Calculate stage stats
      total_tasks <- nrow(stage_tasks)
      if (total_tasks == 0) {
        stage_status <- "NOT_STARTED"
        completed_tasks <- 0
        progress_pct <- 0
      } else {
        completed_tasks <- sum(stage_tasks$status == "COMPLETED", na.rm = TRUE)
        running_tasks <- sum(stage_tasks$status == "RUNNING", na.rm = TRUE)
        started_tasks <- sum(stage_tasks$status == "STARTED", na.rm = TRUE)
        failed_tasks <- sum(stage_tasks$status == "FAILED", na.rm = TRUE)
        
        progress_pct <- round(100 * completed_tasks / total_tasks)
        
        # Stage status priority (highest to lowest):
        # 1. FAILED - if any task has failed
        # 2. RUNNING - if any task is currently running
        # 3. STARTED - if any task has started but not running
        # 4. COMPLETED - if all tasks are completed
        # 5. NOT_STARTED - if no tasks have started
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
      }
      
      # Create task rows
      task_rows <- if (total_tasks > 0) {
        lapply(seq_len(nrow(stage_tasks)), function(j) {
          task <- stage_tasks[j, ]
          task_status <- task$status
          task_progress <- task$overall_percent_complete
          
          div(class = "task-row",
              div(class = "task-name", task$task_name),
              tags$span(class = paste("task-status-badge", paste0("status-", task_status)),
                       task_status),
              if ((task_status == "RUNNING" || task_status == "STARTED") && !is.na(task_progress) && task_progress > 0) {
                div(class = "task-progress",
                    div(class = paste("task-progress-fill", paste0("status-", task_status)),
                        style = sprintf("width: %.1f%%", task_progress),
                        sprintf("%.1f%%", task_progress))
                )
              } else if (task_status == "COMPLETED") {
                div(class = "task-progress",
                    div(class = "task-progress-fill status-COMPLETED",
                        style = "width: 100%",
                        "100%")
                )
              } else {
                div(class = "task-progress")
              },
              if (!is.na(task$overall_progress_message) && task$overall_progress_message != "") {
                div(class = "task-message", 
                    title = task$overall_progress_message,
                    task$overall_progress_message)
              } else {
                div(class = "task-message")
              }
          )
        })
      } else {
        list(div(class = "alert alert-sm alert-secondary", "No tasks registered for this stage"))
      }
      
      # Create stage panel
      div(class = "stage-panel",
          div(class = "stage-header",
              div(class = "stage-name", stage_name),
              tags$span(class = paste("stage-badge", paste0("status-", stage_status)),
                       stage_status),
              div(class = "stage-progress",
                  div(class = paste("stage-progress-fill", paste0("status-", stage_status)),
                      style = sprintf("width: %d%%", progress_pct),
                      sprintf("%d%%", progress_pct))
              ),
              div(class = "stage-count",
                  sprintf("%d/%d", completed_tasks, total_tasks))
          ),
          div(class = paste("stage-body", if(stage_name %in% rv$expanded_stages) "expanded" else ""),
              task_rows
          )
      )
    })
    
    tagList(stage_panels)
  })
  
  # Main task table - initial render
  output$task_table <- renderDT({
    # Only render the initial table structure
    empty_df <- data.frame(
      Stage = character(0),
      Task = character(0),
      Status = character(0),
      Progress = character(0),
      `Overall Progress` = character(0),
      Started = character(0),
      Duration = character(0),
      Host = character(0),
      Details = character(0),
      stage_order_hidden = numeric(0),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    
    datatable(empty_df,
              escape = FALSE,
              selection = 'none',
              options = list(
                pageLength = 25,
                order = list(list(9, 'asc')),  # Order by hidden stage_order column (index 9) - task_order already included in SQL ORDER BY
                columnDefs = list(
                  list(targets = 9, visible = FALSE)  # Hide the stage_order_hidden column
                ),
                rowCallback = JS(
                  "function(row, data) {",
                  "  var status = data[2];",
                  "  $(row).addClass('status-' + status);",
                  "}"
                )
              )) %>%
      formatStyle('Status', fontWeight = 'bold')
  })
  
  # Update task table data using proxy to avoid flickering
  observe({
    data <- task_data()
    
    # Prepare display columns
    if (!is.null(data) && nrow(data) > 0) {
      # Get subtask info for running tasks
      subtask_info <- lapply(data$run_id, function(rid) {
        if (data[data$run_id == rid, "status"] %in% c("RUNNING", "STARTED")) {
          st <- tryCatch({
            subs <- tasker::get_subtask_progress(rid)
            if (!is.null(subs) && nrow(subs) > 0) {
              # Find currently running subtask or last updated one
              running <- subs[subs$status == "RUNNING", ]
              if (nrow(running) > 0) {
                running[1, ]
              } else {
                subs[order(subs$last_update, decreasing = TRUE), ][1, ]
              }
            } else {
              NULL
            }
          }, error = function(e) NULL)
          st
        } else {
          NULL
        }
      })
      
      # Build progress column with subtask info
      progress_col <- sapply(seq_len(nrow(data)), function(i) {
        st <- subtask_info[[i]]
        base_prog <- if (is.na(data$current_subtask[i])) {
          "--"
        } else {
          sprintf("%d/%d", data$current_subtask[i], data$total_subtasks[i])
        }
        
        if (!is.null(st) && !is.na(st$subtask_name)) {
          # Add subtask name and items if available
          if (!is.na(st$items_total) && st$items_total > 0) {
            items_complete <- if (!is.na(st$items_complete)) st$items_complete else 0
            sprintf("%s<br/><small>%s (%d/%d)</small>", 
                   base_prog, st$subtask_name, items_complete, st$items_total)
          } else {
            sprintf("%s<br/><small>%s</small>", base_prog, st$subtask_name)
          }
        } else {
          base_prog
        }
      })
      
      display_data <- data.frame(
        Stage    = paste(data$stage_order, ": ", data$stage_name, sep = ""),
        Task     = data$task_name,
        Status   = data$status,
        Progress = progress_col,
        "Overall Progress" = sprintf("%.1f%%", data$overall_percent_complete),
        Started  = format(data$start_time, "%Y-%m-%d %H:%M:%S"),
        Duration = format_duration(data$start_time, data$last_update),
        Host     = data$hostname,
        Details  = sprintf('<button class="btn btn-sm btn-info detail-btn" data-id="%s">View</button>', 
                         data$run_id),
        stage_order_hidden = data$stage_order,
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    } else {
      display_data <- data.frame(
        Stage = character(0),
        Task = character(0),
        Status = character(0),
        Progress = character(0),
        `Overall Progress` = character(0),
        Started = character(0),
        Duration = character(0),
        Host = character(0),
        Details = character(0),
        stage_order_hidden = numeric(0),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    }
    
    # Use proxy to update data without recreating the table
    proxy <- dataTableProxy('task_table')
    replaceData(proxy, display_data, resetPaging = FALSE, rownames = FALSE)
  })
  
  # Handle detail button clicks
  observeEvent(input$task_table_cell_clicked, {
    info <- input$task_table_cell_clicked
    if (!is.null(info$value) && grepl("detail-btn", info$value)) {
      task_id <- gsub('.*data-id="([^"]+)".*', '\\1', info$value)
      rv$selected_task_id <- task_id
    }
  })
  
  # Detail panel
  output$detail_panel <- renderUI({
    if (is.null(rv$selected_task_id)) {
      return(NULL)
    }
    
    # Get fresh data from database, not filtered data
    data <- tryCatch({
      tasker::get_task_status()
    }, error = function(e) {
      showNotification(paste("Error fetching task details:", e$message), type = "error")
      return(NULL)
    })
    
    if (is.null(data) || nrow(data) == 0) {
      return(div(class = "alert alert-warning", "No task data available"))
    }
    
    task <- data[data$run_id == rv$selected_task_id, ]
    
    if (nrow(task) == 0) {
      return(NULL)
    }
    
    # Get subtask progress details
    subtasks <- tryCatch({
      tasker::get_subtask_progress(rv$selected_task_id)
    }, error = function(e) {
      NULL
    })
    
    div(class = "detail-box",
        h3("Task Details"),
        actionButton("close_detail", "Close", class = "btn-sm btn-secondary pull-right"),
        hr(),
        fluidRow(
          column(6,
                 h4("Identification"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Run ID:"),    tags$td(task$run_id)),
                           tags$tr(tags$th("Stage:"),     tags$td(task$stage_name)),
                           tags$tr(tags$th("Task Name:"), tags$td(task$task_name)),
                           tags$tr(tags$th("Type:"),      tags$td(task$task_type)),
                           tags$tr(tags$th("Status:"),    tags$td(task$status))
                 )
          ),
          column(6,
                 h4("Execution Info"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Hostname:"),    tags$td(task$hostname)),
                           tags$tr(tags$th("PID:"),         tags$td(task$process_id)),
                           tags$tr(tags$th("Started:"),     tags$td(format(task$start_time, "%Y-%m-%d %H:%M:%S"))),
                           tags$tr(tags$th("Last Update:"), tags$td(format(task$last_update, "%Y-%m-%d %H:%M:%S"))),
                           tags$tr(tags$th("Duration:"),    tags$td(format_duration(task$start_time, task$last_update)))
                 )
          )
        ),
        fluidRow(
          column(12,
                 h4("Progress"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Overall:"), 
                                  tags$td(sprintf("%.1f%% - %s", 
                                                task$overall_percent_complete,
                                                ifelse(is.na(task$overall_progress_message), "", task$overall_progress_message)))),
                           tags$tr(tags$th("Subtasks:"), 
                                  tags$td(ifelse(is.na(task$total_subtasks), "N/A",
                                                sprintf("%s / %d", 
                                                       ifelse(is.na(task$current_subtask), "0", task$current_subtask),
                                                       task$total_subtasks))))
                 )
          )
        ),
        if (!is.null(subtasks) && nrow(subtasks) > 0) {
          fluidRow(
            column(12,
                   h4("Subtask Details"),
                   tags$table(class = "table table-sm table-striped",
                             tags$thead(
                               tags$tr(
                                 tags$th("#"),
                                 tags$th("Subtask Name"),
                                 tags$th("Status"),
                                 tags$th("Progress"),
                                 tags$th("Items"),
                                 tags$th("Message"),
                                 tags$th("Started"),
                                 tags$th("Duration")
                               )
                             ),
                             tags$tbody(
                               lapply(seq_len(nrow(subtasks)), function(i) {
                                 st <- subtasks[i, ]
                                 progress_pct <- if (!is.na(st$percent_complete)) {
                                   sprintf("%.1f%%", st$percent_complete)
                                 } else if (!is.na(st$items_total) && st$items_total > 0 && !is.na(st$items_complete)) {
                                   sprintf("%.1f%%", 100 * st$items_complete / st$items_total)
                                 } else {
                                   "--"
                                 }
                                 
                                 items_str <- if (!is.na(st$items_total) && st$items_total > 0) {
                                   complete <- if (!is.na(st$items_complete)) st$items_complete else 0
                                   sprintf("%d / %d", complete, st$items_total)
                                 } else {
                                   "--"
                                 }
                                 
                                 duration <- if (!is.na(st$start_time)) {
                                   end_time <- if (!is.na(st$end_time)) st$end_time else st$last_update
                                   if (!is.na(end_time)) {
                                     format_duration(st$start_time, end_time)
                                   } else {
                                     "--"
                                   }
                                 } else {
                                   "--"
                                 }
                                 
                                 status_class <- paste0("status-", st$status)
                                 
                                 tags$tr(
                                   tags$td(st$subtask_number),
                                   tags$td(st$subtask_name),
                                   tags$td(tags$span(class = paste("task-status-badge", status_class), st$status)),
                                   tags$td(progress_pct),
                                   tags$td(items_str),
                                   tags$td(style = "max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;",
                                          title = if (!is.na(st$progress_message)) st$progress_message else "",
                                          if (!is.na(st$progress_message)) st$progress_message else "--"),
                                   tags$td(if (!is.na(st$start_time)) format(st$start_time, "%H:%M:%S") else "--"),
                                   tags$td(duration)
                                 )
                               })
                             )
                   )
            )
          )
        },
        fluidRow(
          column(12,
                 h4("Files"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Script Path:"), tags$td(ifelse(is.na(task$script_path), "N/A", task$script_path))),
                           tags$tr(tags$th("Script File:"), tags$td(task$script_filename)),
                           tags$tr(tags$th("Log Path:"),    tags$td(task$log_path)),
                           tags$tr(tags$th("Script:"),      tags$td(ifelse(is.na(task$script_filename), "N/A", task$script_filename))),
                           tags$tr(tags$th("Log Path:"),    tags$td(ifelse(is.na(task$log_path), "N/A", task$log_path))),
                           tags$tr(tags$th("Log File:"),    tags$td(ifelse(is.na(task$log_filename), "N/A", task$log_filename)))
                 )
          )
        ),
        fluidRow(
          column(12,
                 h4("Error Message"),
                 tags$div(ifelse(is.na(task$error_message) || task$error_message == "", 
                                "No errors", task$error_message))
          )
        )
    )
  })
  
  # Close detail panel
  observeEvent(input$close_detail, {
    rv$selected_task_id <- NULL
  })
  
  # Stage summary table
  output$stage_summary_table <- renderDT({
    # Get all stages from database (exclude TEST)
    stages_data <- tryCatch({
      stages_data_raw <- tasker::get_stages()
      # Exclude TEST stage
      if (!is.null(stages_data_raw) && nrow(stages_data_raw) > 0) {
        stages_data_raw[stages_data_raw$stage_name != "TEST" & stages_data_raw$stage_order != 999, ]
      } else {
        stages_data_raw
      }
    }, error = function(e) NULL)
    
    if (is.null(stages_data) || nrow(stages_data) == 0) {
      return(datatable(data.frame(Message = "No stages configured")))
    }
    
    # Get task data
    data <- task_data()
    
    # If no task data, show all stages with zero counts
    if (is.null(data) || nrow(data) == 0) {
      summary_table <- stages_data[, c("stage_name", "stage_order")]
      summary_table$Total <- 0
      return(datatable(summary_table, options = list(
        pageLength = 10,
        order = list(list(1, 'asc'))  # Order by stage_order column
      )))
    }
    
    # Include stage_order in the aggregation
    summary <- aggregate(
      cbind(Total = run_id) ~ stage_name + stage_order + status, 
      data = data, 
      FUN = length)
    
    wide_summary <- reshape(summary, 
                           idvar = c("stage_name", "stage_order"), 
                           timevar = "status", 
                           direction = "wide")
    
    # Merge with all stages to include stages with no tasks
    all_stages_summary <- merge(
      stages_data[, c("stage_name", "stage_order")],
      wide_summary,
      by = c("stage_name", "stage_order"),
      all.x = TRUE
    )
    
    # Fill NA values with 0
    status_cols <- grep("^Total\\.", names(all_stages_summary), value = TRUE)
    for (col in status_cols) {
      all_stages_summary[[col]] <- ifelse(is.na(all_stages_summary[[col]]), 0, all_stages_summary[[col]])
    }
    
    # Order by stage_order
    all_stages_summary <- all_stages_summary[order(all_stages_summary$stage_order), ]
    
    datatable(all_stages_summary, options = list(
      pageLength = 10,
      order = list(list(1, 'asc'))  # Order by stage_order column
    ))
  })
  
  # Stage progress plot
  output$stage_progress_plot <- renderPlot({
    # Get all stages from database (exclude TEST)
    stages_data <- tryCatch({
      stages_data_raw <- tasker::get_stages()
      # Exclude TEST stage
      if (!is.null(stages_data_raw) && nrow(stages_data_raw) > 0) {
        stages_data_raw[stages_data_raw$stage_name != "TEST" & stages_data_raw$stage_order != 999, ]
      } else {
        stages_data_raw
      }
    }, error = function(e) NULL)
    
    if (is.null(stages_data) || nrow(stages_data) == 0) {
      return(NULL)
    }
    
    # Get task data
    data <- task_data()
    
    library(ggplot2)
    
    # If no task data, show all stages with 0% progress
    if (is.null(data) || nrow(data) == 0) {
      stage_progress <- stages_data[, c("stage_name", "stage_order")]
      stage_progress$overall_percent_complete <- 0
    } else {
      # Calculate progress for stages with data
      stage_progress <- aggregate(
        cbind(overall_percent_complete, stage_order) ~ stage_name, 
        data = data,
        FUN = function(x) if(length(x) > 0) mean(x, na.rm = TRUE) else NA
      )
      
      # Merge with all stages to include stages with no tasks
      stage_progress <- merge(
        stages_data[, c("stage_name", "stage_order")],
        stage_progress,
        by = c("stage_name", "stage_order"),
        all.x = TRUE
      )
      
      # Fill NA with 0
      stage_progress$overall_percent_complete <- ifelse(
        is.na(stage_progress$overall_percent_complete), 
        0, 
        stage_progress$overall_percent_complete
      )
    }
    
    # Order by stage_order
    stage_progress <- stage_progress[order(stage_progress$stage_order), ]
    
    # Convert stage_name to factor with levels in stage_order
    stage_progress$stage_name <- factor(stage_progress$stage_name, 
                                        levels = stage_progress$stage_name)
    
    ggplot(stage_progress, aes(x = stage_name, y = overall_percent_complete)) +
      geom_bar(stat = "identity", fill = "steelblue") +
      geom_text(aes(label = sprintf("%.1f%%", overall_percent_complete)), 
               vjust = -0.5) +
      ylim(0, 110) +
      labs(title = "Average Progress by Stage",
           x = "Stage",
           y = "Progress (%)") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })
  
  # Timeline plot
  output$timeline_plot <- renderPlot({
    data <- task_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(NULL)
    }
    
    library(ggplot2)
    
    # Prepare timeline data
    data$end_display <- ifelse(is.na(data$end_time), 
                           as.numeric(Sys.time()), 
                           as.numeric(data$end_time))
    data$start_display <- as.numeric(data$start_time)
    
    # Order by stage_order and convert stage_name to factor for proper facet ordering
    data <- data[order(data$stage_order), ]
    data$stage_name <- factor(data$stage_name, levels = unique(data$stage_name))
    
    ggplot(data, aes(y = task_name, color = status)) +
      geom_segment(aes(x = as.POSIXct(start_display, origin = "1970-01-01"),
                      xend = as.POSIXct(end_display, origin = "1970-01-01"),
                      yend = task_name),
                  size = 8) +
      facet_grid(stage_name ~ ., scales = "free_y", space = "free_y") +
      labs(title = "Task Timeline",
           x = "Time",
           y = "Task",
           color = "Status") +
      theme_minimal() +
      theme(
        axis.text.y = element_text(size = 12),
        axis.text.x = element_text(size = 11),
        axis.title = element_text(size = 13, face = "bold"),
        strip.text = element_text(size = 12, face = "bold"),
        plot.title = element_text(size = 14, face = "bold")
      )
  })
  
  # Last update time
  output$last_update <- renderText({
    if (!is.null(rv$last_update)) {
      paste("Last update:", format(rv$last_update, "%H:%M:%S"))
    } else {
      "No data loaded"
    }
  })
}

# Helper function
format_duration <- function(start, end) {
  sapply(seq_along(start), function(i) {
    s <- start[i]
    e <- end[i]
    
    if (is.na(s)) return("-")
    
    if (is.na(e)) {
      e <- Sys.time()
    }
    
    duration <- as.numeric(difftime(e, s, units = "secs"))
    
    hours <- floor(duration / 3600)
    minutes <- floor((duration %% 3600) / 60)
    seconds <- round(duration %% 60)
    
    if (hours > 0) {
      sprintf("%02d:%02d:%02d", hours, minutes, seconds)
    } else if (minutes > 0) {
      sprintf("%02d:%02d", minutes, seconds)
    } else {
      sprintf("%ds", seconds)
    }
  })
}

shinyApp(ui = ui, server = server)
