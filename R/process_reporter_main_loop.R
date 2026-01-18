#' Reporter Main Loop
#'
#' The main collection loop for the reporter service.
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
#' reporter_main_loop()
#' }
reporter_main_loop <- function(
    collection_interval_seconds = 10,
    hostname = Sys.info()["nodename"],
    con = NULL
) {
  
  message("[Process Reporter] ", Sys.time() ," Starting main loop on host: ", hostname)
  message("[Process Reporter] ", Sys.time() ," Collection interval: ", collection_interval_seconds, " seconds")
  
  close_con <- FALSE
  if (is.null(con)) {
    con <- get_db_connection()
    close_con <- TRUE
  }
  
  on.exit({
    message("[Process Reporter] ", Sys.time(), " Main loop shutting down")
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
        message("[Process Reporter] ", Sys.time(), " Shutdown requested, exiting main loop")
        break
      }
      
      # Update heartbeat
      update_reporter_heartbeat(con, hostname)
      
      # Get active tasks on this host
      active_tasks <- get_active_tasks_for_reporter(con, hostname)
      
      if (length(active_tasks) > 0) {
        message("[Process Reporter] ", Sys.time(), "  Found ", length(active_tasks), " active tasks")
        
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
            warning("[Process Reporter] ", Sys.time(), " Error collecting metrics for run_id ", 
                    task$run_id, ": ", e$message)
          })
        }
      } else {
        message("[Process Reporter] ", Sys.time(), " No active tasks found")
      }
      
    }, error = function(e) {
      warning("[Process Reporter] ", Sys.time(), " Error in main loop: ", e$message)
    })
    
    # Calculate sleep time to maintain consistent interval
    loop_duration <- as.numeric(difftime(Sys.time(), loop_start, units = "secs"))
    sleep_time <- max(0, collection_interval_seconds - loop_duration)
    
    if (sleep_time > 0) {
      Sys.sleep(sleep_time)
    } else {
      warning("[Process Reporter] ", Sys.time(), " Loop took ", round(loop_duration, 2), 
              " seconds (longer than ", collection_interval_seconds, "s interval)")
    }
  }
  
  message("[Process Reporter] ", Sys.time(), " Main loop terminated")
  return(NULL)
}


#' Update Reporter Heartbeat
#'
#' Updates or inserts reporter status record with current heartbeat.
#' Handles both initial registration and ongoing heartbeat updates.
#'
#' @param con Database connection
#' @param hostname Reporter hostname
#'
#' @return TRUE if successful, FALSE otherwise
#' @keywords internal
update_reporter_heartbeat <- function(con, hostname) {
  
  tryCatch({
    table_name <- get_table_name("reporter_status", con, char = TRUE)
    current_pid <- Sys.getpid()
    current_time <- Sys.time()
    
    # Get current package version
    version <- utils::packageVersion("tasker")
    
    # Database-specific SQL for UPSERT operation
    config <- getOption("tasker.config")
    if (!is.null(config) && config$database$driver == "sqlite") {
      sql <- sprintf("
        INSERT OR REPLACE INTO %s 
        (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested)
        VALUES (?, ?, 
                COALESCE((SELECT started_at FROM %s WHERE hostname = ? AND process_id = ?), ?),
                ?, ?, FALSE)
      ", table_name, table_name)
      params <- list(hostname, current_pid, hostname, current_pid, current_time, current_time, as.character(version))
    } else {
      # PostgreSQL UPSERT
      sql <- sprintf("
        INSERT INTO %s (hostname, process_id, started_at, last_heartbeat, version, shutdown_requested)
        VALUES ($1, $2, $3, $4, $5, FALSE)
        ON CONFLICT (hostname) 
        DO UPDATE SET 
          process_id = EXCLUDED.process_id,
          started_at = CASE 
            WHEN %s.process_id != EXCLUDED.process_id THEN EXCLUDED.started_at
            ELSE %s.started_at
          END,
          last_heartbeat = EXCLUDED.last_heartbeat,
          version = EXCLUDED.version,
          shutdown_requested = FALSE
      ", table_name, table_name, table_name)
      params <- list(hostname, current_pid, current_time, current_time, as.character(version))
    }
    
    DBI::dbExecute(con, sql, params = params)
    return(TRUE)
    
  }, error = function(e) {
    warning("Failed to update reporter heartbeat: ", e$message)
    return(FALSE)
  })
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
    table_name <- get_table_name("reporter_status", con, char = TRUE)
    current_pid <- Sys.getpid()
    
    # Database-specific SQL - check for THIS process specifically
    config <- getOption("tasker.config")
    if (!is.null(config) && config$database$driver == "sqlite") {
      sql <- sprintf("
        SELECT shutdown_requested
        FROM %s
        WHERE hostname = ? AND process_id = ?
      ", table_name)
      params <- list(hostname, current_pid)
    } else {
      sql <- sprintf("
        SELECT shutdown_requested
        FROM %s
        WHERE hostname = $1 AND process_id = $2
      ", table_name)
      params <- list(hostname, current_pid)
    }
    
    result <- DBI::dbGetQuery(con, sql, params = params)
    
    if (nrow(result) > 0) {
      # SQLite uses INTEGER, PostgreSQL uses BOOLEAN
      return(result$shutdown_requested[1] == 1 || result$shutdown_requested[1] == TRUE)
    }
    
    # If no record exists for this specific process, don't shutdown
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
get_active_tasks_for_reporter <- function(con, hostname) {
  
  tryCatch({
    # Get table names directly to avoid configuration dependency issues
    config <- getOption("tasker.config")
    if (!is.null(config) && !is.null(config$database) && !is.null(config$database$schema)) {
      task_runs_table <- paste0(config$database$schema, ".task_runs")
      tasks_table <- paste0(config$database$schema, ".tasks")
    } else {
      task_runs_table <- "task_runs"
      tasks_table <- "tasks"
    }
    
    # Database-specific SQL
    if (!is.null(config) && config$database$driver == "sqlite") {
      sql <- sprintf("
        SELECT tr.run_id, tr.process_id, tr.start_time, COALESCE(t.task_name, 'Unknown') as task_name
        FROM %s tr
        LEFT JOIN %s t ON tr.task_id = t.task_id
        WHERE tr.hostname = ? 
          AND tr.status IN ('RUNNING', 'STARTED')
          AND tr.process_id IS NOT NULL
        ORDER BY tr.start_time
      ", task_runs_table, tasks_table)
    } else {
      sql <- sprintf("
        SELECT tr.run_id, tr.process_id, tr.start_time, COALESCE(t.task_name, 'Unknown') as task_name
        FROM %s tr
        LEFT JOIN %s t ON tr.task_id = t.task_id
        WHERE tr.hostname = $1 
          AND tr.status IN ('RUNNING', 'STARTED')
          AND tr.process_id IS NOT NULL
        ORDER BY tr.start_time
      ", task_runs_table, tasks_table)
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