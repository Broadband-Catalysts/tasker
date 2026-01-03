server <- function(input, output, session) {
  
  # ============================================================================
  # INITIALIZATION: Get structure once at startup
  # ============================================================================
  
  # Reactive values for general app state
  rv <- reactiveValues(
    selected_task_id = NULL,
    last_update = NULL,
    error_message = NULL,
    force_refresh = 0
  )
  
  # Get pipeline structure (stages + registered tasks) - this rarely changes
  pipeline_structure <- reactiveVal(NULL)
  
  # Initialize structure
  observe({
    structure <- tryCatch({
      stages <- tasker::get_stages()
      if (!is.null(stages) && nrow(stages) > 0) {
        stages <- stages[stages$stage_name != "TEST" & stages$stage_order != 999, ]
      }
      
      registered_tasks <- tasker::get_registered_tasks()
      
      list(stages = stages, tasks = registered_tasks)
    }, error = function(e) {
      showNotification(paste("Error loading structure:", e$message), type = "error")
      NULL
    })
    
    pipeline_structure(structure)
  })
  
  # ============================================================================
  # DATA REFRESH: Main data loading with error handling
  # ============================================================================
  
  # Create reactive for stage-level data
  stage_reactives <- reactiveValues()
  
  # Create reactive for task-level data
  task_reactives <- reactiveValues()
  
  # Main data refresh function
  refresh_data <- function() {
    tryCatch({
      # Get current active tasks with progress
      active_tasks <- tasker::get_active_tasks()
      
      if (is.null(active_tasks) || nrow(active_tasks) == 0) {
        return()
      }
      
      # Update task reactives
      for (i in seq_len(nrow(active_tasks))) {
        task <- active_tasks[i, ]
        task_reactives[[task$task_id]] <- task
      }
      
      # Calculate stage-level summaries
      struct <- pipeline_structure()
      if (!is.null(struct) && !is.null(struct$stages)) {
        for (i in seq_len(nrow(struct$stages))) {
          stage <- struct$stages[i, ]
          stage_name <- stage$stage_name
          
          # Get tasks for this stage
          stage_tasks <- active_tasks[active_tasks$stage_name == stage_name, ]
          
          if (nrow(stage_tasks) > 0) {
            completed <- sum(stage_tasks$status == "COMPLETED")
            running <- sum(stage_tasks$status == "RUNNING")
            failed <- sum(stage_tasks$status == "FAILED")
            total <- nrow(stage_tasks)
            
            # Determine overall stage status
            status <- if (failed > 0) {
              "FAILED"
            } else if (running > 0) {
              "RUNNING"
            } else if (completed == total) {
              "COMPLETED"
            } else if (completed > 0) {
              "STARTED"
            } else {
              "NOT_STARTED"
            }
            
            progress_pct <- round((completed / total) * 100)
            
            stage_reactives[[stage_name]] <- list(
              status = status,
              progress_pct = progress_pct,
              completed = completed,
              total = total,
              running = running,
              failed = failed
            )
          } else {
            stage_reactives[[stage_name]] <- list(
              status = "NOT_STARTED",
              progress_pct = 0,
              completed = 0,
              total = 0,
              running = 0,
              failed = 0
            )
          }
        }
      }
      
      rv$last_update <- Sys.time()
      rv$error_message <- NULL
      
    }, error = function(e) {
      rv$error_message <- paste("Error refreshing data:", e$message)
      showNotification(paste("Error:", e$message), type = "error")
    })
  }
  
  # Auto refresh timer
  observe({
    invalidateLater(input$refresh_interval * 1000, session)
    if (input$auto_refresh) {
      refresh_data()
    }
  })
  
  # Manual refresh
  observeEvent(input$refresh, {
    refresh_data()
  })
  
  # Initial data load
  observeEvent(pipeline_structure(), {
    if (!is.null(pipeline_structure())) {
      refresh_data()
    }
  })
  
  # ============================================================================
  # FILTER LOGIC
  # ============================================================================
  
  # Update filter choices when structure changes
  observe({
    struct <- pipeline_structure()
    if (!is.null(struct) && !is.null(struct$stages)) {
      stage_choices <- setNames(struct$stages$stage_name, struct$stages$stage_name)
      updateSelectInput(session, "stage_filter", 
                       choices = c("All" = "", stage_choices),
                       selected = input$stage_filter)
    }
  })
  
  # Filtered data reactive
  filtered_stages <- reactive({
    struct <- pipeline_structure()
    if (is.null(struct) || is.null(struct$stages)) return(NULL)
    
    stages <- struct$stages
    
    # Apply stage filter
    if (!is.null(input$stage_filter) && length(input$stage_filter) > 0 && 
        !all(input$stage_filter == "")) {
      stages <- stages[stages$stage_name %in% input$stage_filter, ]
    }
    
    # Apply status filter to stages
    if (!is.null(input$status_filter) && length(input$status_filter) > 0 && 
        !all(input$status_filter == "")) {
      # Filter based on stage status
      stage_statuses <- sapply(stages$stage_name, function(sn) {
        stage_data <- stage_reactives[[sn]]
        if (is.null(stage_data)) "NOT_STARTED" else stage_data$status
      })
      stages <- stages[stage_statuses %in% input$status_filter, ]
    }
    
    stages[order(stages$stage_order), ]
  })
  
  filtered_tasks <- reactive({
    struct <- pipeline_structure()
    filtered_stages_df <- filtered_stages()
    
    if (is.null(struct) || is.null(struct$tasks) || is.null(filtered_stages_df)) {
      return(NULL)
    }
    
    tasks <- struct$tasks
    
    # Filter tasks to only those in visible stages
    if (nrow(filtered_stages_df) > 0) {
      tasks <- tasks[tasks$stage_name %in% filtered_stages_df$stage_name, ]
    } else {
      tasks <- tasks[0, ]  # Empty data frame
    }
    
    tasks
  })
  
  # ============================================================================
  # PIPELINE STATUS UI: Build with filtered data
  # ============================================================================
  
  output$pipeline_status_ui <- renderUI({
    stages <- filtered_stages()
    tasks <- filtered_tasks()
    
    if (is.null(stages) || nrow(stages) == 0) {
      return(div(class = "alert alert-info", "No stages match the current filters"))
    }
    
    if (is.null(tasks) || nrow(tasks) == 0) {
      return(div(class = "alert alert-info", "No tasks found for filtered stages"))
    }
    
    # Build accordion panels for each stage
    accordion_panels <- lapply(seq_len(nrow(stages)), function(i) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      stage_id <- gsub("[^a-zA-Z0-9]", "_", stage_name)
      
      # Get tasks for this stage
      stage_tasks <- tasks[tasks$stage_name == stage_name, ]
      if (nrow(stage_tasks) > 0) {
        stage_tasks <- stage_tasks[order(stage_tasks$task_order), ]
      }
      
      # Build task rows
      task_rows <- if (nrow(stage_tasks) > 0) {
        lapply(seq_len(nrow(stage_tasks)), function(j) {
          task <- stage_tasks[j, ]
          task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task$task_name, sep="_"))
          
          div(class = "task-row",
              div(class = "task-name", task$task_name),
              uiOutput(paste0("task_status_", task_id)),
              uiOutput(paste0("task_progress_", task_id)),
              uiOutput(paste0("task_message_", task_id))
          )
        })
      } else {
        list(div(class = "alert alert-info", "No tasks in this stage"))
      }
      
      # Create accordion panel
      accordion_panel(
        title = div(class = "stage-header",
                   div(class = "stage-name", stage_name),
                   uiOutput(paste0("stage_badge_", stage_id), inline = TRUE),
                   uiOutput(paste0("stage_progress_", stage_id), inline = TRUE),
                   textOutput(paste0("stage_count_", stage_id), inline = TRUE)
        ),
        value = paste0("stage_panel_", stage_id),
        task_rows
      )
    })
    
    # Build accordion with all stage panels
    do.call(accordion, c(
      list(id = "pipeline_stages_accordion", multiple = TRUE),
      accordion_panels
    ))
  })
  
  # ============================================================================
  # STAGE HEADER COMPONENTS: Reactive outputs
  # ============================================================================
  
  observe({
    stages <- filtered_stages()
    if (is.null(stages) || nrow(stages) == 0) return()
    
    lapply(seq_len(nrow(stages)), function(i) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      stage_id <- gsub("[^a-zA-Z0-9]", "_", stage_name)
      
      # Badge
      output[[paste0("stage_badge_", stage_id)]] <- renderUI({
        stage_data <- stage_reactives[[stage_name]]
        if (is.null(stage_data)) return(span(class = "stage-badge status-NOT_STARTED", "NOT STARTED"))
        
        span(class = paste("stage-badge", paste0("status-", stage_data$status)), 
             stage_data$status)
      })
      
      # Progress bar
      output[[paste0("stage_progress_", stage_id)]] <- renderUI({
        stage_data <- stage_reactives[[stage_name]]
        if (is.null(stage_data)) {
          return(div(class = "stage-progress",
                    div(class = "stage-progress-fill status-NOT_STARTED",
                        style = "width: 0%", "0%")))
        }
        
        div(class = "stage-progress",
            div(class = paste("stage-progress-fill", paste0("status-", stage_data$status)),
                style = sprintf("width: %d%%", stage_data$progress_pct),
                sprintf("%d%%", stage_data$progress_pct))
        )
      })
      
      # Count
      output[[paste0("stage_count_", stage_id)]] <- renderText({
        stage_data <- stage_reactives[[stage_name]]
        if (is.null(stage_data)) return("0/0")
        sprintf("%d/%d", stage_data$completed, stage_data$total)
      })
    })
  })
  
  # ============================================================================
  # TASK COMPONENTS: Reactive outputs
  # ============================================================================
  
  observe({
    tasks <- filtered_tasks()
    if (is.null(tasks) || nrow(tasks) == 0) return()
    
    lapply(seq_len(nrow(tasks)), function(i) {
      task <- tasks[i, ]
      stage_name <- task$stage_name
      task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task$task_name, sep="_"))
      
      # Status badge
      output[[paste0("task_status_", task_id)]] <- renderUI({
        task_data <- task_reactives[[task$task_id]]
        status <- if (is.null(task_data)) "NOT_STARTED" else task_data$status
        
        span(class = paste("task-status-badge", paste0("status-", status)), status)
      })
      
      # Progress container
      output[[paste0("task_progress_", task_id)]] <- renderUI({
        task_data <- task_reactives[[task$task_id]]
        if (is.null(task_data)) {
          return(div(class = "task-progress-container",
                    div(class = "task-progress",
                        div(class = "task-progress-fill status-NOT_STARTED", 
                            style = "width: 0%"),
                        div(class = "task-progress-label", "0%"))))
        }
        
        # Calculate progress percentage
        if (is.null(task_data$subtask_total) || task_data$subtask_total == 0) {
          progress_pct <- 0
          progress_text <- "0%"
        } else {
          progress_pct <- round((task_data$subtask_completed / task_data$subtask_total) * 100)
          progress_text <- sprintf("%d%%", progress_pct)
        }
        
        div(class = "task-progress-container",
            div(class = "task-progress",
                div(class = paste("task-progress-fill", paste0("status-", task_data$status)),
                    style = sprintf("width: %d%%", progress_pct)),
                div(class = "task-progress-label", progress_text)))
      })
      
      # Message
      output[[paste0("task_message_", task_id)]] <- renderUI({
        task_data <- task_reactives[[task$task_id]]
        message <- if (is.null(task_data)) "" else {
          if (!is.null(task_data$message) && task_data$message != "") {
            task_data$message
          } else {
            ""
          }
        }
        
        div(class = "task-message", message)
      })
    })
  })
  
  # ============================================================================
  # UTILITY OUTPUTS
  # ============================================================================
  
  output$last_update <- renderText({
    if (is.null(rv$last_update)) {
      "Never"
    } else {
      format(rv$last_update, "%H:%M:%S")
    }
  })
  
  output$has_error <- reactive({
    !is.null(rv$error_message)
  })
  outputOptions(output, "has_error", suspendWhenHidden = FALSE)
  
  output$error_display <- renderText({
    rv$error_message %||% ""
  })
}