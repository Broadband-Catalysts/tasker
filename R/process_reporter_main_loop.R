#' Process Reporter Main Loop
#'
#' The main collection loop for the process reporter service.
#' Runs continuously until shutdown is requested.
#'
#' @param collection_interval_seconds How often to collect metrics (default: 10)
#' @param hostname Reporter hostname (default: current host)
#' @param con Database connection (NULL = get default)
#'
#' @return NULL (runs until shutdown)
#' @export
#'
#' @examples
#' \dontrun{
#' # This runs in the background daemon process
#' process_reporter_main_loop()
#' }
process_reporter_main_loop <- function(
    collection_interval_seconds = 10,
    hostname = Sys.info()["nodename"],
    con = NULL
) {
  
  message("[Process Reporter] Starting main loop on host: ", hostname)
  message("[Process Reporter] Collection interval: ", collection_interval_seconds, " seconds")
  
  close_con <- FALSE
  if (is.null(con)) {
    con <- get_db_connection()
    close_con <- TRUE
  }
  
  on.exit({
    message("[Process Reporter] Main loop shutting down")
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  # Track metrics for batch optimization
  last_start_times <- list()
  
  # Main collection loop
  repeat {
    loop_start <- Sys.time()
    
    tryCatch({
      # Check for shutdown signal
      if (should_shutdown(con, hostname)) {
        message("[Process Reporter] Shutdown requested, exiting main loop")
        break
      }
      
      # Update heartbeat
      update_reporter_heartbeat(con, hostname)
      
      # Get active tasks on this host
      active_tasks <- get_active_tasks(con, hostname)
      
      if (length(active_tasks) > 0) {
        message("[Process Reporter] Found ", length(active_tasks), " active tasks")
        
        # Get previous start times for PID reuse detection (batch query)
        run_ids <- sapply(active_tasks, function(task) task$run_id)
        prev_start_times <- get_previous_start_times(con, run_ids)
        
        # Collect metrics for each active task
        for (task in active_tasks) {
          tryCatch({
            # Get previous start time for this run_id
            prev_start_time <- prev_start_times[[task$run_id]]
            
            # Collect metrics
            metrics <- collect_process_metrics(
              run_id = task$run_id,
              process_id = task$process_id,
              hostname = hostname,
              include_children = TRUE,
              timeout_seconds = 5,
              prev_start_time = prev_start_time
            )
            
            # Write to database
            write_process_metrics(metrics, con = con)
            
          }, error = function(e) {
            warning("[Process Reporter] Error collecting metrics for run_id ", 
                    task$run_id, ": ", e$message)
          })
        }
      } else {
        message("[Process Reporter] No active tasks found")
      }
      
    }, error = function(e) {
      warning("[Process Reporter] Error in main loop: ", e$message)
    })
    
    # Calculate sleep time to maintain consistent interval
    loop_duration <- as.numeric(difftime(Sys.time(), loop_start, units = "secs"))
    sleep_time <- max(0, collection_interval_seconds - loop_duration)
    
    if (sleep_time > 0) {
      Sys.sleep(sleep_time)
    } else {
      warning("[Process Reporter] Loop took ", round(loop_duration, 2), 
              " seconds (longer than ", collection_interval_seconds, "s interval)")
    }
  }
  
  message("[Process Reporter] Main loop terminated")
  return(NULL)
}


#' Check if reporter should shutdown
#'
#' Internal function to check shutdown flag in database.
#'
#' @param con Database connection
#' @param hostname Reporter hostname
#'
#' @return TRUE if shutdown requested, FALSE otherwise
#' @keywords internal
should_shutdown <- function(con, hostname) {
  
  tryCatch({
    table_name <- get_table_name("process_reporter_status", con, char = TRUE)
    
    # Database-specific SQL
    config <- getOption("tasker.config")
    if (!is.null(config) && config$database$driver == "sqlite") {
      sql <- sprintf("
        SELECT shutdown_requested
        FROM %s
        WHERE hostname = ?
      ", table_name)
    } else {
      sql <- sprintf("
        SELECT shutdown_requested
        FROM %s
        WHERE hostname = $1
      ", table_name)
    }
    
    result <- DBI::dbGetQuery(con, sql, params = list(hostname))
    
    if (nrow(result) > 0) {
      # SQLite uses INTEGER, PostgreSQL uses BOOLEAN
      return(result$shutdown_requested[1] == 1 || result$shutdown_requested[1] == TRUE)
    }
    
    return(FALSE)
    
  }, error = function(e) {
    warning("Failed to check shutdown flag: ", e$message)
    return(FALSE)
  })
}


#' Get active tasks for a hostname
#'
#' Internal function to retrieve tasks that are currently running
#' and need process monitoring.
#'
#' @param con Database connection
#' @param hostname Host to check for active tasks
#'
#' @return List of task info (run_id, process_id, etc.)
#' @keywords internal
get_active_tasks <- function(con, hostname) {
  
  tryCatch({
    table_name <- get_table_name("task_runs", con, char = TRUE)
    
    # Database-specific SQL
    config <- getOption("tasker.config")
    if (!is.null(config) && config$database$driver == "sqlite") {
      sql <- sprintf("
        SELECT tr.run_id, tr.process_id, tr.start_time, COALESCE(t.task_name, 'Unknown') as task_name
        FROM %s tr
        LEFT JOIN tasks t ON tr.task_id = t.task_id
        WHERE tr.hostname = ? 
          AND tr.status IN ('RUNNING', 'STARTED')
          AND tr.process_id IS NOT NULL
        ORDER BY tr.start_time
      ", table_name)
    } else {
      sql <- sprintf("
        SELECT tr.run_id, tr.process_id, tr.start_time, COALESCE(t.task_name, 'Unknown') as task_name
        FROM %s tr
        LEFT JOIN tasks t ON tr.task_id = t.task_id
        WHERE tr.hostname = $1 
          AND tr.status IN ('RUNNING', 'STARTED')
          AND tr.process_id IS NOT NULL
        ORDER BY tr.start_time
      ", table_name)
    }
    
    result <- DBI::dbGetQuery(con, sql, params = list(hostname))
    
    # Convert to list of task objects
    if (nrow(result) > 0) {
      tasks <- list()
      for (i in 1:nrow(result)) {
        tasks[[i]] <- list(
          run_id = result$run_id[i],
          process_id = result$process_id[i],
          start_time = result$start_time[i],
          task_name = result$task_name[i]
        )
      }
      return(tasks)
    }
    
    return(list())
    
  }, error = function(e) {
    warning("Failed to get active tasks: ", e$message)
    return(list())
  })
}