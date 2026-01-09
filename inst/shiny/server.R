library(shiny)
library(bslib)
library(DT)
library(tasker)
library(dplyr)
library(lubridate)
library(shinyWidgets)
library(shinyjs)
library(htmltools)
library(ps)
library(jsonlite)

# Source completion estimation functions - now in tasker package
# (kept for reference - functions are now called via tasker:: namespace)

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
  
  # Apply minimum width for active stages to show activity
  if (status %in% c("STARTED", "RUNNING")) {
    progress_pct <- max(progress_pct, 0.5)
  }
  
  sprintf('
    <div class="stage-progress">
      <div class="stage-progress-fill status-%s" style="width: %.1f%%"></div>
      <span class="stage-progress-text">%.0f%%</span>
    </div>',
    htmltools::htmlEscape(status), progress_pct, round(progress_pct)
  )
}

# Initialize log settings with defaults
init_log_settings <- function(rv, task_id) {
  if (is.null(rv$log_settings[[task_id]])) {
    rv$log_settings[[task_id]] <- list(
      num_lines = 5,
      tail_mode = TRUE,
      auto_refresh = TRUE,
      filter = ""
    )
  }
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
    # Show minimum progress to indicate activity
    min_width <- if (total_subtasks > 0) (0.5 / total_subtasks) * 100 else 0.5
    max(effective_progress, min_width)
  } else if (task_status == "STARTED") {
    # Show minimum progress to indicate activity
    min_width <- if (total_subtasks > 0) (0.5 / total_subtasks) * 100 else 0.5
    max(effective_progress, min_width)
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
        <div class="task-progress" style="height: 20px;">
          <div class="task-progress-fill status-%s" style="width: %.0f%%"></div>
          <span class="task-progress-text">%s</span>
        </div>',
      task_status,
      task_width, task_label
    )
  } else {
    # For NOT_STARTED tasks, render empty progress bar container
    progress_html <- sprintf('
      <div class="task-progress-container">
        <div class="task-progress" style="height: 20px;">
          <span class="task-progress-text">%s</span>
        </div>',
      task_label)
  }
  
  # Add secondary items progress bar if needed
  if (show_dual) {
    items_complete_safe <- if (is.na(items_complete)) 0 else items_complete
    items_total_safe <- if (is.na(items_total) || items_total == 0) 1 else items_total
    items_pct <- round(100 * items_complete_safe / items_total_safe, 1)
    
    # Apply minimum width for active tasks to show activity
    if (task_status %in% c("STARTED", "RUNNING")) {
      min_width <- (0.5 / items_total_safe) * 100
      items_pct <- max(items_pct, min_width)
    }
    
    progress_html <- paste0(progress_html, sprintf('
      <div style="height: 4px;"></div>
      <div class="task-progress" style="height: 15px;">
        <div class="item-progress-fill status-%s" style="width: %.2f%%"></div>
        <span class="item-progress-text">Items: %.0f/%.0f (%.1f%%)</span>
      </div>',
      task_status,
      items_pct, items_complete_safe, items_total, round(items_pct, 1)
    ))
  }
  
  progress_html <- paste0(progress_html, '</div>')
  
  return(progress_html)
}

# Generate process status pane HTML
build_process_status_html <- function(task_data, stage_name, task_name, progress_history_env = NULL, output = NULL, task_reactives = NULL, session = NULL) {
  if (is.null(task_data)) {
    return(HTML("<div class='process-info-header'>No task data available</div>"))
  }
  
  # Show basic task info even if never run
  if (is.null(task_data$run_id) || is.na(task_data$run_id)) {
    basic_info <- sprintf(
      "<div class='process-info'>
        <h4 class='process-info-header'>Task Information</h4>
        <div class='process-details'>
          <div class='process-detail-item'><strong>Stage:</strong> <span>%s</span></div>
          <div class='process-detail-item'><strong>Task:</strong> <span>%s</span></div>
          <div class='process-detail-item'><strong>Status:</strong> <span>%s</span></div>
          <div class='process-detail-item'><strong>Last Run:</strong> <span>Never executed</span></div>
        </div>
        <p style='margin-top: 15px; color: #666;'>This task has not been executed yet. No process information or subtask details are available.</p>
      </div>",
      htmltools::htmlEscape(stage_name),
      htmltools::htmlEscape(task_name), 
      htmltools::htmlEscape(task_data$status %||% "NOT_STARTED")
    )
    return(HTML(basic_info))
  }
  
  run_id <- task_data$run_id
  status <- task_data$status
  
  # Check if process is actually running (validate PID)
  process_dead <- FALSE
  if (!is.null(task_data$process_id) && !is.na(task_data$process_id)) {
    if (status %in% c("RUNNING", "STARTED")) {
      # Check if process exists using ps package
      pid_check <- tryCatch({
        ps::ps_is_running(ps::ps_handle(as.integer(task_data$process_id)))
      }, error = function(e) FALSE, warning = function(w) FALSE)
      
      if (!pid_check) {
        process_dead <- TRUE
      }
    }
  }
  
  # Build HTML components
  html_parts <- list()
  
  # Error banner if process is dead
  if (process_dead) {
    html_parts <- c(html_parts, sprintf(
      "<div class='process-error-banner'>
        <i class='fa fa-exclamation-triangle'></i>
        <div class='error-text'>WARNING: Task marked as %s but process (PID: %s) is not running</div>
      </div>",
      htmltools::htmlEscape(status),
      htmltools::htmlEscape(as.character(task_data$process_id))
    ))
  }
  
  # Main process info header
  html_parts <- c(html_parts, "<h4 class='process-info-header'>Main Process Info</h4>")
  
  # Process details
  process_details <- sprintf(
    "<div class='process-details'>
      <div class='process-detail-item'><strong>PID:</strong> <span>%s</span></div>
      <div class='process-detail-item'><strong>Hostname:</strong> <span>%s</span></div>
      <div class='process-detail-item'><strong>Status:</strong> <span>%s</span></div>
      <div class='process-detail-item'><strong>Started:</strong> <span>%s</span></div>
    </div>",
    htmltools::htmlEscape(if (!is.null(task_data$process_id)) as.character(task_data$process_id) else "N/A"),
    htmltools::htmlEscape(if (!is.null(task_data$hostname)) task_data$hostname else "N/A"),
    htmltools::htmlEscape(status),
    htmltools::htmlEscape(if (!is.null(task_data$start_time)) format(task_data$start_time, "%Y-%m-%d %H:%M:%S") else "N/A")
  )
  html_parts <- c(html_parts, process_details)
  
  # Resource usage if available
  if (!is.null(task_data$cpu_percent) && !is.na(task_data$cpu_percent)) {
    resource_html <- sprintf(
      "<div class='process-details'>
        <div class='process-detail-item'><strong>CPU:</strong> <span>%.1f%%</span></div>
        <div class='process-detail-item'><strong>Memory:</strong> <span>%s</span></div>
        <div class='process-detail-item'><strong>Processes:</strong> <span>%s</span></div>
      </div>",
      task_data$cpu_percent,
      if (!is.null(task_data$memory_mb) && !is.na(task_data$memory_mb)) 
        sprintf("%.1f MB", task_data$memory_mb) else "N/A",
      if (!is.null(task_data$process_count) && !is.na(task_data$process_count)) 
        as.character(task_data$process_count) else "1"
    )
    html_parts <- c(html_parts, resource_html)
  }
  
  # Get subtask progress
  subtasks <- tryCatch({
    tasker::get_subtask_progress(run_id)
  }, error = function(e) NULL)
  
  if (!is.null(subtasks) && nrow(subtasks) > 0) {
    html_parts <- c(html_parts, "<h4 class='process-info-header'>Subtask Progress</h4>")
    
    # Build subtask table
    table_rows <- lapply(seq_len(nrow(subtasks)), function(i) {
      st <- subtasks[i, ]
      duration <- tryCatch({
        start_val <- st$start_time
        if (!is.null(start_val) && !is.na(start_val)) {
          format_duration(start_val, st$last_update)
        } else {
          "-"
        }
      }, error = function(e) "-")
      
      items_display <- tryCatch({
        items_complete_val <- st$items_complete
        items_total_val <- st$items_total
        
        if (!is.null(items_complete_val) && !is.na(items_complete_val) && 
            !is.null(items_total_val) && !is.na(items_total_val)) {
          sprintf("%d / %d", as.integer(items_complete_val), as.integer(items_total_val))
        } else {
          "-"
        }
      }, error = function(e) "-")
      
      progress_display <- tryCatch({
        items_complete_val <- st$items_complete
        items_total_val <- st$items_total
        
        if (!is.null(items_complete_val) && !is.na(items_complete_val) &&
            !is.null(items_total_val) && !is.na(items_total_val) && items_total_val > 0) {
          progress_pct <- (as.numeric(items_complete_val) / as.numeric(items_total_val)) * 100
          sprintf("%.1f%%", progress_pct)
        } else {
          # Fallback to database percent_complete if items not available
          progress_val <- st$percent_complete
          if (!is.null(progress_val) && !is.na(progress_val)) {
            sprintf("%.1f%%", as.numeric(progress_val))
          } else {
            "0%"
          }
        }
      }, error = function(e) "0%")
      
      # Create reactive output ID for this completion estimate
      estimate_output_id <- paste0("completion_estimate_", gsub("[^a-zA-Z0-9]", "_", task_data$run_id), "_", st$subtask_number)
      completion_estimate <- paste0('<div id="', estimate_output_id, '" class="shiny-text-output">Computing...</div>')
      
      sprintf(
        "<tr>
          <td>%d</td>
          <td>%s</td>
          <td>%s</td>
          <td>%s</td>
          <td>%s</td>
          <td>%s</td>
          <td>%s</td>
          <td>%s</td>
        </tr>",
        as.integer(st$subtask_number),
        htmltools::htmlEscape(if (!is.null(st$subtask_name) && !is.na(st$subtask_name)) st$subtask_name else "Unnamed"),
        badge_html(st$status),
        progress_display,
        items_display,
        htmltools::htmlEscape(if (!is.null(st$progress_message) && !is.na(st$progress_message)) st$progress_message else ""),
        duration,
        completion_estimate
      )
    })
    
    subtask_table <- sprintf(
      "<table class='subtask-table'>
        <thead>
          <tr>
            <th>#</th>
            <th>Subtask Name</th>
            <th>Status</th>
            <th>Progress</th>
            <th>Items</th>
            <th>Message</th>
            <th>Duration</th>
            <th>Est. Completion</th>
          </tr>
        </thead>
        <tbody>
          %s
        </tbody>
      </table>",
      paste(table_rows, collapse = "\n")
    )
    
    html_parts <- c(html_parts, subtask_table)
    
    # Create reactive outputs for completion estimates (if output object provided)
    if (!is.null(output)) {
      for (i in seq_len(nrow(subtasks))) {
        local({
          # Create local copies for closure
          st <- subtasks[i, ]
          local_run_id <- task_data$run_id
          local_subtask_number <- st$subtask_number
          local_status <- st$status
          local_items_total <- st$items_total
          local_stage_name <- stage_name
          local_task_name <- task_name
          local_output_id <- paste0("completion_estimate_", gsub("[^a-zA-Z0-9]", "_", local_run_id), "_", local_subtask_number)
          
          # Create reactive output if it doesn't exist
          if (!local_output_id %in% names(output)) {
            output[[local_output_id]] <- renderText({
              # Force re-execution every 5 seconds to pick up new progress snapshots
              invalidateLater(5000, session)
              
              # Also depend on task_reactives for immediate updates when task changes
              task_key <- paste0(local_stage_name, "__", local_task_name)
              task_data <- task_reactives[[task_key]]
              
              # Read current status from local copies
              status_safe <- if (!is.null(local_status)) as.character(local_status) else "UNKNOWN"
              items_total_safe <- if (!is.null(local_items_total) && !is.na(local_items_total)) as.numeric(local_items_total) else 0
              
              if (status_safe %in% c("RUNNING", "STARTED") && items_total_safe > 0 && !is.null(local_run_id) && !is.na(local_run_id)) {
                # Read from environment - this will update every 5 seconds due to invalidateLater
                estimate <- tasker::get_completion_estimate(progress_history_env, local_run_id, local_subtask_number, quiet = TRUE)
                completion_text <- tasker::format_completion_with_ci(estimate, quiet = TRUE)
                if (is.null(completion_text) || completion_text == "") {
                  "Computing..."
                } else {
                  completion_text
                }
              } else if (status_safe %in% c("COMPLETED", "FAILED", "SKIPPED")) {
                toupper(status_safe)
              } else {
                "--"
              }
            })
          }
        })
      }
    }
  }
  
  HTML(paste(html_parts, collapse = "\n"))
}

server <- function(input, output, session) {
  # ============================================================================
  # INITIALIZATION: Get structure once at startup
  # ============================================================================
  
  # Reactive values for general app state
  rv <- reactiveValues(
    selected_task_id = NULL,
    last_update = NULL,
    error_message = NULL,
    force_refresh = 0,
    reset_pending_stage = NULL,
    reset_pending_task = NULL,
    # Expandable panes state
    expanded_process_panes = c(),
    expanded_log_panes = c(),
    # Per-task log settings (stored as list with task_id as key)
    log_settings = list(),
    # Trigger for log refresh (increment to force re-render)
    log_refresh_trigger = 0,
    # Track last file positions for incremental log reading
    log_last_positions = list(),
    # Flag to track if initial auto-expand has been performed
    initial_auto_expand_done = FALSE,
    # Track previous stage statuses to detect transitions
    stage_previous_statuses = list(),
    # Database connection for SQL queries monitoring (reused)
    monitor_connection = NULL
  )
  
  # Cleanup database connection when session ends
  onSessionEnded(function() {
    if (!is.null(rv$monitor_connection) && DBI::dbIsValid(rv$monitor_connection)) {
      try({
        DBI::dbDisconnect(rv$monitor_connection)
        message("Disconnected monitor database connection")
      }, silent = TRUE)
    }
  })
  
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
  
  # ============================================================================
  # PROGRESS DATA HARVESTING: Storage for completion time prediction
  # ============================================================================
  
  
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
          items_complete = 0,
          log_path = task$log_path,
          log_filename = task$log_filename
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
    
    # Get list of task keys that exist in current_status
    current_task_keys <- if (!is.null(current_status) && nrow(current_status) > 0) {
      paste(current_status$stage_name, current_status$task_name, sep = "||")
    } else {
      character(0)
    }
    
    # Check for tasks that have been reset (exist in task_reactives but not in current_status)
    # These should be set back to NOT_STARTED state
    struct <- pipeline_structure()
    if (!is.null(struct) && !is.null(struct$tasks)) {
      all_task_keys <- paste(struct$tasks$stage_name, struct$tasks$task_name, sep = "||")
      
      # Find tasks that are registered but have no current status (have been reset)
      reset_task_keys <- setdiff(all_task_keys, current_task_keys)
      
      for (task_key in reset_task_keys) {
        current_val <- task_reactives[[task_key]]
        # Only reset if currently showing a status other than NOT_STARTED
        if (!is.null(current_val) && !is.null(current_val$status) && current_val$status != "NOT_STARTED") {
          # Get task info from registered tasks
          parts <- strsplit(task_key, "||", fixed = TRUE)[[1]]
          stage_name <- parts[1]
          task_name <- parts[2]
          
          task_info <- struct$tasks[struct$tasks$stage_name == stage_name & struct$tasks$task_name == task_name, ]
          if (nrow(task_info) > 0) {
            task_reactives[[task_key]] <- list(
              stage_name = stage_name,
              task_name = task_name,
              task_order = task_info$task_order[1],
              status = "NOT_STARTED",
              overall_percent_complete = 0,
              overall_progress_message = "",
              run_id = NA,
              current_subtask = 0,
              total_subtasks = 0,
              items_total = 0,
              items_complete = 0,
              current_subtask_name = "",
              current_subtask_number = 0,
              log_path = task_info$log_path[1],
              log_filename = task_info$log_filename[1]
            )
          }
        }
      }
    }
    
    if (is.null(current_status) || nrow(current_status) == 0) {
      rv$last_update <- Sys.time()
      return()
    }
    
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
          
          # ============================================================================
          # PROGRESS DATA HARVESTING: Capture progress snapshots for statistical prediction
          # ============================================================================
          
          # Create progress snapshot for active subtasks
          if (subtask_info$status %in% c("RUNNING", "STARTED") && items_total > 0) {
            tryCatch({
              run_key <- paste0("run_", task_status$run_id)
              subtask_key <- paste0("subtask_", subtask_info$subtask_number)
              storage_key <- paste0(run_key, "_", subtask_key)
              
              # Get current history list or initialize empty
              if (exists(storage_key, envir = progress_history_env)) {
                history_list <- get(storage_key, envir = progress_history_env)
              } else {
                history_list <- list()
              }
              
              # Create snapshot
              snapshot <- list(
                timestamp = Sys.time(),
                items_complete = items_complete,
                items_total = items_total,
                subtask_name = subtask_info$subtask_name,
                status = subtask_info$status
              )
              
              # Add to history (keep last 100 snapshots per subtask)
              history_list[[length(history_list) + 1]] <- snapshot
              
              # # Debug output
              # message("DEBUG: Created snapshot for ", run_key, " ", subtask_key, 
              #         " - total snapshots: ", length(history_list))
              
              # Trim to last 100 snapshots to prevent memory bloat
              if (length(history_list) > 100) {
                history_list <- history_list[(length(history_list) - 99):length(history_list)]
              }
              
              # Store back to environment
              assign(storage_key, history_list, envir = progress_history_env)
              
              # Verify storage
              verified_list <- get(storage_key, envir = progress_history_env)
              # message("DEBUG: Verified storage - ", run_key, " ", subtask_key, 
              #         " now has ", length(verified_list), " snapshots")
            }, error = function(e) {
              message("Error capturing progress snapshot: ", e$message)
            })
          }
        }
      }
      
      # Use task_status directly and just add/modify the fields we need
      new_val <- task_status %>%
        mutate(
          task_order = if (!is.null(current_val)) current_val$task_order else NA,
          items_total = items_total,
          items_complete = items_complete,
          current_subtask_name = if (!is.null(subtask_info) && !is.na(subtask_info$subtask_name)) subtask_info$subtask_name else "",
          current_subtask_number = if (!is.null(subtask_info) && !is.na(subtask_info$subtask_number)) subtask_info$subtask_number else 0
        ) %>%
        as.list()
      
      # Only update if something changed
      if (is.null(current_val) || !identical(current_val, new_val)) {
        task_reactives[[task_key]] <- new_val
      }
    }
    
    rv$last_update <- Sys.time()
  })
  
  # ============================================================================
  # AUTO-EXPAND: Automatically expand stage accordion when status TRANSITIONS to RUNNING/STARTED
  # Only expands on status change, not on every poll
  # ============================================================================
  
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    stages <- struct$stages
    if (is.null(stages) || nrow(stages) == 0) return()
    
    # Trigger on any stage_reactives change
    stage_reactives_list <- reactiveValuesToList(stage_reactives)
    
    # Wait for stage reactives to be populated before doing initial auto-expand
    has_data <- any(sapply(stage_reactives_list, function(x) !is.null(x)))
    if (!has_data) return()
    
    # Check each stage's status and compare with previous status
    lapply(seq_len(nrow(stages)), function(i) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      stage_id <- gsub("[^a-zA-Z0-9]", "_", stage_name)
      
      stage_data <- stage_reactives[[stage_name]]
      
      if (!is.null(stage_data)) {
        current_status <- stage_data$status
        previous_status <- rv$stage_previous_statuses[[stage_name]]
        
        # Store current status for next comparison
        rv$stage_previous_statuses[[stage_name]] <- current_status
        
        # Only auto-expand if status CHANGED TO RUNNING or STARTED
        status_changed_to_active <- !is.null(previous_status) && 
                                     !(previous_status %in% c("RUNNING", "STARTED")) &&
                                     (current_status %in% c("RUNNING", "STARTED"))
        
        # On initial load (previous_status is NULL), expand active stages
        initial_load_active <- is.null(previous_status) && 
                               (current_status %in% c("RUNNING", "STARTED"))
        
        if (status_changed_to_active || initial_load_active) {
          # Use shinyjs to manipulate Bootstrap accordion with delay for DOM readiness
          shinyjs::delay(100, {
            collapse_id <- paste0("collapse_", stage_id)
            button_id <- paste0("heading_", stage_id)
            
            # Only expand if not already expanded (check DOM state to respect manual user actions)
            shinyjs::runjs(sprintf(
              "
              var button = document.querySelector('#%s .accordion-button');
              var collapse = document.getElementById('%s');
              if (button && collapse && !collapse.classList.contains('show')) {
                button.classList.remove('collapsed');
                button.setAttribute('aria-expanded', 'true');
                collapse.classList.add('show');
              }
              ",
              button_id, collapse_id
            ))
          })
        }
      }
    })
    
    # Mark that initial auto-expand has been checked
    if (!rv$initial_auto_expand_done) {
      rv$initial_auto_expand_done <- TRUE
    }
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
      
      # Update stage reactive only if something changed
      new_stage_data <- list(
        completed = completed,
        total = total_tasks,
        progress_pct = progress_pct,
        status = stage_status
      )
      
      current_stage_data <- stage_reactives[[stage_name]]
      
      # Only update if something actually changed
      if (is.null(current_stage_data) || !identical(current_stage_data, new_stage_data)) {
        stage_reactives[[stage_name]] <- new_stage_data
      }
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
      
      # Reset the task reactive to NOT_STARTED state
      task_key <- paste(stage, task, sep = "||")
      if (!is.null(task_reactives[[task_key]])) {
        # Get current task info from registered tasks for log paths
        struct <- pipeline_structure()
        if (!is.null(struct) && !is.null(struct$tasks)) {
          task_info <- struct$tasks[struct$tasks$stage_name == stage & struct$tasks$task_name == task, ]
          if (nrow(task_info) > 0) {
            task_reactives[[task_key]] <- list(
              stage_name = stage,
              task_name = task,
              task_order = task_info$task_order[1],
              status = "NOT_STARTED",
              overall_percent_complete = 0,
              overall_progress_message = "",
              run_id = NA,
              current_subtask = 0,
              total_subtasks = 0,
              items_total = 0,
              items_complete = 0,
              current_subtask_name = "",
              current_subtask_number = 0,
              log_path = task_info$log_path[1],
              log_filename = task_info$log_filename[1]
            )
          }
        }
      }
      
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
  # PIPELINE STATUS UI: Reactive structure with proper Shiny UI elements
  # ============================================================================
  
  # Build the entire accordion UI structure using proper Shiny reactive UI
  output$pipeline_stages_accordion <- renderUI({
    struct <- pipeline_structure()
    if (is.null(struct)) {
      return(div(class = "alert alert-info", "Loading pipeline structure..."))
    }
    
    stages <- struct$stages
    tasks <- struct$tasks
    
    if (is.null(stages) || nrow(stages) == 0) {
      return(div(class = "alert alert-info", "No stages configured"))
    }
    
    if (is.null(tasks) || nrow(tasks) == 0) {
      return(div(class = "alert alert-info", "No tasks registered"))
    }
    
    # Order stages
    stages <- stages[order(stages$stage_order), ]
    
    # Build accordion panels
    accordion_panels <- lapply(seq_len(nrow(stages)), function(i) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      stage_id <- gsub("[^a-zA-Z0-9]", "_", stage_name)
      
      # Get tasks for this stage
      stage_tasks <- tasks[tasks$stage_name == stage_name, ]
      if (nrow(stage_tasks) > 0) {
        stage_tasks <- stage_tasks[order(stage_tasks$task_order), ]
      }
      
      # Build task rows using proper UI elements
      task_rows <- lapply(seq_len(nrow(stage_tasks)), function(j) {
        task <- stage_tasks[j, ]
        task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task$task_name, sep="_"))
        
        tagList(
          div(
            class = "task-row",
            `data-task-id` = task_id,
            # Toggle buttons grouped on the left
            div(
              class = "task-toggle-buttons",
              # Process info toggle button (graph icon)
              tags$button(
                class = "btn-expand-process",
                id = paste0("btn_expand_process_", task_id),
                onclick = sprintf("Shiny.setInputValue('toggle_process_pane', '%s', {priority: 'event'})", task_id),
                "📊"
              ),
              # Log viewer toggle button (file icon)
              tags$button(
                class = "btn-expand-log",
                id = paste0("btn_expand_log_", task_id),
                onclick = sprintf("Shiny.setInputValue('toggle_log_pane', '%s', {priority: 'event'})", task_id),
                "📄"
              )
            ),
            textOutput(paste0("task_name_", task_id), inline = TRUE, container = function(...) div(class = "task-name", ...)),
            uiOutput(paste0("task_status_", task_id), class = "task-status-badge", inline = TRUE),
            uiOutput(paste0("task_progress_", task_id), class = "task-progress-container", inline = TRUE),
            uiOutput(paste0("task_message_", task_id), class = "task-message", inline = TRUE),
            uiOutput(paste0("task_reset_", task_id), class = "task-reset-button", inline = TRUE)
          ),
          # Process status sub-pane (hidden by default)
          div(
            id = paste0("process_pane_", task_id),
            class = "task-subpane process-pane",
            style = "display: none;",
            uiOutput(paste0("process_content_", task_id))
          ),
          # Log viewer sub-pane (hidden by default)
          div(
            id = paste0("log_pane_", task_id),
            class = "task-subpane log-pane",
            style = "display: none;",
            uiOutput(paste0("log_content_", task_id))
          )
        )
      })
      
      # Build accordion panel
      div(
        class = "accordion-item",
        tags$h2(
          class = "accordion-header",
          id = paste0("heading_", stage_id),
          tags$button(
            class = "accordion-button collapsed",
            type = "button",
            `data-bs-toggle` = "collapse",
            `data-bs-target` = paste0("#collapse_", stage_id),
            `aria-expanded` = "false",
            `aria-controls` = paste0("collapse_", stage_id),
            div(
              class = "stage-header",
              div(class = "stage-name", stage_name),
              uiOutput(paste0("stage_badge_", stage_id), class = "stage-badge", inline = TRUE),
              uiOutput(paste0("stage_progress_", stage_id), class = "stage-progress", inline = TRUE),
              uiOutput(paste0("stage_count_", stage_id), class = "stage-count", inline = TRUE)
            )
          )
        ),
        div(
          id = paste0("collapse_", stage_id),
          class = "accordion-collapse collapse",
          `aria-labelledby` = paste0("heading_", stage_id),
          div(class = "accordion-body", task_rows)
        )
      )
    })
    
    # Return the complete accordion
    div(class = "accordion", id = "pipeline_stages_accordion_inner", accordion_panels)
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
      
      # Create renderUI blocks for stage components
      (function(stage_name_local, stage_id_local) {
        
        # Badge - reactive renderUI
        output[[paste0("stage_badge_", stage_id_local)]] <- renderUI({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            HTML(badge_html(stage_data$status))
          }
        })
        
        # Progress bar - reactive renderUI  
        output[[paste0("stage_progress_", stage_id_local)]] <- renderUI({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            HTML(stage_progress_html(stage_data$progress_pct, stage_data$status))
          }
        })
        
        # Count - reactive renderUI
        output[[paste0("stage_count_", stage_id_local)]] <- renderUI({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            span(sprintf("%d/%d", stage_data$completed, stage_data$total))
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
    
    # For each task, create individual reactive outputs using renderUI
    lapply(seq_len(nrow(tasks)), function(i) {
      task <- tasks[i, ]
      stage_name <- task$stage_name
      task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task$task_name, sep="_"))
      task_key <- paste(stage_name, task$task_name, sep = "||")
      
      # Create renderUI blocks for task components
      (function(task_key_local, task_id_local, stage_name_local, task_name_local) {
        
        # Task name display - reactive renderText (toggles between task_name and script_filename)
        output[[paste0("task_name_", task_id_local)]] <- renderText({
          show_script <- input$show_script_name
          # Find the task in pipeline structure to get script_filename
          struct <- pipeline_structure()
          if (!is.null(struct) && !is.null(struct$tasks)) {
            task_info <- struct$tasks[struct$tasks$stage_name == stage_name_local & 
                                      struct$tasks$task_name == task_name_local, ]
            if (nrow(task_info) > 0) {
              script_filename <- task_info$script_filename[1]
              if (!is.null(show_script) && show_script && 
                  !is.null(script_filename) && !is.na(script_filename) && nchar(script_filename) > 0) {
                return(script_filename)
              }
            }
          }
          # Default to task_name
          task_name_local
        })
        
        # Status badge - reactive renderUI
        output[[paste0("task_status_", task_id_local)]] <- renderUI({
          task_data <- task_reactives[[task_key_local]]
          task_status <- if (!is.null(task_data)) task_data$status else "NOT_STARTED"
          HTML(badge_html(task_status))
        })
        
        # Progress bars with enhanced subtask information - reactive renderUI
        output[[paste0("task_progress_", task_id_local)]] <- renderUI({
          task_data <- task_reactives[[task_key_local]]
          HTML(task_progress_html(task_data))
        })
        
        # Message with enhanced subtask details - reactive renderUI
        output[[paste0("task_message_", task_id_local)]] <- renderUI({
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
          
          div(class = "task-message", title = message_text, message_text)
        })
        
        # Reset button - reactive renderUI
        output[[paste0("task_reset_", task_id_local)]] <- renderUI({
          tags$button(
            id = paste0("reset_btn_", task_id_local),
            class = "btn btn-sm btn-warning task-reset-btn",
            title = "Reset this task to NOT_STARTED",
            onclick = sprintf(
              "Shiny.setInputValue('task_reset_clicked', {stage: '%s', task: '%s', timestamp: Date.now()}, {priority: 'event'})",
              htmltools::htmlEscape(stage_name_local),
              htmltools::htmlEscape(task_name_local)
            ),
            "Reset"
          )
        })
      })(task_key, task_id, stage_name, task$task_name)
    })
  })
  
  # ============================================================================
  # EXPANDABLE PANES: Reactive Content
  # ============================================================================
  
  # Create reactive outputs for process pane content
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    tasks <- struct$tasks
    if (is.null(tasks) || nrow(tasks) == 0) return()
    
    lapply(seq_len(nrow(tasks)), function(i) {
      task <- tasks[i, ]
      stage_name <- task$stage_name
      task_name <- task$task_name
      task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task_name, sep="_"))
      task_key <- paste(stage_name, task_name, sep = "||")
      
      (function(task_key_local, task_id_local, stage_name_local, task_name_local) {
        # Process pane content - only update when pane is expanded
        output[[paste0("process_content_", task_id_local)]] <- renderUI({
          # Only render if this pane is expanded
          if (!(task_id_local %in% rv$expanded_process_panes)) {
            return(NULL)
          }
          
          task_data <- task_reactives[[task_key_local]]
          build_process_status_html(task_data, stage_name_local, task_name_local, progress_history_env, output, task_reactives, session)
        })
        
        # Log pane content - static UI structure with controls
        output[[paste0("log_content_", task_id_local)]] <- renderUI({
          # Only render if this pane is expanded
          if (!(task_id_local %in% rv$expanded_log_panes)) {
            return(NULL)
          }
          
          # Get log settings for this task
          settings <- rv$log_settings[[task_id_local]]
          if (is.null(settings)) {
            settings <- list(
              num_lines = 5,
              tail_mode = TRUE,
              auto_refresh = TRUE,
              filter = ""
            )
          }
          
          # Build static controls
          tagList(
            div(
              class = "log-controls-container",
              div(
                class = "log-controls",
                selectInput(
                  paste0("log_lines_", task_id_local),
                  NULL,
                  choices = c(
                    "Last 5 lines" = 5,
                    "Last 10 lines" = 10,
                    "Last 25 lines" = 25,
                    "Last 50 lines" = 50,
                    "Last 100 lines" = 100,
                    "Full log" = -1
                  ),
                  selected = settings$num_lines,
                  width = "140px"
                ),
                checkboxInput(
                  paste0("log_tail_", task_id_local),
                  "Tail mode",
                  value = settings$tail_mode
                ),
                checkboxInput(
                  paste0("log_auto_refresh_", task_id_local),
                  "Auto-refresh",
                  value = settings$auto_refresh
                ),
                actionButton(
                  paste0("log_refresh_", task_id_local),
                  "Refresh",
                  icon = icon("sync"),
                  class = "btn-sm btn-primary"
                )
              )
            ),
            # Terminal container with dynamic content
            div(
              class = "log-terminal",
              htmlOutput(paste0("log_text_", task_id_local))
            )
          )
        })
        
        # Log text content - incremental updates using observer
        observe({
          # Only process if this pane is expanded
          if (!(task_id_local %in% rv$expanded_log_panes)) {
            return()
          }
          
          # Depend on log_refresh_trigger to re-render when settings change
          rv$log_refresh_trigger
          
          # Get log settings for this task
          settings <- rv$log_settings[[task_id_local]]
          if (is.null(settings)) {
            settings <- list(
              num_lines = 5,
              tail_mode = TRUE,
              auto_refresh = TRUE,
              filter = ""
            )
          }
          
          # Auto-refresh support
          if (settings$auto_refresh && task_id_local %in% rv$expanded_log_panes) {
            invalidateLater(2000)  # Refresh every 2 seconds
          }
          
          task_data <- task_reactives[[task_key_local]]
          
          # Determine log file location
          log_path <- task_data$log_path
          if (is.null(log_path) || is.na(log_path) || log_path == "") {
            log_path <- getOption("tasker.config")$logging$log_dir
          }
          if (is.null(log_path) || is.na(log_path) || log_path == "") {
            log_path <- path.expand("~/fccData/inst/scripts")
          }
          
          # Determine log filename
          log_file <- NULL
          if (!is.null(task_data$log_filename) && !is.na(task_data$log_filename)) {
            log_file <- file.path(log_path, task_data$log_filename)
          } else {
            potential_log <- file.path(log_path, paste0(task_name_local, ".Rout"))
            if (file.exists(potential_log)) {
              log_file <- potential_log
            }
          }
          
          if (is.null(log_file) || !file.exists(log_file)) {
            # For FAILED tasks, try looking for error log with "-error" suffix
            if (!is.null(task_data$status) && task_data$status == "FAILED" && !is.null(log_file)) {
              # Try adding -error to the full filename (makefile appends to full name)
              error_log_file <- paste0(log_file, "-error")
              
              if (file.exists(error_log_file)) {
                log_file <- error_log_file
              }
            }
          }
          
          if (is.null(log_file) || !file.exists(log_file)) {
            # Show helpful message when no log file is available
            task_status <- task_data$status %||% "NOT_STARTED"
            
            no_log_message <- if (is.null(log_file)) {
              sprintf(
                "<div class='log-file-info-bar'>
                  <span><strong>Task:</strong> %s</span>
                  <span><strong>Status:</strong> %s</span>
                  <span><strong>Log:</strong> Not configured</span>
                </div>
                <div class='log-line' style='padding: 20px; text-align: center; color: #888;'>
                  <div style='margin-bottom: 10px;'><strong>No log file configured for this task</strong></div>
                  <div>Log files are typically created when a task is executed.</div>
                  <div>Expected location: %s/%s.Rout</div>
                </div>",
                htmltools::htmlEscape(task_name_local),
                htmltools::htmlEscape(task_status),
                htmltools::htmlEscape(log_path),
                htmltools::htmlEscape(task_name_local)
              )
            } else {
              sprintf(
                "<div class='log-file-info-bar'>
                  <span><strong>File:</strong> %s</span>
                  <span><strong>Status:</strong> %s</span>
                  <span><strong>State:</strong> File not found</span>
                </div>
                <div class='log-line' style='padding: 20px; text-align: center; color: #888;'>
                  <div style='margin-bottom: 10px;'><strong>Log file not found</strong></div>
                  <div>Expected: %s</div>
                  <div style='margin-top: 10px;'>This file will be created when the task runs.</div>
                </div>",
                htmltools::htmlEscape(basename(log_file)),
                htmltools::htmlEscape(task_status),
                htmltools::htmlEscape(log_file)
              )
            }
            
            # Update the output with the no-log message
            output[[paste0("log_text_", task_id_local)]] <- renderUI({
              HTML(no_log_message)
            })
            return()
          }
          
          # Get last position for this log
          pos_key <- paste0(task_id_local, "_", log_file)
          last_pos <- rv$log_last_positions[[pos_key]]
          if (is.null(last_pos)) {
            last_pos <- list(line_count = 0, display_mode = paste(settings$num_lines, settings$tail_mode))
          }
          
          # Check if display settings changed (requires full refresh)
          current_mode <- paste(settings$num_lines, settings$tail_mode)
          settings_changed <- (last_pos$display_mode != current_mode)
          
          # Read log file
          all_lines <- tryCatch({
            readLines(log_file, warn = FALSE)
          }, error = function(e) {
            return(character(0))
          })
          
          if (length(all_lines) == 0) {
            return()
          }
          
          # Determine which lines to show
          num_to_read <- if (settings$num_lines <= -1) length(all_lines) else settings$num_lines
          if (settings$tail_mode) {
            lines_to_show <- tail(all_lines, num_to_read)
            start_line <- max(1, length(all_lines) - num_to_read + 1)
          } else {
            lines_to_show <- head(all_lines, num_to_read)
            start_line <- 1
          }
          
          # If settings changed or this is first load, replace all content
          if (settings_changed || last_pos$line_count == 0) {
            # Format all lines
            formatted_lines <- sapply(lines_to_show, function(line) {
              line <- htmltools::htmlEscape(line)
              class_attr <- ""
              if (grepl("ERROR|FAIL", line)) {
                class_attr <- " log-line-error"
              } else if (grepl("WARN", line)) {
                class_attr <- " log-line-warning"
              } else if (grepl("INFO", line)) {
                class_attr <- " log-line-info"
              }
              paste0("<div class='log-line", class_attr, "'>", line, "</div>")
            }, USE.NAMES = FALSE)
            
            # Build file info header
            file_info <- sprintf(
              "<div class='log-file-info-bar'>
                <span><strong>File:</strong> %s</span>
                <span><strong>Lines:</strong> %s</span>
                <span><strong>Updated:</strong> %s</span>
              </div>",
              htmltools::htmlEscape(basename(log_file)),
              length(lines_to_show),
              format(Sys.time(), "%H:%M:%S")
            )
            
            content <- paste0(file_info, paste(formatted_lines, collapse = ""))
            
            # Replace entire content using renderUI output
            output[[paste0("log_text_", task_id_local)]] <- renderUI({
              HTML(content)
            })
            
            # Update position tracker
            rv$log_last_positions[[pos_key]] <- list(
              line_count = length(all_lines),
              last_end_line = start_line + length(lines_to_show) - 1,
              display_mode = current_mode
            )
          } else if (settings$tail_mode && length(all_lines) > last_pos$line_count) {
            # Tail mode: Append new lines
            new_line_count <- length(all_lines) - last_pos$line_count
            new_lines <- tail(all_lines, new_line_count)
            
            # Format new lines
            formatted_new_lines <- sapply(new_lines, function(line) {
              line <- htmltools::htmlEscape(line)
              class_attr <- ""
              if (grepl("ERROR|FAIL", line)) {
                class_attr <- " log-line-error"
              } else if (grepl("WARN", line)) {
                class_attr <- " log-line-warning"
              } else if (grepl("INFO", line)) {
                class_attr <- " log-line-info"
              }
              paste0("<div class='log-line", class_attr, "'>", line, "</div>")
            }, USE.NAMES = FALSE)
            
            # Append using JavaScript
            new_content <- paste(formatted_new_lines, collapse = "")
            log_text_id <- paste0("log_text_", task_id_local)
            
            shinyjs::runjs(sprintf(
              "var elem = document.getElementById('%s');
               if (elem) {
                 var wasAtBottom = elem.scrollHeight - elem.scrollTop <= elem.clientHeight + 50;
                 elem.insertAdjacentHTML('beforeend', %s);
                 if (wasAtBottom) {
                   elem.scrollTop = elem.scrollHeight;
                 }
               }",
              log_text_id,
              jsonlite::toJSON(new_content, auto_unbox = TRUE)
            ))
            
            # Update line info bar
            file_info <- sprintf(
              "<div class='log-file-info-bar'>
                <span><strong>File:</strong> %s</span>
                <span><strong>Lines:</strong> %s</span>
                <span><strong>Updated:</strong> %s</span>
              </div>",
              htmltools::htmlEscape(basename(log_file)),
              length(lines_to_show),
              format(Sys.time(), "%H:%M:%S")
            )
            
            shinyjs::runjs(sprintf(
              "var elem = document.getElementById('%s');
               if (elem) {
                 var infoBar = elem.querySelector('.log-file-info-bar');
                 if (infoBar) {
                   infoBar.outerHTML = %s;
                 }
               }",
              log_text_id,
              jsonlite::toJSON(file_info, auto_unbox = TRUE)
            ))
            
            # Update position tracker
            rv$log_last_positions[[pos_key]] <- list(
              line_count = length(all_lines),
              last_end_line = length(all_lines),
              display_mode = current_mode
            )
          }
        })
        
        # Initial render for log text output
        output[[paste0("log_text_", task_id_local)]] <- renderUI({
          NULL  # Will be populated by observer
        })
      })(task_key, task_id, stage_name, task_name)
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
  
  # ============================================================================
  # EXPANDABLE PANES: Toggle Event Handlers
  # ============================================================================
  
  # Process pane toggle handler
  observeEvent(input$toggle_process_pane, {
    task_id <- input$toggle_process_pane
    
    # Toggle expanded state
    if (task_id %in% rv$expanded_process_panes) {
      rv$expanded_process_panes <- setdiff(rv$expanded_process_panes, task_id)
      # Hide the pane
      shinyjs::hide(paste0("process_pane_", task_id))
      # Remove expanded class from button
      shinyjs::removeClass(paste0("btn_expand_process_", task_id), "expanded")
    } else {
      rv$expanded_process_panes <- c(rv$expanded_process_panes, task_id)
      # Show the pane
      shinyjs::show(paste0("process_pane_", task_id))
      # Add expanded class to button
      shinyjs::addClass(paste0("btn_expand_process_", task_id), "expanded")
    }
  })
  
  # Log pane toggle handler
  observeEvent(input$toggle_log_pane, {
    task_id <- input$toggle_log_pane
    
    # Initialize log settings for this task if not exists
    init_log_settings(rv, task_id)
    
    # Toggle expanded state
    if (task_id %in% rv$expanded_log_panes) {
      rv$expanded_log_panes <- setdiff(rv$expanded_log_panes, task_id)
      # Hide the pane
      shinyjs::hide(paste0("log_pane_", task_id))
      # Remove expanded class from button
      shinyjs::removeClass(paste0("btn_expand_log_", task_id), "expanded")
    } else {
      rv$expanded_log_panes <- c(rv$expanded_log_panes, task_id)
      # Show the pane
      shinyjs::show(paste0("log_pane_", task_id))
      # Add expanded class to button
      shinyjs::addClass(paste0("btn_expand_log_", task_id), "expanded")
    }
  })
  
  # ============================================================================
  # LOG CONTROLS: Dynamic observers for log viewer settings
  # ============================================================================
  
  # Observer to create reactive handlers for each task's log controls
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    tasks <- struct$tasks
    if (is.null(tasks) || nrow(tasks) == 0) return()
    
    # Create observers for each task's log controls
    lapply(seq_len(nrow(tasks)), function(i) {
      task <- tasks[i, ]
      stage_name <- task$stage_name
      task_name <- task$task_name
      task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task_name, sep="_"))
      
      # Observer for num_lines dropdown
      observeEvent(input[[paste0("log_lines_", task_id)]], {
        new_value <- as.numeric(input[[paste0("log_lines_", task_id)]])
        
        # Initialize settings if not exists
        init_log_settings(rv, task_id)
        
        # Update num_lines setting
        rv$log_settings[[task_id]]$num_lines <- new_value
        # Trigger re-render
        rv$log_refresh_trigger <- rv$log_refresh_trigger + 1
      }, ignoreInit = TRUE)
      
      # Observer for tail_mode checkbox
      observeEvent(input[[paste0("log_tail_", task_id)]], {
        new_value <- input[[paste0("log_tail_", task_id)]]
        
        init_log_settings(rv, task_id)
        
        rv$log_settings[[task_id]]$tail_mode <- new_value
        # Trigger re-render
        rv$log_refresh_trigger <- rv$log_refresh_trigger + 1
      }, ignoreInit = TRUE)
      
      # Observer for auto_refresh checkbox
      observeEvent(input[[paste0("log_auto_refresh_", task_id)]], {
        new_value <- input[[paste0("log_auto_refresh_", task_id)]]
        
        init_log_settings(rv, task_id)
        
        rv$log_settings[[task_id]]$auto_refresh <- new_value
        # Trigger re-render
        rv$log_refresh_trigger <- rv$log_refresh_trigger + 1
      }, ignoreInit = TRUE)
      
      # Observer for refresh button
      observeEvent(input[[paste0("log_refresh_", task_id)]], {
        # Trigger re-render
        rv$log_refresh_trigger <- rv$log_refresh_trigger + 1
      }, ignoreInit = TRUE)
    })
  })
  
  # ============================================================================
  # SQL QUERIES TAB
  # ============================================================================
  
  # Initialize trigger
  rv$sql_trigger <- Sys.time()
  
  # Manual refresh button for SQL queries
  observeEvent(input$sql_refresh_now, {
    rv$sql_trigger <- Sys.time()
  })
  
  # Fetch SQL queries
  sql_queries_data <- reactive({
    # Depend on main auto-refresh and manual trigger
    autoRefresh()
    rv$sql_trigger
    
    tryCatch({
      config <- getOption("tasker.config")
      if (is.null(config)) {
        showNotification("Tasker configuration not loaded", type = "error", duration = 5)
        return(data.frame(
          pid = integer(0),
          duration = character(0),
          username = character(0),
          query = character(0),
          state = character(0),
          stringsAsFactors = FALSE
        ))
      }
      
      # Get or create database connection (reused across refreshes)
      con <- tasker::get_monitor_connection(config, rv$monitor_connection)
      
      # Update stored connection for reuse
      rv$monitor_connection <- con
      
      # Get active queries using utility function
      queries <- tasker::get_database_queries(con, config$database$driver %||% "postgresql")
      
      # Show notification if no queries
      if (is.null(queries) || nrow(queries) == 0) {
        showNotification("No active queries", type = "message", duration = 3)
      }
      
      return(queries)
      
    }, error = function(e) {
      showNotification(
        sprintf("Error fetching SQL queries: %s", conditionMessage(e)),
        type = "error",
        duration = 10
      )
      return(data.frame(
        pid = integer(0),
        duration = character(0),
        username = character(0),
        query = character(0),
        state = character(0),
        stringsAsFactors = FALSE
      ))
    })
  })
  
  # Render SQL queries table - initial render with proper column structure
  output$sql_queries_table <- renderDT({
    # Start with empty data frame with proper columns
    initial_data <- data.frame(
      pid = integer(0),
      duration = character(0),
      username = character(0),
      query = character(0),
      state = character(0),
      stringsAsFactors = FALSE
    )
    
    datatable(
      initial_data,
      options = list(
        pageLength = 25,
        scrollX = TRUE,
        scrollY = "60vh",
        scrollCollapse = TRUE,
        dom = 'frtip',
        ordering = TRUE
      ),
      rownames = FALSE,
      filter = 'top',
      class = 'cell-border stripe'
    )
  })
  
  # Update SQL queries table content using proxy
  observe({
    queries <- sql_queries_data()
    
    # Use proxy to update data without recreating the table
    proxy <- dataTableProxy('sql_queries_table')
    
    # Always pass queries (which has proper column structure)
    replaceData(proxy, queries, resetPaging = FALSE, rownames = FALSE)
  })
}
