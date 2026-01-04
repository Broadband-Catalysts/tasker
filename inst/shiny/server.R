library(shiny)
library(bslib)
library(DT)
library(tasker)
library(dplyr)
library(lubridate)
library(shinyWidgets)
library(shinyjs)

# ============================================================================
# UTILITY FUNCTIONS for Static UI Updates  
# ============================================================================

# Safe NULL operator
`%||%` <- function(x, y) if (is.null(x) || is.na(x)) y else x

# Format duration helper function
format_duration <- function(start_time, end_time) {
  if (is.null(start_time) || is.na(start_time)) return("-")
  if (is.null(end_time) || is.na(end_time)) end_time <- Sys.time()
  
  tryCatch({
    dur <- as.duration(interval(start_time, end_time))
    period <- seconds_to_period(as.numeric(dur, "seconds"))
    
    h <- hour(period)
    m <- minute(period)
    sec <- round(second(period))
    
    if (h > 0) {
      sprintf("%02d:%02d:%02d", h, m, sec)
    } else if (m > 0) {
      sprintf("%02d:%02d", m, sec)
    } else {
      sprintf("%ds", sec)
    }
  }, error = function(e) "-")
}

# Generate badge HTML
badge_html <- function(status) {
  if (status == "NOT_STARTED") {
    sprintf('<span class="badge" style="background-color: #dee2e6; color: #495057;">%s</span>', htmltools::htmlEscape(status))
  } else {
    status_class <- switch(status,
      "COMPLETED" = "bg-success text-white",
      "RUNNING" = "bg-warning text-dark", 
      "FAILED" = "bg-danger text-white",
      "STARTED" = "bg-info text-dark",
      "bg-secondary text-white"  # default
    )
    sprintf('<span class="badge %s">%s</span>', status_class, htmltools::htmlEscape(status))
  }
}

# Generate progress bar HTML
stage_progress_html <- function(progress_pct, status) {
  # Ensure progress_pct is numeric and within bounds
  progress_pct <- max(0, min(100, as.numeric(progress_pct %||% 0)))
  status <- as.character(status %||% "unknown")
  
  sprintf('
    <div class="stage-progress">
      <div class="stage-progress-fill status-%s" style="width: %.0f%%">
        %.0f%%
      </div>
    </div>',
    htmltools::htmlEscape(status), progress_pct, progress_pct
  )
}

# Generate task progress bars HTML with subtask information
task_progress_html <- function(task_data) {
  if (is.null(task_data)) {
    task_data <- list(
      status = "NOT_STARTED",
      overall_percent_complete = 0,
      current_subtask = 0,
      total_subtasks = 0,
      current_subtask_name = "",
      current_subtask_number = 0,
      items_total = 0,
      items_complete = 0
    )
  }
  
  task_status <- task_data$status
  task_progress <- if (!is.na(task_data$overall_percent_complete)) task_data$overall_percent_complete else 0
  current_subtask <- if (!is.na(task_data$current_subtask)) task_data$current_subtask else 0
  total_subtasks <- if (!is.na(task_data$total_subtasks)) task_data$total_subtasks else 0
  items_total <- if (!is.na(task_data$items_total)) task_data$items_total else 0
  items_complete <- if (!is.na(task_data$items_complete)) task_data$items_complete else 0
  
  show_dual <- (items_total > 1 && task_status != "COMPLETED")
  
  # Calculate effective progress - prioritize subtask-based calculation when available
  effective_progress <- if (total_subtasks > 0 && current_subtask >= 0) {
    round(100 * current_subtask / total_subtasks, 1)
  } else if (!is.na(task_progress)) {
    task_progress
  } else {
    0
  }
  
  # Build enhanced progress bar labels with subtask information
  task_label <- if (task_status == "COMPLETED") {
    if (total_subtasks > 0) {
      sprintf("Task: %d/%d (100%%)", total_subtasks, total_subtasks)
    } else {
      "Task: 100%"
    }
  } else if (task_status == "FAILED") {
    if (total_subtasks > 0) {
      if (!is.null(task_data$current_subtask_name) && task_data$current_subtask_name != "") {
        sprintf("Task: %d/%d (%.1f%%) - Subtask %d.%d | %s", 
               current_subtask, total_subtasks, effective_progress,
               current_subtask, 
               if (!is.na(task_data$current_subtask_number)) task_data$current_subtask_number else 1,
               task_data$current_subtask_name)
      } else {
        sprintf("Task: %d/%d (%.1f%%)", current_subtask, total_subtasks, effective_progress)
      }
    } else {
      sprintf("Task: %.1f%%", effective_progress)
    }
  } else if (task_status %in% c("RUNNING", "STARTED")) {
    if (total_subtasks > 0) {
      if (!is.null(task_data$current_subtask_name) && task_data$current_subtask_name != "") {
        sprintf("Task: %d/%d (%.1f%%) - Subtask %d.%d | %s", 
               current_subtask, total_subtasks, effective_progress,
               current_subtask,
               if (!is.na(task_data$current_subtask_number)) task_data$current_subtask_number else 1,
               task_data$current_subtask_name)
      } else {
        sprintf("Task: %d/%d (%.1f%%)", current_subtask, total_subtasks, effective_progress)
      }
    } else {
      sprintf("Task: %.1f%%", effective_progress)
    }
  } else {
    "Task:"
  }
  
  task_width <- if (task_status == "COMPLETED") {
    100
  } else if (task_status == "FAILED") {
    effective_progress
  } else if (task_status == "RUNNING") {
    max(effective_progress, 1)
  } else if (task_status == "STARTED") {
    max(effective_progress, 1)
  } else if (task_status == "NOT_STARTED") {
    0
  } else {
    0
  }
  
  # Determine progress bar style
  bar_status <- switch(task_status,
    "COMPLETED" = "success",
    "RUNNING" = "warning", 
    "FAILED" = "danger",
    "STARTED" = "info",
    "primary"
  )
  
  # Build primary progress bar HTML
  if (task_width > 0) {
    progress_html <- sprintf('
      <div class="task-progress-container">
        <div class="progress" style="height: 20px; overflow: visible;">
          <div class="progress-bar progress-bar-%s%s" role="progressbar" 
               style="width: %.0f%%; overflow: visible;" aria-valuenow="%.0f" aria-valuemin="0" aria-valuemax="100">
            %s
          </div>
        </div>',
      bar_status,
      if (task_status == "RUNNING") " progress-bar-striped progress-bar-animated" else "",
      task_width, task_width, task_label
    )
  } else {
    # For NOT_STARTED tasks, render empty progress bar container
    progress_html <- '
      <div class="task-progress-container">
        <div class="progress" style="height: 20px; overflow: visible;">
        </div>'
  }
  
  # Add secondary items progress bar if needed
  if (show_dual) {
    items_complete_safe <- if (is.na(items_complete)) 0 else items_complete
    items_total_safe <- if (is.na(items_total) || items_total == 0) 1 else items_total
    items_pct <- round(100 * items_complete_safe / items_total_safe, 1)
    
    progress_html <- paste0(progress_html, sprintf('
      <div style="height: 4px;"></div>
      <div class="progress" style="height: 15px; overflow: visible;">
        <div class="progress-bar progress-bar-info" role="progressbar" 
             style="width: %.1f%%; overflow: visible;" aria-valuenow="%.1f" aria-valuemin="0" aria-valuemax="100">
          <small>Items: %.0f/%.0f (%.1f%%)</small>
        </div>
      </div>',
      items_pct, items_pct, items_complete_safe, items_total, items_pct
    ))
  }
  
  progress_html <- paste0(progress_html, '</div>')
  
  return(progress_html)
}

server <- function(input, output, session) {
  # ============================================================================
  # INITIALIZATION: Get structure once at startup
  # ============================================================================
  
  # Reactive values for general app state
  rv <- reactiveValues(
    selected_task_id = NULL,
    last_update = NULL,
    expanded_stages = c(),
    error_message = NULL,
    force_refresh = 0,
    reset_pending_stage = NULL,
    reset_pending_task = NULL
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
  # REACTIVE DATA: One reactiveVal per task for status
  # ============================================================================
  
  # Storage for task reactiveVals - created dynamically
  task_reactives <- reactiveValues()
  
  # Storage for stage aggregate data - computed from tasks
  stage_reactives <- reactiveValues()
  
  # Initialize task reactiveVals when structure is loaded
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    tasks <- struct$tasks
    stages <- struct$stages
    if (is.null(tasks) || nrow(tasks) == 0) return()
    
    # Create a reactiveVal for each task
    for (i in seq_len(nrow(tasks))) {
      task <- tasks[i, ]
      task_key <- paste(task$stage_name, task$task_name, sep = "||")
      
      # Initialize with NOT_STARTED status if not already exists
      if (is.null(task_reactives[[task_key]])) {
        task_reactives[[task_key]] <- list(
          stage_name = task$stage_name,
          task_name = task$task_name,
          task_order = task$task_order,
          status = "NOT_STARTED",
          overall_percent_complete = 0,
          overall_progress_message = "",
          run_id = NA,
          current_subtask = 0,
          total_subtasks = 0,
          items_total = 0,
          items_complete = 0
        )
      }
    }
    
    # Initialize stage reactives
    if (!is.null(stages) && nrow(stages) > 0) {
      for (i in seq_len(nrow(stages))) {
        stage_name <- stages[i, ]$stage_name
        if (is.null(stage_reactives[[stage_name]])) {
          stage_reactives[[stage_name]] <- list(
            completed = 0,
            total = 0,
            progress_pct = 0,
            status = "NOT_STARTED"
          )
        }
      }
    }
  })
  
  # ============================================================================
  # POLLING OBSERVER: Update only changed task statuses
  # ============================================================================
  
  # Auto-refresh timer
  autoRefresh <- reactive({
    if (input$auto_refresh) {
      invalidateLater(input$refresh_interval * 1000)
    }
    input$refresh
  })
  
  # Task data reactive - fetches current task status
  task_data <- reactive({
    autoRefresh()  # Depend on auto-refresh
    
    tryCatch({
      tasker::get_task_status()
    }, error = function(e) {
      message("Error getting task data: ", e$message)
      NULL
    })
  })
  
  # Observer: Poll database and update only changed values
  observe({
    # Use the task_data reactive instead of duplicating the call
    current_status <- task_data()
    rv$force_refresh  # Also depend on force_refresh
    
    if (is.null(current_status) || nrow(current_status) == 0) return()
    
    # Update each task's reactive ONLY if it changed
    for (i in seq_len(nrow(current_status))) {
      task_status <- current_status[i, ]
      task_key <- paste(task_status$stage_name, task_status$task_name, sep = "||")
      
      current_val <- task_reactives[[task_key]]
      
      # Get subtask info for items progress - only for RUNNING/STARTED tasks
      items_total <- 0
      items_complete <- 0
      subtask_info <- NULL
      if (!is.na(task_status$run_id) && task_status$status %in% c("RUNNING", "STARTED")) {
        subtask_info <- tryCatch({
          subs <- tasker::get_subtask_progress(task_status$run_id)
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
        
        if (!is.null(subtask_info) && !is.na(subtask_info$items_total) && subtask_info$items_total > 0) {
          items_total <- subtask_info$items_total
          items_complete <- if (!is.na(subtask_info$items_complete)) subtask_info$items_complete else 0
        }
      }
      
      new_val <- list(
        stage_name = task_status$stage_name,
        task_name = task_status$task_name,
        task_order = if (!is.null(current_val)) current_val$task_order else NA,
        status = task_status$status,
        overall_percent_complete = if (!is.na(task_status$overall_percent_complete)) task_status$overall_percent_complete else 0,
        overall_progress_message = if (!is.na(task_status$overall_progress_message)) task_status$overall_progress_message else "",
        run_id = task_status$run_id,
        current_subtask = if (!is.na(task_status$current_subtask)) task_status$current_subtask else 0,
        total_subtasks = if (!is.na(task_status$total_subtasks)) task_status$total_subtasks else 0,
        items_total = items_total,
        items_complete = items_complete,
        # Add subtask name from active subtask if available
        current_subtask_name = if (!is.null(subtask_info) && !is.na(subtask_info$subtask_name)) subtask_info$subtask_name else "",
        current_subtask_number = if (!is.null(subtask_info) && !is.na(subtask_info$subtask_number)) subtask_info$subtask_number else 0
      )
      
      # Only update if something changed
      if (is.null(current_val) || !identical(current_val, new_val)) {
        task_reactives[[task_key]] <- new_val
      }
    }
    
    rv$last_update <- Sys.time()
  })
  
  # ============================================================================
  # OBSERVER: Update stage aggregates from task reactives
  # ============================================================================
  
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    stages <- struct$stages
    tasks <- struct$tasks
    if (is.null(stages) || nrow(stages) == 0 || is.null(tasks) || nrow(tasks) == 0) return()
    
    # Trigger on any task_reactives change
    reactiveValuesToList(task_reactives)
    
    # Update each stage's aggregate stats
    for (i in seq_len(nrow(stages))) {
      stage_name <- stages[i, ]$stage_name
      stage_tasks <- tasks[tasks$stage_name == stage_name, ]
      
      if (nrow(stage_tasks) == 0) next
      
      # Get all task data for this stage
      task_keys <- paste(stage_tasks$stage_name, stage_tasks$task_name, sep = "||")
      task_data_list <- lapply(task_keys, function(key) task_reactives[[key]])
      
      total_tasks <- length(task_data_list)
      statuses <- sapply(task_data_list, function(td) if(!is.null(td)) td$status else "NOT_STARTED")
      
      completed <- sum(statuses == "COMPLETED", na.rm = TRUE)
      running <- sum(statuses == "RUNNING", na.rm = TRUE)
      started <- sum(statuses == "STARTED", na.rm = TRUE)
      failed <- sum(statuses == "FAILED", na.rm = TRUE)
      
      progress_pct <- if (total_tasks > 0) round(100 * completed / total_tasks) else 0
      
      stage_status <- if (failed > 0) {
        "FAILED"
      } else if (running > 0) {
        "RUNNING"
      } else if (completed == total_tasks) {
        "COMPLETED"
      } else if (started > 0 || completed > 0) {
        "STARTED"
      } else {
        "NOT_STARTED"
      }
      
      # Update stage reactive
      stage_reactives[[stage_name]] <- list(
        completed = completed,
        total = total_tasks,
        progress_pct = progress_pct,
        status = stage_status
      )
    }
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
    }, error = function(e) {
      error_details <- paste0(
        "Error fetching stages: ", e$message, "\n",
        "Function: get_stages()",
        "\nTime: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
      rv$error_message <- error_details
      showNotification(error_details, type = "error", duration = 10)
      NULL
    })
    
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
  
  # Note: Stage expansion state is now managed by bslib::accordion()
  
  # Handle task reset button clicks - show confirmation modal
  observeEvent(input$task_reset_clicked, {
    req(input$task_reset_clicked)
    
    stage <- input$task_reset_clicked$stage
    task <- input$task_reset_clicked$task
    
    # Store the task info for the confirm handler
    rv$reset_pending_stage <- stage
    rv$reset_pending_task <- task
    
    # Show confirmation modal
    showModal(modalDialog(
      title = tags$span(
        icon("exclamation-triangle"),
        " Confirm Task Reset"
      ),
      div(
        style = "font-size: 14px;",
        tags$p(
          style = "font-weight: bold; color: #d9534f;",
          "WARNING: This action is irreversible and cannot be undone!"
        ),
        tags$p(
          "You are about to reset the following task:"
        ),
        tags$div(
          style = "background: #f5f5f5; padding: 10px; margin: 10px 0; border-radius: 4px; font-family: monospace;",
          tags$div(sprintf("Stage: %s", stage)),
          tags$div(sprintf("Task: %s", task))
        ),
        tags$p(
          "This will delete all execution history, progress data, and subtask information for this task."
        ),
        tags$p(
          style = "margin-bottom: 0;",
          "The task status will be set back to NOT_STARTED."
        )
      ),
      footer = tagList(
        actionButton("confirm_reset", "Reset Task", 
                    class = "btn-danger",
                    icon = icon("trash")),
        modalButton("Cancel")
      ),
      easyClose = FALSE,
      size = "m"
    ))
  }, ignoreNULL = TRUE, ignoreInit = TRUE)
  
  # Handle confirmed reset
  observeEvent(input$confirm_reset, {
    stage <- rv$reset_pending_stage
    task <- rv$reset_pending_task
    
    req(stage, task)
    
    # Close the modal
    removeModal()
    
    # Perform the reset
    tryCatch({
      tasker::task_reset(stage = stage, task = task, quiet = FALSE)
      
      showNotification(
        sprintf("Task '%s' in stage '%s' has been reset", task, stage),
        type = "message",
        duration = 3
      )
      
      # Force refresh of task data
      rv$force_refresh <- rv$force_refresh + 1
      
      # Clear pending task info
      rv$reset_pending_stage <- NULL
      rv$reset_pending_task <- NULL
      
    }, error = function(e) {
      showNotification(
        sprintf("Error resetting task: %s", e$message),
        type = "error",
        duration = 5
      )
    })
  })
  
  # ============================================================================
  # PIPELINE STATUS UI: Static structure with reactive components
  # ============================================================================
  
  # Build the entire UI structure once using bslib::accordion
  # ============================================================================
  # STATIC UI GENERATION: Build accordion structure once at startup
  # ============================================================================
  
  # Build static UI structure when pipeline structure is loaded
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) {
      shinyjs::html("pipeline_stages_accordion", 
                   '<div class="alert alert-info">Loading pipeline structure...</div>')
      return()
    }
    
    stages <- struct$stages
    tasks <- struct$tasks
    
    if (is.null(stages) || nrow(stages) == 0) {
      shinyjs::html("pipeline_stages_accordion", 
                   '<div class="alert alert-info">No stages configured</div>')
      return()
    }
    
    if (is.null(tasks) || nrow(tasks) == 0) {
      shinyjs::html("pipeline_stages_accordion", 
                   '<div class="alert alert-info">No tasks registered</div>')
      return()
    }
    
    # Order stages
    stages <- stages[order(stages$stage_order), ]
    
    # Build static HTML structure
    accordion_html <- ""
    
    for (i in seq_len(nrow(stages))) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      stage_id <- gsub("[^a-zA-Z0-9]", "_", stage_name)
      
      # Get tasks for this stage
      stage_tasks <- tasks[tasks$stage_name == stage_name, ]
      if (nrow(stage_tasks) > 0) {
        stage_tasks <- stage_tasks[order(stage_tasks$task_order), ]
      }
      
      # Build task rows HTML
      task_rows_html <- ""
      for (j in seq_len(nrow(stage_tasks))) {
        task <- stage_tasks[j, ]
        task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task$task_name, sep="_"))
        
        task_rows_html <- paste0(task_rows_html, sprintf('
          <div class="task-row">
            <div class="task-name">%s</div>
            <div id="task_status_%s" class="task-status-badge"></div>
            <div id="task_progress_%s" class="task-progress-container"></div>
            <div id="task_message_%s" class="task-message"></div>
            <div id="task_reset_%s" class="task-reset-button"></div>
          </div>',
          htmltools::htmlEscape(task$task_name), task_id, task_id, task_id, task_id
        ))
      }
      
      # Build accordion panel HTML
      accordion_html <- paste0(accordion_html, sprintf('
        <div class="accordion-item">
          <h2 class="accordion-header" id="heading_%s">
            <button class="accordion-button collapsed" type="button" 
                    data-bs-toggle="collapse" data-bs-target="#collapse_%s" 
                    aria-expanded="false" aria-controls="collapse_%s">
              <div class="stage-header">
                <div class="stage-name">%s</div>
                <div id="stage_badge_%s" class="stage-badge"></div>
                <div id="stage_progress_%s" class="stage-progress"></div>
                <div id="stage_count_%s" class="stage-count"></div>
              </div>
            </button>
          </h2>
          <div id="collapse_%s" class="accordion-collapse collapse" 
               aria-labelledby="heading_%s">
            <div class="accordion-body">
              %s
            </div>
          </div>
        </div>',
        stage_id, stage_id, stage_id, 
        htmltools::htmlEscape(stage_name), stage_id, stage_id, stage_id,
        stage_id, stage_id, task_rows_html
      ))
    }
    
    # Insert the complete accordion structure
    shinyjs::html("pipeline_stages_accordion", accordion_html)
  })

  # Create individual reactive outputs for stage header components
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    stages <- struct$stages
    if (is.null(stages) || nrow(stages) == 0) return()
    
    stages <- stages[order(stages$stage_order), ]
    
    lapply(seq_len(nrow(stages)), function(i) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      stage_id <- gsub("[^a-zA-Z0-9]", "_", stage_name)
      
      # Create reactive observers for stage components using shinyjs
      (function(stage_name_local, stage_id_local) {
        
        # Badge - updates when status changes
        observe({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            tryCatch({
              shinyjs::html(paste0("stage_badge_", stage_id_local), 
                           badge_html(stage_data$status))
            }, error = function(e) {
              message("Error updating stage badge: ", e$message)
            })
          }
        })
        
        # Progress bar - updates when progress or status changes
        observe({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            tryCatch({
              shinyjs::html(paste0("stage_progress_", stage_id_local),
                           stage_progress_html(stage_data$progress_pct, stage_data$status))
            }, error = function(e) {
              message("Error updating stage progress: ", e$message)
            })
          }
        })
        
        # Count - updates when task counts change
        observe({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            tryCatch({
              shinyjs::html(paste0("stage_count_", stage_id_local),
                           sprintf("%d/%d", stage_data$completed, stage_data$total))
            }, error = function(e) {
              message("Error updating stage count: ", e$message)
            })
          }
        })
      })(stage_name, stage_id)
    })
  })
  
  # Create reactive observers for individual task components using shinyjs
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    stages <- struct$stages
    tasks <- struct$tasks
    
    if (is.null(stages) || nrow(stages) == 0 || is.null(tasks) || nrow(tasks) == 0) return()
    
    # For each task, create individual reactive outputs
    lapply(seq_len(nrow(tasks)), function(i) {
      task <- tasks[i, ]
      stage_name <- task$stage_name
      task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task$task_name, sep="_"))
      task_key <- paste(stage_name, task$task_name, sep = "||")
      
      # Create reactive observers for task components using shinyjs
      (function(task_key_local, task_id_local, stage_name_local, task_name_local) {
        
        # Status badge
        observe({
          task_data <- task_reactives[[task_key_local]]
          task_status <- if (!is.null(task_data)) task_data$status else "NOT_STARTED"
          tryCatch({
            shinyjs::html(paste0("task_status_", task_id_local), badge_html(task_status))
          }, error = function(e) {
            message("Error updating task status: ", e$message)
          })
        })
        
        # Progress bars with enhanced subtask information
        observe({
          task_data <- task_reactives[[task_key_local]]
          tryCatch({
            shinyjs::html(paste0("task_progress_", task_id_local), task_progress_html(task_data))
          }, error = function(e) {
            message("Error updating task progress: ", e$message)
          })
        })
        
        # Message with enhanced subtask details
        observe({
          task_data <- task_reactives[[task_key_local]]
          
          # Create enhanced message that includes subtask information
          message_text <- if (!is.null(task_data)) {
            current_subtask_name <- task_data$current_subtask_name %||% ""
            overall_progress_message <- task_data$overall_progress_message %||% ""
            current_subtask <- task_data$current_subtask %||% 0
            current_subtask_number <- task_data$current_subtask_number %||% 1
            
            if (nchar(current_subtask_name) > 0 && nchar(overall_progress_message) > 0) {
              # Combine subtask name with overall progress message
              sprintf("Subtask %d.%d: %s | %s", 
                     current_subtask, current_subtask_number,
                     current_subtask_name, overall_progress_message)
            } else if (nchar(current_subtask_name) > 0) {
              # Show only subtask name if no overall message
              sprintf("Subtask %d.%d: %s", current_subtask, current_subtask_number, current_subtask_name)
            } else {
              # Fall back to overall progress message
              overall_progress_message
            }
          } else {
            ""
          }
          
          message_text <- message_text %||% ""
          
          tryCatch({
            shinyjs::html(paste0("task_message_", task_id_local), 
                         sprintf('<div class="task-message" title="%s">%s</div>',
                                htmltools::htmlEscape(message_text),
                                htmltools::htmlEscape(message_text)))
          }, error = function(e) {
            message("Error updating task message: ", e$message)
          })
        })
        
        # Reset button
        observe({
          tryCatch({
            reset_btn_html <- sprintf(
              '<button id="reset_btn_%s" class="btn btn-sm btn-warning task-reset-btn" title="Reset this task to NOT_STARTED" onclick="Shiny.setInputValue(\'task_reset_clicked\', {stage: \'%s\', task: \'%s\', timestamp: Date.now()}, {priority: \'event\'})">Reset</button>',
              task_id_local, 
              htmltools::htmlEscape(stage_name_local), 
              htmltools::htmlEscape(task_name_local)
            )
            shinyjs::html(paste0("task_reset_", task_id_local), reset_btn_html)
          }, error = function(e) {
            message("Error updating task reset button: ", e$message)
          })
        })
      })(task_key, task_id, stage_name, task$task_name)
    })
  })
  
  # Remove the old pipeline_data reactive and related code below this point
  
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
            items_pct <- round(100 * items_complete / st$items_total, 1)
            sprintf("%s<br/><small>%s</small><br/><span class='item-progress'>%d / %d items<span class='item-progress-pct'>(%.1f%%)</span></span>", 
                   base_prog, st$subtask_name, items_complete, st$items_total, items_pct)
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
        "Overall Progress" = sprintf("%.1f%%", ifelse(is.na(data$overall_percent_complete), 0, data$overall_percent_complete)),
        Started  = format(data$start_time, "%Y-%m-%d %H:%M:%S"),
        Duration = format_duration(data$start_time, data$last_update),
        Host     = ifelse(is.na(data$hostname), "-", data$hostname),
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
                           tags$tr(tags$th("Script File:"), tags$td(ifelse(is.na(task$script_filename), "N/A", task$script_filename))),
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
  
  # Log Viewer Tab
  output$log_viewer_ui <- renderUI({
    data <- task_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(div(class = "alert alert-info", "No tasks available. Please select a task with a log file."))
    }
    
    # Get tasks that have log files
    tasks_with_logs <- data[!is.na(data$log_path) & data$log_path != "" & !is.na(data$log_filename), ]
    
    if (nrow(tasks_with_logs) == 0) {
      return(div(class = "alert alert-info", "No tasks with log files found."))
    }
    
    # Create choices for selectInput
    log_choices <- setNames(
      tasks_with_logs$run_id,
      paste0(tasks_with_logs$stage_name, " > ", tasks_with_logs$task_name, " (", tasks_with_logs$status, ")")
    )
    
    tagList(
      div(class = "log-header",
          selectInput("log_task_select", "Select Task:", 
                     choices = log_choices,
                     width = "400px"),
          numericInput("log_lines", "Lines to show:", 
                      value = 100, min = 10, max = 5000, step = 50,
                      width = "150px"),
          checkboxInput("log_tail", "Tail mode (show last lines)", value = TRUE),
          checkboxInput("log_auto_refresh", "Auto-refresh", value = TRUE),
          actionButton("log_refresh", "Refresh", class = "btn-primary btn-sm")
      ),
      div(class = "log-output",
          uiOutput("log_content")
      )
    )
  })
  
  # Log content display
  output$log_content <- renderUI({
    # Trigger refresh
    input$log_refresh
    
    if (input$log_auto_refresh) {
      invalidateLater(3000)  # Refresh every 3 seconds
    }
    
    if (is.null(input$log_task_select) || input$log_task_select == "") {
      return(HTML("<div class='log-line'>No task selected</div>"))
    }
    
    tryCatch({
      # Get task info
      data <- task_data()
      
      if (is.null(data) || nrow(data) == 0) {
        return(HTML("<div class='log-line log-line-error'>No task data available</div>"))
      }
      
      task <- data[data$run_id == input$log_task_select, ]
      
      if (nrow(task) == 0) {
        return(HTML("<div class='log-line log-line-error'>Task not found</div>"))
      }
      
      # Construct log file path
      log_file <- file.path(task$log_path, task$log_filename)
      
      if (!file.exists(log_file)) {
        return(HTML(paste0(
          "<div class='log-line log-line-warning'>Log file not found: ", 
          htmltools::htmlEscape(log_file), "</div>"
        )))
      }
      
      # Read log file
      num_lines <- if (!is.null(input$log_lines)) input$log_lines else 100
      tail_mode <- if (!is.null(input$log_tail)) input$log_tail else TRUE
      
      if (tail_mode) {
        # Read last N lines
        all_lines <- readLines(log_file, warn = FALSE)
        total_lines <- length(all_lines)
        start_line <- max(1, total_lines - num_lines + 1)
        lines <- all_lines[start_line:total_lines]
      } else {
        # Read first N lines
        lines <- readLines(log_file, n = num_lines, warn = FALSE)
      }
      
      if (length(lines) == 0) {
        return(HTML("<div class='log-line'>Log file is empty</div>"))
      }
      
      # Format lines with syntax highlighting
      formatted_lines <- sapply(lines, function(line) {
        # Escape HTML
        line <- htmltools::htmlEscape(line)
        
        # Apply coloring based on content
        class_attr <- ""
        if (grepl("ERROR|Error|error|FAIL|Failed|failed", line, ignore.case = FALSE)) {
          class_attr <- " log-line-error"
        } else if (grepl("WARN|Warning|warning", line, ignore.case = FALSE)) {
          class_attr <- " log-line-warning"
        } else if (grepl("INFO|Info", line, ignore.case = FALSE)) {
          class_attr <- " log-line-info"
        }
        
        paste0("<div class='log-line", class_attr, "'>", line, "</div>")
      })
      
      # Add header info
      header <- paste0(
        "<div class='log-line log-line-info'>",
        "File: ", htmltools::htmlEscape(log_file), 
        " | Lines: ", length(lines),
        if (tail_mode) paste0(" (last ", num_lines, ")") else paste0(" (first ", num_lines, ")"),
        " | Updated: ", format(Sys.time(), "%H:%M:%S"),
        "</div><div class='log-line'>─────────────────────────────────────────────────────────────────────</div>"
      )
      
      HTML(paste0(header, paste(formatted_lines, collapse = "")))
      
    }, error = function(e) {
      HTML(paste0(
        "<div class='log-line log-line-error'>Error reading log file: ",
        htmltools::htmlEscape(e$message),
        "</div>"
      ))
    })
  })
  
  # Last update time
  output$last_update <- renderText({
    if (!is.null(rv$last_update)) {
      # Convert to US Eastern timezone
      eastern_time <- lubridate::with_tz(rv$last_update, "America/New_York")
      paste("Last update:", format(eastern_time, "%H:%M:%S %Z"))
    } else {
      "No data loaded"
    }
  })
  
  # Error display
  output$has_error <- reactive({
    !is.null(rv$error_message)
  })
  outputOptions(output, "has_error", suspendWhenHidden = FALSE)
  
  output$error_display <- renderText({
    if (!is.null(rv$error_message)) {
      rv$error_message
    } else {
      ""
    }
  })
}
