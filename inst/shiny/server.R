library(shiny)
library(bslib)
library(DT)
library(tasker)
library(dplyr)
library(lubridate)
library(shinyWidgets)
library(shinyjs)
library(htmltools)
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

# Centralized stage progress calculation
calculate_stage_progress <- function(stage_tasks) {
  if (is.null(stage_tasks) || length(stage_tasks) == 0) {
    return(list(percentage = 0, completed = 0, total = 0, label = "0/0 (0%)", width = 0))
  }
  
  completed_count <- sum(sapply(stage_tasks, function(t) t$status == "COMPLETED"), na.rm = TRUE)
  total_count <- length(stage_tasks)
  percentage <- if (total_count > 0) round(100 * completed_count / total_count, 1) else 0
  
  list(
    percentage = percentage,
    completed = completed_count,
    total = total_count,
    label = sprintf("%d/%d (%.1f%%)", completed_count, total_count, percentage),
    width = percentage
  )
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
# Centralized progress calculation function
calculate_task_progress <- function(task_data) {
  if (is.null(task_data)) {
    return(list(percentage = 0, width = 0, label = "Task:", status_class = "primary"))
  }
  
  task_status <- task_data$status
  task_progress <- if (!is.na(task_data$overall_percent_complete)) task_data$overall_percent_complete else 0
  current_subtask <- if (!is.na(task_data$current_subtask)) task_data$current_subtask else 0
  total_subtasks <- if (!is.na(task_data$total_subtasks)) task_data$total_subtasks else 0
  items_total <- if (!is.na(task_data$items_total)) task_data$items_total else 0
  items_complete <- if (!is.na(task_data$items_complete)) task_data$items_complete else 0
  
  # Debug logging to understand subtask detection (DISABLED)
  # if (total_subtasks > 0) {
  #   message(sprintf("DEBUG: Task with subtasks - status=%s, total=%d, completed=%s", 
  #                  task_status, total_subtasks, 
  #                  if(is.null(task_data$completed_subtasks)) "NULL" else as.character(task_data$completed_subtasks)))
  # }
  # Note: Removed noisy debug message about no subtasks detected
  
  # Calculate effective progress - prioritize subtask completion when available
  # Count actual completed subtasks, not current_subtask number
  if (total_subtasks > 0) {
    # Count completed subtasks from task_data if available
    completed_count <- if (!is.null(task_data$completed_subtasks) && !is.na(task_data$completed_subtasks)) {
      task_data$completed_subtasks
    } else if (!is.null(task_data$current_subtask) && !is.na(task_data$current_subtask)) {
      # For running tasks, assume subtasks before current are complete
      # But don't count the current subtask as complete unless status is COMPLETED
      if (task_status == "COMPLETED") {
        total_subtasks  # All subtasks complete
      } else {
        max(0, current_subtask - 1)  # Only count previous subtasks as complete
      }
    } else {
      0
    }
    
    # Log when we successfully use subtask progress (DISABLED)
    # if (total_subtasks > 0) {
    #   message(sprintf("Using subtask progress: %d/%d", completed_count, total_subtasks))
    # }
    
    effective_progress <- round(100 * completed_count / total_subtasks, 1)
    use_subtasks <- TRUE
  } else {
    # Use items progress (task-level or subtask items)
    # Note: Subtask display and items progress are independent features
    
    if (items_total > 1 && items_complete > 0) {
      effective_progress <- round(100 * items_complete / items_total, 1)
    } else if (!is.na(task_progress) && task_progress > 0) {
      effective_progress <- task_progress
    } else {
      effective_progress <- 0
    }
    use_subtasks <- FALSE
  }
  
  # Build enhanced progress bar labels with subtask information
  if (task_status == "COMPLETED") {
    if (total_subtasks > 0 && use_subtasks) {
      label <- sprintf("Task: %d/%d (100%%)", as.integer(total_subtasks), as.integer(total_subtasks))
    } else {
      label <- "Task: 100%"
    }
  } else if (task_status == "FAILED") {
    if (total_subtasks > 0 && use_subtasks) {
      completed_count <- if (!is.null(task_data$completed_subtasks) && !is.na(task_data$completed_subtasks)) {
        task_data$completed_subtasks
      } else {
        max(0, current_subtask - 1)
      }
      if (!is.null(task_data$current_subtask_name) && task_data$current_subtask_name != "") {
        label <- sprintf("Task: %d/%d (%.1f%%) - Subtask %d.%d | %s", 
               as.integer(completed_count), as.integer(total_subtasks), effective_progress,
               as.integer(current_subtask), 
               as.integer(if (!is.na(task_data$current_subtask_number)) task_data$current_subtask_number else 1),
               task_data$current_subtask_name)
      } else {
        label <- sprintf("Task: %d/%d (%.1f%%)", as.integer(completed_count), as.integer(total_subtasks), effective_progress)
      }
    } else {
      label <- sprintf("Task: %.1f%%", effective_progress)
    }
  } else if (task_status %in% c("RUNNING", "STARTED")) {
    if (total_subtasks > 0 && use_subtasks) {
      completed_count <- if (!is.null(task_data$completed_subtasks) && !is.na(task_data$completed_subtasks)) {
        task_data$completed_subtasks
      } else {
        max(0, current_subtask - 1)
      }
      if (!is.null(task_data$current_subtask_name) && task_data$current_subtask_name != "") {
        label <- sprintf("Task: %d/%d (%.1f%%) - Subtask %d.%d | %s", 
               as.integer(completed_count), as.integer(total_subtasks), effective_progress,
               as.integer(current_subtask),
               as.integer(if (!is.na(task_data$current_subtask_number)) task_data$current_subtask_number else 1),
               task_data$current_subtask_name)
      } else {
        label <- sprintf("Task: %d/%d (%.1f%%)", as.integer(completed_count), as.integer(total_subtasks), effective_progress)
      }
    } else {
      label <- sprintf("Task: %.1f%%", effective_progress)
    }
  } else {
    label <- "Task:"
  }
  
  # Calculate display width
  if (task_status == "COMPLETED") {
    width <- 100
  } else if (task_status == "FAILED") {
    width <- effective_progress
  } else if (task_status == "RUNNING") {
    # Show minimum progress to indicate activity
    min_width <- if (total_subtasks > 0) (0.5 / total_subtasks) * 100 else 0.5
    width <- max(effective_progress, min_width)
  } else if (task_status == "STARTED") {
    # Show minimum progress to indicate activity
    min_width <- if (total_subtasks > 0) (0.5 / total_subtasks) * 100 else 0.5
    width <- max(effective_progress, min_width)
  } else if (task_status == "NOT_STARTED") {
    width <- 0
  } else {
    width <- 0
  }
  
  # Determine progress bar style
  status_class <- switch(task_status,
    "COMPLETED" = "success",
    "RUNNING" = "warning", 
    "FAILED" = "danger",
    "STARTED" = "info",
    "primary"
  )
  
  return(list(
    percentage = effective_progress,
    width = width,
    label = label,
    status_class = status_class
  ))
}

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
  
  # Calculate progress using centralized function
  progress_info <- calculate_task_progress(task_data)
  task_status <- task_data$status
  items_total <- if (!is.na(task_data$items_total)) task_data$items_total else 0
  items_complete <- if (!is.na(task_data$items_complete)) task_data$items_complete else 0
  
  show_dual <- (items_total > 1 && task_status != "COMPLETED")
  
  # Build primary progress bar HTML
  if (progress_info$width > 0) {
    progress_html <- sprintf('
        <div class="task-progress" style="height: 16px;">
          <div class="task-progress-fill status-%s" style="width: %.0f%%"></div>
          <span class="task-progress-text">%s</span>
        </div>',
      task_status,
      progress_info$width, progress_info$label
    )
  } else {
    # For NOT_STARTED tasks, render empty progress bar container
    progress_html <- sprintf('
        <div class="task-progress" style="height: 16px;">
          <span class="task-progress-text">%s</span>
        </div>',
      progress_info$label)
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
      <div class="task-progress" style="height: 12px; margin-top: 2px;">
        <div class="item-progress-fill status-%s" style="width: %.2f%%"></div>
        <span class="item-progress-text">Items: %.0f/%.0f (%.1f%%)</span>
      </div>',
      task_status,
      items_pct, items_complete_safe, items_total, round(items_pct, 1)
    ))
  }
  
  return(progress_html)
}

# Generate process status pane HTML
build_process_status_html <- function(task_data, stage_name, task_name, progress_history_env = NULL, output = NULL, task_reactives = NULL, session = NULL, input = NULL) {
  if (is.null(task_data)) {
    return(HTML("<div class='process-info-header'>No task data available</div>"))
  }
  
  # Show basic task info even if never run
  if (is.null(task_data$run_id) || is.na(task_data$run_id)) {
    basic_info <- sprintf(
      "<div class='process-info'>
        <h5 class='process-info-header'>Task Information</h5>
        <div class='process-details compact'>
          <span class='detail-item'><strong>Stage:</strong> %s</span>
          <span class='detail-item'><strong>Task:</strong> %s</span>
          <span class='detail-item'><strong>Status:</strong> %s</span>
          <span class='detail-item'><strong>Last Run:</strong> Never executed</span>
        </div>
        <p style='margin-top: 6px; color: #666; font-size: 12px;'>This task has not been executed yet.</p>
      </div>",
      htmltools::htmlEscape(stage_name),
      htmltools::htmlEscape(task_name), 
      htmltools::htmlEscape(task_data$status %||% "NOT_STARTED")
    )
    return(HTML(basic_info))
  }
  
  run_id <- task_data$run_id
  status <- task_data$status
  
  # Build HTML components
  html_parts <- list()
  
  # Check for process/metrics issues using database fields
  # Priority: collection_error > stale metrics > process dead
  if (!is.null(task_data$metrics_collection_error) && isTRUE(task_data$metrics_collection_error)) {
    # Metrics collection error
    error_msg <- if (!is.null(task_data$metrics_error_message) && !is.na(task_data$metrics_error_message)) {
      sprintf("Metrics collection error: %s", task_data$metrics_error_message)
    } else {
      "Metrics collection failed"
    }
    html_parts <- c(html_parts, sprintf(
      "<div class='process-error-banner'>
        <i class='fa fa-exclamation-triangle'></i>
        <div class='error-text'>%s</div>
      </div>",
      htmltools::htmlEscape(error_msg)
    ))
  } else if (!is.null(task_data$metrics_age_seconds) && !is.na(task_data$metrics_age_seconds)) {
    # Check for stale metrics (>30 seconds old)
    if (status %in% c("RUNNING", "STARTED") && task_data$metrics_age_seconds > 30) {
      html_parts <- c(html_parts, sprintf(
        "<div class='process-warning-banner'>
          <i class='fa fa-exclamation-circle'></i>
          <div class='warning-text'>WARNING: Metrics are stale (%d seconds old) - Reporter may not be running</div>
        </div>",
        as.integer(task_data$metrics_age_seconds)
      ))
    }
  } else if (!is.null(task_data$metrics_is_alive) && !is.na(task_data$metrics_is_alive)) {
    # Check database is_alive field (from process metrics)
    if (status %in% c("RUNNING", "STARTED") && !isTRUE(task_data$metrics_is_alive)) {
      html_parts <- c(html_parts, sprintf(
        "<div class='process-error-banner'>
          <i class='fa fa-exclamation-triangle'></i>
          <div class='error-text'>WARNING: Task marked as %s but process (PID: %s) is not alive</div>
        </div>",
        htmltools::htmlEscape(status),
        htmltools::htmlEscape(as.character(task_data$process_id))
      ))
    }
  }
  
  # Main process info header
  html_parts <- c(html_parts, "<h5 class='process-info-header'>Process Info</h5>")
  
  # Process details
  # Get browser timezone for embedded timestamps (uses shinyTZ automatic detection)
  browser_tz <- tryCatch({
    shinyTZ::get_browser_tz()
  }, error = function(e) {
    # Fallback to TASKER_DISPLAY_TIMEZONE if session not available
    TASKER_DISPLAY_TIMEZONE
  })
  
  process_details <- sprintf(
    "<div class='process-details compact'>
      <span class='detail-item'><strong>PID:</strong> %s</span>
      <span class='detail-item'><strong>Host:</strong> %s</span>
      <span class='detail-item'><strong>Status:</strong> %s</span>
      <span class='detail-item'><strong>Started:</strong> %s</span>
    </div>",
    htmltools::htmlEscape(if (!is.null(task_data$process_id)) as.character(task_data$process_id) else "N/A"),
    htmltools::htmlEscape(if (!is.null(task_data$hostname)) task_data$hostname else "N/A"),
    htmltools::htmlEscape(status),
    htmltools::htmlEscape(if (!is.null(task_data$start_time)) {
      # Use shinyTZ helper to format in browser timezone
      shinyTZ::format_in_tz(task_data$start_time, tz = browser_tz, format = "%Y-%m-%d %H:%M:%S %Z")
    } else "N/A")
  )
  html_parts <- c(html_parts, process_details)
  
  # Check if process is actually dead and update status if needed
  process_is_dead <- FALSE
  if (!is.null(task_data$metrics_is_alive) && !is.na(task_data$metrics_is_alive) && 
      status %in% c("RUNNING", "STARTED") && !isTRUE(task_data$metrics_is_alive)) {
    process_is_dead <- TRUE
    
    # Update task status to FAILED in database
    tryCatch({
      tasker::task_update(
        status = "FAILED",
        error_message = sprintf("Process (PID: %s) terminated unexpectedly", 
                               task_data$process_id),
        run_id = task_data$run_id,
        quiet = TRUE
      )
      
      # Update local status for immediate UI feedback
      status <- "FAILED"
      
    }, error = function(e) {
      message("Failed to update dead process status: ", e$message)
    })
  }
  
  # Resource usage and process state information
  has_current_metrics <- (!is.null(task_data$cpu_percent) && !is.na(task_data$cpu_percent)) || 
                        (!is.null(task_data$memory_mb) && !is.na(task_data$memory_mb)) ||
                        (!is.null(task_data$child_count) && !is.na(task_data$child_count))
  has_any_metrics <- has_current_metrics || (!is.null(task_data$metrics_age_seconds) && !is.na(task_data$metrics_age_seconds))
  
  if (has_current_metrics) {
    # Current process metrics available
    cpu_display <- if (!is.null(task_data$cpu_percent) && !is.na(task_data$cpu_percent)) {
      cpu_text <- sprintf("%.1f%%", task_data$cpu_percent)
      # Add CPU core info if available
      if (!is.null(task_data$cpu_cores) && !is.na(task_data$cpu_cores)) {
        sprintf("%s (%d cores)", cpu_text, as.integer(task_data$cpu_cores))
      } else {
        cpu_text
      }
    } else {
      "N/A"
    }
    
    # Add average and max CPU if available
    cpu_avg_max <- ""
    if (!is.null(task_data$avg_cpu_percent) && !is.na(task_data$avg_cpu_percent) &&
        !is.null(task_data$max_cpu_percent) && !is.na(task_data$max_cpu_percent)) {
      cpu_avg_max <- sprintf(" (avg: %.1f%%, max: %.1f%%)", 
                            task_data$avg_cpu_percent, 
                            task_data$max_cpu_percent)
    }
    cpu_display <- paste0(cpu_display, cpu_avg_max)
    
    memory_display <- if (!is.null(task_data$memory_mb) && !is.na(task_data$memory_mb)) {
      mem_text <- sprintf("%.1f MB (%.1f%%)", task_data$memory_mb, 
              if (!is.null(task_data$memory_percent) && !is.na(task_data$memory_percent)) task_data$memory_percent else 0)
      # Add average and max memory if available
      if (!is.null(task_data$avg_memory_mb) && !is.na(task_data$avg_memory_mb) &&
          !is.null(task_data$max_memory_mb) && !is.na(task_data$max_memory_mb)) {
        mem_text <- sprintf("%s (avg: %.1f MB, max: %.1f MB)", 
                           mem_text,
                           task_data$avg_memory_mb,
                           task_data$max_memory_mb)
      }
      mem_text
    } else {
      "N/A"
    }
    
    # Child process counts
    child_display <- if (!is.null(task_data$child_count) && !is.na(task_data$child_count)) {
      if (task_data$child_count > 0) {
        child_cpu <- if (!is.null(task_data$child_total_cpu_percent) && !is.na(task_data$child_total_cpu_percent)) 
          sprintf(" (%.1f%% CPU)", task_data$child_total_cpu_percent) else ""
        child_mem <- if (!is.null(task_data$child_total_memory_mb) && !is.na(task_data$child_total_memory_mb)) 
          sprintf(" (%.1f MB RAM)", task_data$child_total_memory_mb) else ""
        sprintf("%d children%s%s", as.integer(task_data$child_count), child_cpu, child_mem)
      } else {
        "No children"
      }
    } else {
      "N/A"
    }
    
    # Metrics age for current metrics
    metrics_age_display <- if (!is.null(task_data$metrics_age_seconds) && !is.na(task_data$metrics_age_seconds)) {
      if (task_data$metrics_age_seconds <= 10) {
        "Live"
      } else {
        sprintf("%ds ago", as.integer(task_data$metrics_age_seconds))
      }
    } else {
      "Just collected"
    }
    
    resource_html <- sprintf(
      "<div class='process-details compact'>
        <span class='detail-item'><strong>CPU:</strong> %s</span>
        <span class='detail-item'><strong>Memory:</strong> %s</span>
        <span class='detail-item'><strong>Children:</strong> %s</span>
        <span class='detail-item'><strong>Metrics:</strong> %s</span>
      </div>",
      htmltools::htmlEscape(cpu_display),
      htmltools::htmlEscape(memory_display),
      htmltools::htmlEscape(child_display),
      htmltools::htmlEscape(metrics_age_display)
    )
    html_parts <- c(html_parts, resource_html)
    
  } else if (has_any_metrics && !is.null(task_data$metrics_age_seconds)) {
    # Historic metrics available but no current data
    metrics_age <- as.integer(task_data$metrics_age_seconds)
    
    # Determine process state based on status and metrics age
    if (status == "FAILED") {
      process_state <- "<span style='color: #d9534f;'>🔴 Terminated</span>"
    } else if (status %in% c("COMPLETED", "SKIPPED")) {
      process_state <- "<span style='color: #5cb85c;'>✅ Completed</span>"
    } else if (status %in% c("RUNNING", "STARTED")) {
      if (process_is_dead) {
        process_state <- "<span style='color: #000000;'>❌ Dead</span>"
      } else if (metrics_age > 300) {  # 5 minutes
        process_state <- "<span style='color: #f0ad4e;'>🔴 Running (paused)</span>"
      } else if (metrics_age > 120) {
        process_state <- "<span style='color: #f0ad4e;'>🟡 Running (stale)</span>"
      } else {
        process_state <- "<span style='color: #5cb85c;'>🟢 Running</span>"
      }
    } else {
      process_state <- sprintf("<span style='color: #777;'>❓ %s</span>", status)
    }
    
    # Show actual metrics instead of just collection time
    cpu_display <- if (!is.null(task_data$metrics_cpu_percent) && !is.na(task_data$metrics_cpu_percent)) {
      cpu_text <- sprintf("%.1f%%", task_data$metrics_cpu_percent)
      # Add CPU core info if available
      if (!is.null(task_data$metrics_cpu_cores) && !is.na(task_data$metrics_cpu_cores)) {
        sprintf("%s (%d cores)", cpu_text, as.integer(task_data$metrics_cpu_cores))
      } else {
        cpu_text
      }
      # Add average and max CPU if available
      if (!is.null(task_data$avg_cpu_percent) && !is.na(task_data$avg_cpu_percent) &&
          !is.null(task_data$max_cpu_percent) && !is.na(task_data$max_cpu_percent)) {
        cpu_text <- sprintf("%s (avg: %.1f%%, max: %.1f%%)", 
                           cpu_text,
                           task_data$avg_cpu_percent, 
                           task_data$max_cpu_percent)
      }
      cpu_text
    } else {
      "N/A"
    }
    
    memory_display <- if (!is.null(task_data$metrics_memory_mb) && !is.na(task_data$metrics_memory_mb)) {
      mem_text <- if (!is.null(task_data$metrics_memory_percent) && !is.na(task_data$metrics_memory_percent)) {
        sprintf("%.1f MB (%.1f%%)", task_data$metrics_memory_mb, task_data$metrics_memory_percent)
      } else {
        sprintf("%.1f MB", task_data$metrics_memory_mb)
      }
      # Add average and max memory if available
      if (!is.null(task_data$avg_memory_mb) && !is.na(task_data$avg_memory_mb) &&
          !is.null(task_data$max_memory_mb) && !is.na(task_data$max_memory_mb)) {
        mem_text <- sprintf("%s (avg: %.1f MB, max: %.1f MB)", 
                           mem_text,
                           task_data$avg_memory_mb,
                           task_data$max_memory_mb)
      }
      mem_text
    } else {
      "N/A"
    }
    
    child_display <- if (!is.null(task_data$child_count) && !is.na(task_data$child_count)) {
      if (task_data$child_count > 0) {
        sprintf("%d children", as.integer(task_data$child_count))
      } else {
        "No children"
      }
    } else {
      "N/A"
    }
    
    historic_note <- if (metrics_age < 60) {
      sprintf("as of %.0fs ago", metrics_age)
    } else if (metrics_age < 3600) {
      sprintf("as of %.0fm ago", metrics_age / 60)
    } else {
      sprintf("as of %.0fh ago", metrics_age / 3600)
    }
    
    resource_html <- sprintf(
      "<div class='process-details compact'>
        <span class='detail-item'><strong>State:</strong> %s</span>
        <span class='detail-item'><strong>CPU:</strong> %s</span>
        <span class='detail-item'><strong>Memory:</strong> %s</span>
        <span class='detail-item'><strong>Children:</strong> %s</span>
        <span class='detail-item'><strong>Updated:</strong> %s</span>
      </div>",
      process_state,
      htmltools::htmlEscape(cpu_display),
      htmltools::htmlEscape(memory_display),
      htmltools::htmlEscape(child_display),
      htmltools::htmlEscape(historic_note)
    )
    html_parts <- c(html_parts, resource_html)
    
  } else if (status %in% c("RUNNING", "STARTED")) {
    # Task marked as running but no metrics data at all
    process_state <- if (process_is_dead) {
      "<span style='color: #000000;'>❌ Dead</span>"
    } else {
      "<span style='color: #f0ad4e;'>⚠️ Running (no metrics)</span>"
    }
    
    resource_html <- sprintf(
      "<div class='process-details compact'>
        <span class='detail-item'><strong>State:</strong> %s</span>
        <span class='detail-item'><strong>Metrics:</strong> <span style='color: #777;'>No data collected</span></span>
      </div>",
      process_state
    )
    html_parts <- c(html_parts, resource_html)
    
  } else {
    # Task in terminal state (COMPLETED, FAILED, etc.) - show final state
    process_state <- switch(status,
      "COMPLETED" = "<span style='color: #5cb85c;'>✅ Completed</span>",
      "FAILED" = "<span style='color: #d9534f;'>❌ Failed</span>",
      "SKIPPED" = "<span style='color: #777;'>⊘ Skipped</span>",
      "CANCELLED" = "<span style='color: #777;'>⊗ Cancelled</span>",
      sprintf("<span style='color: #777;'>❓ %s</span>", status)
    )
    
    resource_html <- sprintf(
      "<div class='process-details compact'>
        <span class='detail-item'><strong>State:</strong> %s</span>
      </div>",
      process_state
    )
    html_parts <- c(html_parts, resource_html)
  }
  
  # Get subtask progress
  subtasks <- tryCatch({
    tasker::get_subtask_progress(run_id)
  }, error = function(e) NULL)
  
  if (!is.null(subtasks) && nrow(subtasks) > 0) {
    html_parts <- c(html_parts, "<h5 class='process-info-header'>Subtasks</h5>")
    
    # Build subtask table
    table_rows <- lapply(seq_len(nrow(subtasks)), function(i) {
      st <- subtasks[i, ]
      duration <- tryCatch({
        start_val <- st$start_time
        if (!is.null(start_val) && !is.na(start_val)) {
          # Use end_time if available (completed subtask), otherwise current time (running subtask)
          end_time <- if (!is.null(st$end_time) && !is.na(st$end_time)) {
            st$end_time
          } else {
            Sys.time()  # For running subtasks
          }
          format_duration(start_val, end_time)
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
      "<table class='table table-condensed subtask-table'>
        <thead>
          <tr>
            <th>#</th>
            <th>Name</th>
            <th>Status</th>
            <th>Progress</th>
            <th>Items</th>
            <th>Message</th>
            <th>Duration</th>
            <th>Remaining</th>
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
              # Force re-execution using global refresh interval to pick up new progress snapshots
              refresh_seconds <- if (!is.null(input) && !is.null(input$refresh_interval)) input$refresh_interval else 5
              invalidateLater(refresh_seconds * 1000, session)
              
              # Also depend on task_reactives for immediate updates when task changes
              task_key <- paste0(local_stage_name, "__", local_task_name)
              task_data <- task_reactives[[task_key]]
              
              # Read current status from local copies
              status_safe <- if (!is.null(local_status)) as.character(local_status) else "UNKNOWN"
              items_total_safe <- if (!is.null(local_items_total) && !is.na(local_items_total)) as.numeric(local_items_total) else 0
              
              if (status_safe %in% c("RUNNING", "STARTED") && items_total_safe > 0 && !is.null(local_run_id) && !is.na(local_run_id)) {
                # Read from environment - this will update at the global refresh interval due to invalidateLater
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
    fallback_warning_shown = FALSE,
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
    # Track previous task statuses to detect transitions
    task_previous_statuses = list(),
    # Database connection for SQL queries monitoring (reused)
    monitor_connection = NULL,
    # Trigger for forcing initial DOM renders
    initial_render_trigger = 0,
    # Query state tracking to prevent reactive flooding
    query_running = FALSE,
    last_query_time = Sys.time() - 60,
    # Track initial load separately to avoid observer self-dependency
    initial_load_complete = FALSE
  )
  
  # Minimum interval between queries (seconds)
  min_query_interval <- 5
  
  # Cleanup database connection when session ends
  onSessionEnded(function() {
    con <- isolate(rv$monitor_connection)
    if (!is.null(con) && DBI::dbIsValid(con)) {
      try({
        DBI::dbDisconnect(con)
        message("Disconnected monitor database connection")
      }, silent = TRUE)
    }
  })
  
  # Busy indicator
  output$busy_indicator <- renderText({
    if (rv$query_running) {
      "⏳ Loading..."
    } else {
      ""
    }
  })
  
  # Disable auto-refresh while query is running
  observe({
    if (rv$query_running) {
      shinyjs::disable("auto_refresh")
    } else {
      shinyjs::enable("auto_refresh")
    }
  })
  
  # Get pipeline structure (stages + registered tasks) - this rarely changes
  pipeline_structure <- reactiveVal(NULL)
  
  # Force structure refresh when button clicked
  observeEvent(input$refresh_structure, {
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
    showNotification("Pipeline structure refreshed", type = "message", duration = 2)
  })
  
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
    
    # Trigger initial render after DOM creation with slight delay
    shinyjs::delay(100, {
      rv$initial_render_trigger <- rv$initial_render_trigger + 1
    })
  })
  
  # Manual refresh of pipeline structure
  observeEvent(input$refresh_structure, {
    structure <- tryCatch({
      stages <- tasker::get_stages()
      if (!is.null(stages) && nrow(stages) > 0) {
        stages <- stages[stages$stage_name != "TEST" & stages$stage_order != 999, ]
      }
      
      registered_tasks <- tasker::get_registered_tasks()
      
      list(stages = stages, tasks = registered_tasks)
    }, error = function(e) {
      showNotification(paste("Error loading structure:", e$message), type = "error", duration = 5)
      NULL
    })
    
    if (!is.null(structure)) {
      pipeline_structure(structure)
      showNotification("Pipeline structure refreshed", type = "message", duration = 2)
      
      # Trigger DOM re-render
      rv$initial_render_trigger <- rv$initial_render_trigger + 1
    }
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
          completed_subtasks = 0,
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
  
  # Auto-refresh trigger (start at 1 to force initial load)
  refresh_trigger <- reactiveVal(1)
  message("[INIT] refresh_trigger initialized to 1")
  
  # Use reactiveTimer() instead of invalidateLater() to prevent reactive storm
  # reactiveTimer() creates a clean reactive dependency that ONLY fires on schedule
  auto_refresh_timer <- reactive({
    # Allow dynamic interval changes
    interval_ms <- input$refresh_interval * 1000
    reactiveTimer(interval_ms)()
  })
  
  observe({
    auto_refresh_timer()  # Depend ONLY on timer
    # Use isolate() to prevent reactive dependencies on conditional checks
    if (isolate(input$auto_refresh) && isolate(!rv$query_running)) {
      new_val <- isolate(refresh_trigger()) + 1
      refresh_trigger(new_val)
      message(sprintf("[AUTO-REFRESH] Incremented refresh_trigger to %d (query_running=%s)", new_val, isolate(rv$query_running)))
    }
  })
  
  # Manual refresh button
  observeEvent(input$refresh, {
    new_val <- refresh_trigger() + 1
    refresh_trigger(new_val)
    message(sprintf("[MANUAL-REFRESH] Incremented refresh_trigger to %d", new_val))
  })
  
  # Task data reactive - fetches current task status with cooldown to prevent flooding
  task_data <- reactive({
    message(sprintf("[TASK_DATA] Called with refresh_trigger=%d", refresh_trigger()))
    # Prevent overlapping queries
    time_since_last <- as.numeric(difftime(Sys.time(), rv$last_query_time, units = "secs"))
    message(sprintf("[TASK_DATA] time_since_last=%.2f, min_interval=%d, query_running=%s", 
                   time_since_last, min_query_interval, rv$query_running))
    req(time_since_last >= min_query_interval)
    message("[TASK_DATA] Cooldown passed, running query...")
    
    rv$query_running <- TRUE
    on.exit({
      rv$query_running <- FALSE
      rv$last_query_time <- Sys.time()
      message("[TASK_DATA] Query complete, updated last_query_time")
    }, add = TRUE)
    
    tryCatch({
      message("[TASK_DATA] Calling tasker::get_task_status()...")
      result <- tasker::get_task_status()
      message(sprintf("[TASK_DATA] Got %d rows", if(!is.null(result)) nrow(result) else 0))
      # No need to clear error_message since we use notifications now
      return(result)
    }, error = function(e) {
      error_msg <- conditionMessage(e)
      
      # Check if error is due to missing view (database schema not updated)
      if (grepl("current_task_status_with_metrics.*does not exist", error_msg, ignore.case = TRUE)) {
        # Show notification about database schema update needed
        showNotification(
          "Database schema needs update. Run tasker::setup_tasker_db(force = TRUE) to enable full features including subtask progress.",
          type = "warning",
          duration = 10
        )
        
        # Try fallback to old view without metrics
        tryCatch({
          message("Falling back to current_task_status view (without process metrics)")
          message("INFO: Subtask progress unavailable. Run tasker::setup_tasker_db(force = TRUE) to enable full features.")
          # Temporarily override get_task_status to use old view
          con <- tasker::get_db_connection()
          on.exit(DBI::dbDisconnect(con))
          
          config <- getOption("tasker.config")
          driver <- config$database$driver
          schema <- if (driver == "postgresql") config$database$schema else ""
          
          table_ref <- if (nchar(schema) > 0) {
            DBI::Id(schema = schema, table = "current_task_status")
          } else {
            "current_task_status"
          }
          
          query <- dplyr::tbl(con, table_ref)
          result <- dplyr::collect(query)
          
          # Show one-time info notification about using fallback
          if (!rv$fallback_warning_shown) {
            showNotification(
              "Using fallback database view - some features limited. Run tasker::setup_tasker_db(force = TRUE) for full functionality.",
              type = "message",
              duration = 8
            )
            rv$fallback_warning_shown <- TRUE
          }
          
          return(result)
          
        }, error = function(e2) {
          message("Fallback also failed: ", conditionMessage(e2))
          showNotification(
            paste("Database connection failed:", conditionMessage(e2)),
            type = "error",
            duration = 15
          )
          NULL
        })
      } else {
        # Other error - show notification
        message("Error getting task data: ", error_msg)
        showNotification(
          paste("Error fetching task status:", error_msg),
          type = "error",
          duration = 10
        )
        NULL
      }
    })
  }) %>% bindEvent(refresh_trigger(), ignoreInit = FALSE, ignoreNULL = TRUE)
  
  # Observer: Poll database and update only changed values
  observe({
    # CRITICAL: Depend ONLY on task_data() and force_refresh, nothing else
    # Use isolate() for all checks to prevent reactive dependencies
    current_status <- task_data()
    rv$force_refresh  # Also depend on force_refresh
    
    message("[OBSERVER] Starting, initial_load_complete=", isolate(rv$initial_load_complete))
    message("[OBSERVER] main_tabs=", isolate(input$main_tabs))
    
    # After initial load, only update when Pipeline Status tab is active
    # Use separate flag to avoid observer self-dependency on rv$last_update
    if (isolate(rv$initial_load_complete)) {
      message("[OBSERVER] Checking tab requirement...")
      req(isolate(input$main_tabs) == "Pipeline Status")
      message("[OBSERVER] Tab requirement passed")
    } else {
      message("[OBSERVER] Initial load - skipping tab check")
    }
    
    message("[OBSERVER] Got current_status, rows=", if(!is.null(current_status)) nrow(current_status) else "NULL")
    
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
              completed_subtasks = 0,
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
      completed_subtasks <- 0
      total_subtasks <- 0
      if (!is.na(task_status$run_id) && task_status$status %in% c("RUNNING", "STARTED")) {
        subtask_info <- tryCatch({
          subs <- tasker::get_subtask_progress(task_status$run_id)
          # Count completed subtasks and total subtasks
          if (!is.null(subs) && nrow(subs) > 0) {
            completed_subtasks <- sum(subs$status == "COMPLETED", na.rm = TRUE)
            total_subtasks <- nrow(subs)
          }
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
          completed_subtasks = completed_subtasks,
          total_subtasks = total_subtasks,
          current_subtask_name = if (!is.null(subtask_info) && !is.na(subtask_info$subtask_name)) subtask_info$subtask_name else "",
          current_subtask_number = if (!is.null(subtask_info) && !is.na(subtask_info$subtask_number)) subtask_info$subtask_number else 0
        ) %>%
        as.list()
      
      # Only update if something changed
      if (is.null(current_val) || !identical(current_val, new_val)) {
        task_reactives[[task_key]] <- new_val
      }
    }
    
    # Update last refresh timestamp
    isolate(rv$last_update <- Sys.time())
    # Mark initial load complete after first successful update
    isolate(rv$initial_load_complete <- TRUE)
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
        
        # Auto-collapse if status CHANGED TO COMPLETED
        status_changed_to_completed <- !is.null(previous_status) && 
                                        (previous_status %in% c("RUNNING", "STARTED")) &&
                                        (current_status == "COMPLETED")
        
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
        } else if (status_changed_to_completed) {
          # Collapse when completed
          shinyjs::delay(100, {
            collapse_id <- paste0("collapse_", stage_id)
            button_id <- paste0("heading_", stage_id)
            
            shinyjs::runjs(sprintf(
              "
              var button = document.querySelector('#%s .accordion-button');
              var collapse = document.getElementById('%s');
              if (button && collapse && collapse.classList.contains('show')) {
                button.classList.add('collapsed');
                button.setAttribute('aria-expanded', 'false');
                collapse.classList.remove('show');
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
    # Only update when Pipeline Status tab is active
    req(input$main_tabs == "Pipeline Status")
    
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
                title = "Toggle process information and metrics",
                onclick = sprintf("Shiny.setInputValue('toggle_process_pane', '%s', {priority: 'event'})", task_id),
                "📊"
              ),
              # Log viewer toggle button (file icon)
              tags$button(
                class = "btn-expand-log",
                id = paste0("btn_expand_log_", task_id),
                title = "Toggle log viewer",
                onclick = sprintf("Shiny.setInputValue('toggle_log_pane', '%s', {priority: 'event'})", task_id),
                "📄"
              )
            ),
            textOutput(paste0("task_name_", task_id), inline = TRUE, container = function(...) div(class = "task-name", ...)),
            htmlOutput(paste0("task_status_", task_id), inline = TRUE, container = function(...) span(class = "task-status-badge", ...)),
            htmlOutput(paste0("task_progress_", task_id), inline = TRUE, container = function(...) div(class = "task-progress-container", ...)),
            textOutput(paste0("task_message_", task_id), inline = TRUE, container = function(...) div(class = "task-message", ...)),
            div(id = paste0("task_reset_", task_id), class = "task-reset-button", 
                tags$button(
                  id = paste0("reset_btn_", task_id),
                  class = "btn btn-sm btn-warning task-reset-btn",
                  title = "Reset this task to NOT_STARTED",
                  onclick = sprintf(
                    "Shiny.setInputValue('task_reset_clicked', {stage: '%s', task: '%s', timestamp: Date.now()}, {priority: 'event'})",
                    htmltools::htmlEscape(task$stage_name),
                    htmltools::htmlEscape(task$task_name)
                  ),
                  "Reset"
                )
            )
          ),
          # Process status sub-pane (hidden by default)
          div(
            id = paste0("process_pane_", task_id),
            class = "task-subpane process-pane",
            style = "display: none;",
            htmlOutput(paste0("process_content_", task_id))
          ),
          # Log viewer sub-pane (hidden by default)
          div(
            id = paste0("log_pane_", task_id),
            class = "task-subpane log-pane",
            style = "display: none;",
            div(
              class = "log-controls-container",
              div(
                class = "log-controls",
                selectInput(
                  paste0("log_lines_", task_id),
                  NULL,
                  choices = c(
                    "Last 5 lines" = 5,
                    "Last 10 lines" = 10,
                    "Last 25 lines" = 25,
                    "Last 50 lines" = 50,
                    "Last 100 lines" = 100,
                    "Full log" = -1
                  ),
                  selected = 5,
                  width = "140px"
                ),
                checkboxInput(
                  paste0("log_tail_", task_id),
                  "Tail mode",
                  value = TRUE
                ),
                checkboxInput(
                  paste0("log_auto_refresh_", task_id),
                  "Auto-refresh",
                  value = TRUE
                ),
                actionButton(
                  paste0("log_refresh_", task_id),
                  "Refresh",
                  icon = icon("sync"),
                  class = "btn-sm btn-primary"
                )
              )
            ),
            div(
              class = "log-terminal",
              htmlOutput(paste0("log_text_", task_id))
            )
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
              htmlOutput(paste0("stage_badge_", stage_id), inline = TRUE, container = function(...) span(class = "stage-badge", ...)),
              htmlOutput(paste0("stage_progress_", stage_id), inline = TRUE, container = function(...) span(class = "stage-progress", ...)),
              textOutput(paste0("stage_count_", stage_id), inline = TRUE, container = function(...) span(class = "stage-count", ...))
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
    # Only create stage UI when Pipeline Status tab is active
    req(input$main_tabs == "Pipeline Status")
    
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    stages <- struct$stages
    if (is.null(stages) || nrow(stages) == 0) return()
    
    stages <- stages[order(stages$stage_order), ]
    
    lapply(seq_len(nrow(stages)), function(i) {
      stage <- stages[i, ]
      stage_name <- stage$stage_name
      stage_id <- gsub("[^a-zA-Z0-9]", "_", stage_name)
      
      # Create render blocks for stage components
      (function(stage_name_local, stage_id_local) {
        
        # Badge - reactive renderText for htmlOutput
        output[[paste0("stage_badge_", stage_id_local)]] <- renderText({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            badge_html(stage_data$status)
          } else {
            ""
          }
        })
        
        # Progress bar - reactive renderText for htmlOutput
        output[[paste0("stage_progress_", stage_id_local)]] <- renderText({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            stage_progress_html(stage_data$progress_pct, stage_data$status)
          } else {
            ""
          }
        })
        
        # Count - reactive renderText for textOutput
        output[[paste0("stage_count_", stage_id_local)]] <- renderText({
          stage_data <- stage_reactives[[stage_name_local]]
          if (!is.null(stage_data)) {
            sprintf("%d/%d", as.integer(stage_data$completed), as.integer(stage_data$total))
          } else {
            ""
          }
        })
      })(stage_name, stage_id)
    })
  })
  
  # Create reactive observers for individual task components using shinyjs
  observe({
    # Only create task UI when Pipeline Status tab is active
    req(input$main_tabs == "Pipeline Status")
    
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
        
        # Status badge - reactive output
        output[[paste0("task_status_", task_id_local)]] <- renderText({
          task_data <- task_reactives[[task_key_local]]
          task_status <- if (!is.null(task_data)) task_data$status else "NOT_STARTED"
          badge_html(task_status)
        })
        
        # Progress bars - reactive output
        output[[paste0("task_progress_", task_id_local)]] <- renderText({
          task_data <- task_reactives[[task_key_local]]
          task_progress_html(task_data)
        })
        
        # Message with enhanced subtask details - reactive output
        output[[paste0("task_message_", task_id_local)]] <- renderText({
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
                     as.integer(current_subtask), as.integer(current_subtask_number),
                     current_subtask_name, overall_progress_message)
            } else if (nchar(current_subtask_name) > 0) {
              # Show only subtask name if no overall message
              sprintf("Subtask %d.%d: %s", as.integer(current_subtask), as.integer(current_subtask_number), current_subtask_name)
            } else {
              # Fall back to overall progress message
              overall_progress_message
            }
          } else {
            ""
          }
          
          message_text %||% ""
        })
        
        # Reset button is now static in UI - no reactive updates needed
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
        # Process pane content - renderText for htmlOutput
        # Always generate content, visibility controlled by CSS/shinyjs
        output[[paste0("process_content_", task_id_local)]] <- renderText({
          # Check if task_reactives exists for this key (may not exist on first render)
          task_data <- task_reactives[[task_key_local]]
          if (is.null(task_data)) {
            # Return placeholder if data not yet available
            return(HTML("<div class='process-info-header'>Loading process information...</div>"))
          }
          build_process_status_html(task_data, stage_name_local, task_name_local, progress_history_env, output, task_reactives, session, input)
        })
        
        # Log pane content - observer to initialize controls once when expanded
        observe({
          # Only initialize if this pane is newly expanded and controls don't exist yet
          if (task_id_local %in% rv$expanded_log_panes) {
            # Get log settings for this task
            init_log_settings(rv, task_id_local)
            settings <- rv$log_settings[[task_id_local]]
            
            # Update control values (in case they were created with different defaults)
            if (!is.null(input[[paste0("log_lines_", task_id_local)]])) {
              updateSelectInput(session, paste0("log_lines_", task_id_local), selected = settings$num_lines)
            }
          }
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
            invalidateLater(input$refresh_interval * 1000)
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
                <div class='log-line' style='text-align: center; white-space-collapse: collapse; line-height: 2;'>
                    <strong>Log file not found</strong>
                    <br>
                    Expected: %s
                    <br>
                    This file will be created when the task runs.
                </div>",
                htmltools::htmlEscape(basename(log_file)),
                htmltools::htmlEscape(task_status),
                htmltools::htmlEscape(log_file)
              )
            }
            
            # Update the output with the no-log message using shinyjs::html
            log_text_id <- paste0("log_text_", task_id_local)
            shinyjs::html(log_text_id, no_log_message)
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
            
            # Replace entire content using shinyjs::html
            log_text_id <- paste0("log_text_", task_id_local)
            shinyjs::html(log_text_id, content)
            
            # Update position tracker
            rv$log_last_positions[[pos_key]] <- list(
              line_count = length(all_lines),
              last_end_line = start_line + length(lines_to_show) - 1,
              display_mode = current_mode
            )
          } else if (settings$tail_mode && length(all_lines) > last_pos$line_count) {
            # Tail mode: Append new lines and enforce line limit
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
            
            # Append using JavaScript and enforce line limit
            new_content <- paste(formatted_new_lines, collapse = "")
            log_text_id <- paste0("log_text_", task_id_local)
            max_lines <- if (settings$num_lines <= -1) 999999 else settings$num_lines
            
            shinyjs::runjs(sprintf(
              "var elem = document.getElementById('%s');
               if (elem) {
                 var wasAtBottom = elem.scrollHeight - elem.scrollTop <= elem.clientHeight + 50;
                 
                 // Add new content
                 elem.insertAdjacentHTML('beforeend', %s);
                 
                 // Re-query to get updated list after adding new content
                 var logLines = elem.querySelectorAll('.log-line');
                 var maxLines = %d;
                 if (maxLines < 999999 && logLines.length > maxLines) {
                   var linesToRemove = logLines.length - maxLines;
                   // Remove oldest lines from the beginning
                   for (var i = 0; i < linesToRemove; i++) {
                     if (logLines[i]) logLines[i].remove();
                   }
                 }
                 
                 if (wasAtBottom) {
                   elem.scrollTop = elem.scrollHeight;
                 }
               }",
              log_text_id,
              jsonlite::toJSON(new_content, auto_unbox = TRUE),
              max_lines
            ))
            
            # Update line info bar with correct count
            displayed_lines <- min(length(lines_to_show) + new_line_count, max_lines)
            file_info <- sprintf(
              "<div class='log-file-info-bar'>
                <span><strong>File:</strong> %s</span>
                <span><strong>Lines:</strong> %d (showing last %d)</span>
                <span><strong>Updated:</strong> %s</span>
              </div>",
              htmltools::htmlEscape(basename(log_file)),
              length(all_lines),
              as.integer(displayed_lines),
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
      })(task_key, task_id, stage_name, task_name)
    })
  })
  
  # Last update time
  output$last_update <- renderDatetime({
    if (!is.null(rv$last_update)) {
      rv$last_update  # shinyTZ automatically handles timezone conversion
    } else {
      NULL  # renderDatetime handles NULL gracefully
    }
  }, format = "%H:%M:%S %Z")
  
  # Process monitor status
  monitor_status_reactive <- reactive({
    # Update at the same global refresh interval as other components
    if (input$auto_refresh) {
      invalidateLater(input$refresh_interval * 1000)
    }
    
    tryCatch({
      tasker::check_reporter(quiet = TRUE)
    }, error = function(e) {
      NULL
    })
  })
  
  output$monitor_status <- renderText({
    monitor_data <- monitor_status_reactive()
    
    if (is.null(monitor_data) || nrow(monitor_data) == 0) {
      # No monitors running
      '<div style="color: #d9534f; font-weight: bold;">⬤ No monitors running</div><div style="color: #777; font-size: 11px;">Process metrics unavailable</div>'
    } else {
      # Build table rows for each monitor using dplyr pipeline
      table_rows <- monitor_data %>%
        dplyr::mutate(
          color = dplyr::case_when(
            heartbeat_age_seconds <= 30                      ~ "#5cb85c",  # Green: fresh heartbeat
            heartbeat_age_seconds <= 120                     ~ "#f0ad4e",  # Yellow: aging
            heartbeat_age_seconds > 120                      ~ "#d9534f",  # Red: stale
            !is.na(is_alive) & !as.logical(is_alive)         ~ "#d9534f",  # Red: confirmed dead
            TRUE                                             ~ "#777"      # Gray: unknown
          ),
          icon = dplyr::case_when(
            heartbeat_age_seconds <= 30                      ~ "🟢",
            heartbeat_age_seconds <= 120                     ~ "🟡",
            heartbeat_age_seconds > 120                      ~ "🔴",
            !is.na(is_alive) & !as.logical(is_alive)         ~ "⬤",
            TRUE                                             ~ "❓"
          ),
          text = dplyr::case_when(
            !is.na(is_alive) & !as.logical(is_alive) ~ "Dead",
            heartbeat_age_seconds <= 30              ~ "Active",
            heartbeat_age_seconds <= 120             ~ "Stale",
            heartbeat_age_seconds > 120              ~ "Very stale",
            TRUE                                     ~ "Unknown"
          ),
          hostname_short = stringr::str_replace(hostname, "\\..*$", ""),
          process_id_str = ifelse(is.na(process_id), "?", as.character(process_id)),
          # Format heartbeat age for display
          heartbeat_display = dplyr::case_when(
            is.na(heartbeat_age_seconds) ~ "Unknown",
            heartbeat_age_seconds < 60 ~ sprintf("%.0fs ago", heartbeat_age_seconds),
            heartbeat_age_seconds < 3600 ~ sprintf("%.0fm ago", heartbeat_age_seconds / 60),
            TRUE ~ sprintf("%.1fh ago", heartbeat_age_seconds / 3600)
          ),
          # Build tooltip text
          tooltip = sprintf("Status: %s\\nHeartbeat: %s", text, heartbeat_display),
          # Build table row HTML
          row_html = paste0(
            "<tr style=\"color: ", color, ";\" title=\"", htmltools::htmlEscape(tooltip), "\">",
              "<td style=\"text-align: center; padding: 2px 4px;\">", icon, "</td>",
              "<td style=\"padding: 2px 4px;\">", htmltools::htmlEscape(hostname_short), "</td>",
              "<td style=\"text-align: right; padding: 2px 4px;\">", htmltools::htmlEscape(process_id_str), "</td>",
            "</tr>"
          )
        ) %>%
        dplyr::pull(row_html)
      
      # Build complete table
      paste0(
        "<table style=\"width: 100%; font-size: 11px; border-collapse: collapse;\">",
          paste(table_rows, collapse = ""),
        "</table>"
      )
    }
  })
  
  # Separate output for active monitor count (displayed inline with title)
  output$monitor_active_count <- renderText({
    monitor_data <- monitor_status_reactive()
    
    if (is.null(monitor_data) || nrow(monitor_data) == 0) {
      "Active: 0/0"
    } else {
      # Calculate active monitors using dplyr pipeline
      total_monitors <- nrow(monitor_data)
      active_monitors <- monitor_data %>%
        dplyr::filter(
          (is.na(is_alive) | as.logical(is_alive)),
          !is.null(heartbeat_age_seconds),
          !is.na(heartbeat_age_seconds),
          as.numeric(heartbeat_age_seconds) <= 30
        ) %>%
        nrow()
      
      sprintf("Active: %d/%d", as.integer(active_monitors), as.integer(total_monitors))
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
  
  # Dynamic error banner with appropriate styling
  output$error_banner <- renderText({
    if (!is.null(rv$error_message)) {
      error_text <- rv$error_message
      
      # Determine if this is an info message or actual error
      is_info <- grepl("^INFO:", error_text)
      
      alert_class <- if (is_info) "alert-info" else "alert-danger"
      label_text <- if (is_info) "Info: " else "Error: "
      
      dismiss_button <- if (is_info) {
        '<button id="dismiss_info" type="button" class="btn btn-sm btn-secondary" style="margin-left: 10px;">Dismiss</button>'
      } else {
        ''
      }
      
      sprintf(
        '<div class="alert %s" style="margin: 6px; padding: 6px 10px;"><strong>%s</strong><pre style="white-space: pre-wrap; margin-top: 6px; background: #fff; padding: 6px; border: 1px solid #ddd;">%s</pre>%s</div>',
        alert_class,
        label_text,
        htmltools::htmlEscape(error_text),
        dismiss_button
      )
    } else {
      ""
    }
  })
  
  # Dismiss info message
  observeEvent(input$dismiss_info, {
    rv$error_message <- NULL
  })
  
  # ============================================================================
  # AUTO-EXPAND: Automatically expand task process panes when status transitions
  # ============================================================================
  
  observe({
    struct <- pipeline_structure()
    if (is.null(struct)) return()
    
    tasks <- struct$tasks
    if (is.null(tasks) || nrow(tasks) == 0) return()
    
    # Trigger on any task_reactives change
    task_reactives_list <- reactiveValuesToList(task_reactives)
    
    # Wait for task reactives to be populated
    has_data <- any(sapply(task_reactives_list, function(x) !is.null(x)))
    if (!has_data) return()
    
    # Check each task's status and compare with previous status
    lapply(seq_len(nrow(tasks)), function(i) {
      task <- tasks[i, ]
      stage_name <- task$stage_name
      task_name <- task$task_name
      task_id <- gsub("[^A-Za-z0-9]", "_", paste(stage_name, task_name, sep="_"))
      task_key <- paste(stage_name, task_name, sep = "||")
      
      task_data <- task_reactives[[task_key]]
      
      if (!is.null(task_data)) {
        current_status <- task_data$status
        previous_status <- rv$task_previous_statuses[[task_key]]
        
        # Store current status for next comparison
        rv$task_previous_statuses[[task_key]] <- current_status
        
        # Only auto-expand if status CHANGED TO RUNNING or STARTED
        status_changed_to_active <- !is.null(previous_status) && 
                                     !(previous_status %in% c("RUNNING", "STARTED")) &&
                                     (current_status %in% c("RUNNING", "STARTED"))
        
        # Auto-collapse if status CHANGED TO COMPLETED
        status_changed_to_completed <- !is.null(previous_status) && 
                                        (previous_status %in% c("RUNNING", "STARTED")) &&
                                        (current_status == "COMPLETED")
        
        # On initial load (previous_status is NULL), expand active tasks
        initial_load_active <- is.null(previous_status) && 
                               (current_status %in% c("RUNNING", "STARTED"))
        
        if (status_changed_to_active || initial_load_active) {
          # Expand process pane
          if (!(task_id %in% rv$expanded_process_panes)) {
            rv$expanded_process_panes <- c(rv$expanded_process_panes, task_id)
            shinyjs::show(paste0("process_pane_", task_id))
            shinyjs::addClass(paste0("btn_expand_process_", task_id), "expanded")
          }
        } else if (status_changed_to_completed) {
          # Collapse process pane
          if (task_id %in% rv$expanded_process_panes) {
            rv$expanded_process_panes <- setdiff(rv$expanded_process_panes, task_id)
            shinyjs::hide(paste0("process_pane_", task_id))
            shinyjs::removeClass(paste0("btn_expand_process_", task_id), "expanded")
          }
        }
      }
    })
  })
  
  # ============================================================================
  # EXPANDABLE PANES: Toggle Event Handlers
  # ============================================================================
  
  # Process pane toggle handler
  observeEvent(input$toggle_process_pane, {
    task_id <- input$toggle_process_pane
    
    # Toggle expanded state and visibility immediately
    if (task_id %in% rv$expanded_process_panes) {
      rv$expanded_process_panes <- setdiff(rv$expanded_process_panes, task_id)
      shinyjs::hide(paste0("process_pane_", task_id))
      shinyjs::removeClass(paste0("btn_expand_process_", task_id), "expanded")
    } else {
      rv$expanded_process_panes <- c(rv$expanded_process_panes, task_id)
      shinyjs::show(paste0("process_pane_", task_id))
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
      # Force log refresh for this task
      rv$log_refresh_trigger <- rv$log_refresh_trigger + 1
    }
  })
  
  # ============================================================================
  # LOG CONTROLS: Dynamic observers for log viewer settings
  # ============================================================================
  
  # Observer to create reactive handlers for each task's log controls
  observe({
    # Only create log controls when Pipeline Status tab is active
    req(input$main_tabs == "Pipeline Status")
    
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
  
  # Checkbox change triggers refresh
  observeEvent(input$exclude_tasker_queries, {
    rv$sql_trigger <- Sys.time()
  }, ignoreInit = TRUE)
  
  # Fetch SQL queries with cooldown to prevent flooding
  sql_queries_data <- reactive({
    # Only fetch when SQL Queries tab is active
    req(input$main_tabs == "SQL Queries")
    
    # Prevent overlapping queries
    time_since_last <- as.numeric(difftime(Sys.time(), rv$last_query_time, units = "secs"))
    req(time_since_last >= min_query_interval)
    
    rv$query_running <- TRUE
    on.exit({
      rv$query_running <- FALSE
      rv$last_query_time <- Sys.time()
    }, add = TRUE)
    
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
      queries <- tasker::get_database_queries(con, status = "active", db_type = config$database$driver %||% "postgresql")
      
      # Filter tasker queries if checkbox is checked (default: exclude)
      if (!is.null(input$exclude_tasker_queries) && input$exclude_tasker_queries && !is.null(queries) && nrow(queries) > 0) {
        queries <- queries[!grepl("tasker\\.", queries$query, ignore.case = TRUE), ]
      }
      
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
  }) %>% bindEvent(refresh_trigger(), rv$sql_trigger, ignoreInit = FALSE, ignoreNULL = TRUE)
  
  # Render SQL queries table - initial render with proper column structure
  output$sql_queries_table <- renderDT({
    # Start with empty data frame with proper columns
    initial_data <- data.frame(
      pid = integer(0),
      duration = character(0),
      username = character(0),
      query = character(0),
      state = character(0),
      Actions = character(0),
      stringsAsFactors = FALSE
    )
    
    datatable(
      initial_data,
      options = list(
        pageLength = 25,
        scrollX = TRUE,
        scrollY = "60vh",
        scrollCollapse = TRUE,
        dom = 'lfrtip',
        ordering = TRUE,
        columnDefs = list(
          list(targets = ncol(initial_data) - 1, orderable = FALSE)
        )
      ),
      rownames = FALSE,
      filter = 'none',
      escape = FALSE,
      class = 'cell-border stripe'
    )
  })

  # Update SQL queries table content using proxy
  observe({
    queries <- sql_queries_data()
    
    # Add action buttons column with kill button for each row
    if (nrow(queries) > 0) {
      queries$Actions <- sapply(seq_len(nrow(queries)), function(i) {
        sprintf(
          '<button class="btn btn-danger btn-sm kill-query-btn" data-pid="%s" data-username="%s" style="padding: 2px 8px; font-size: 12px;">Kill</button>',
          queries$pid[i],
          htmltools::htmlEscape(queries$username[i])
        )
      })
    } else {
      queries$Actions <- character(0)
    }

    # Use proxy to update data without recreating the table
    proxy <- dataTableProxy('sql_queries_table')
    
    # Always pass queries (which has proper column structure)
    replaceData(proxy, queries, resetPaging = FALSE, rownames = FALSE)
  })
  
  # Handle kill button clicks
  observeEvent(input$kill_query_pid, {
    pid <- input$kill_query_pid
    username <- input$kill_query_username
    
    if (!is.null(pid) && !is.null(username)) {
      # Show confirmation modal
      showModal(modalDialog(
        title = "Confirm Kill Query",
        sprintf("Are you sure you want to kill query with PID %s (user: %s)?", pid, username),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_kill_query", "Kill Query", class = "btn-danger")
        ),
        easyClose = TRUE
      ))
      
      # Store PID for confirmation handler
      rv$pending_kill_pid <- pid
    }
  })
  
  # Handle confirmed kill action
  observeEvent(input$confirm_kill_query, {
    pid <- rv$pending_kill_pid
    
    if (!is.null(pid)) {
      tryCatch({
        config <- getOption("tasker.config")
        if (is.null(config)) {
          showNotification("Tasker configuration not loaded", type = "error", duration = 5)
          removeModal()
          return()
        }
        
        # Get database connection
        con <- tasker::get_monitor_connection(config, rv$monitor_connection)
        rv$monitor_connection <- con
        
        # Kill the query using bbcDB::dbKillQuery
        result <- bbcDB::dbKillQuery(con, as.numeric(pid))
        
        # Show success notification
        showNotification(
          sprintf("Query PID %s killed successfully", pid),
          type = "message",
          duration = 3
        )
        
        # Refresh the query list
        rv$sql_trigger <- Sys.time()
        
      }, error = function(e) {
        showNotification(
          sprintf("Error killing query: %s", conditionMessage(e)),
          type = "error",
          duration = 10
        )
      })
      
      # Clear pending kill PID
      rv$pending_kill_pid <- NULL
    }
    
    removeModal()
  })
  
  # ============================================================================
  # DEBUGGER BUTTON
  # ============================================================================
  
  # Start debugger when button is clicked
  observeEvent(input$start_debugger, {
    showNotification("Starting debugger... Check R console.", type = "warning", duration = 3)
    browser()
  })
}
