#' Start Reporter Service
#'
#' Starts a background reporter daemon to monitor running tasks.
#' Uses callr::r_bg() to create a persistent background R process.
#'
#' @param collection_interval How often to collect metrics in seconds (default: 10)
#' @param hostname Hostname for reporter (default: current host)
#' @param force Force restart if reporter already running (default: FALSE)
#' @param quiet Suppress startup messages (default: FALSE)
#' @param conn Database connection (NULL = get default)
#' @param supervise If FALSE (default), reporter persists after parent process exits.
#'   If TRUE, reporter is automatically terminated when parent R process exits.
#'
#' @return List with process handle and status information
#' @export
#'
#' @examples
#' \dontrun{
#' # Start reporter
#' reporter <- start_reporter()
#' 
#' # Check if it's running
#' reporter$process$is_alive()
#' 
#' # Stop reporter gracefully
#' stop_reporter()
#' }
start_reporter <- function(
    collection_interval = 10,
    hostname = Sys.info()["nodename"],
    force = FALSE,
    quiet = FALSE,
    conn = NULL,
    supervise = FALSE
) {
  
  if (!quiet) {
    message("[Reporter] Starting reporter service on host: ", hostname)
  }
  
  # Check if reporter is already running
  existing_status <- get_reporter_database_status(hostname, con = conn)
  
  if (!is.null(existing_status) && !force) {
    # Check if the process is actually alive
    if (get_reporter_status(existing_status$process_id, hostname)$is_alive) {
      if (!quiet) {
        message("[Reporter] Reporter already running (PID: ", existing_status$process_id, ")")
      }
      return(list(
        status = "already_running",
        process_id = existing_status$process_id,
        started_at = existing_status$started_at,
        process = NULL
      ))
    } else {
      if (!quiet) {
        message("[Reporter] Existing reporter appears dead, starting new one")
      }
    }
  } else if (!is.null(existing_status) && force) {
    if (!quiet) {
      message("[Reporter] Force restart requested, stopping existing reporter")
    }
    stop_reporter(hostname, timeout = 10, con = conn)
    Sys.sleep(2)  # Brief pause for clean shutdown
  }
  
  # Get current tasker configuration to pass to background process
  ensure_configured()
  current_config <- getOption("tasker.config")
  if (is.null(current_config)) {
    stop("tasker configuration not loaded. Call tasker_config() first.", call. = FALSE)
  }
  
  # Determine log file path from config
  log_path <- if (!is.null(current_config$logging$log_path)) {
    current_config$logging$log_path
  } else {
    "/tmp"
  }
  
  # Ensure log directory exists
  if (!dir.exists(log_path)) {
    dir.create(log_path, recursive = TRUE)
  }
  
  # Create log file name with hostname and timestamp
  log_file <- file.path(log_path, sprintf("reporter_%s_%s.log", 
                                          hostname, 
                                          format(Sys.time(), "%Y%m%d_%H%M%S")))
  
  # Get path to the daemon script in the installed package
  daemon_script <- system.file("bin", "reporter_daemon.R", package = "tasker")
  
  if (!file.exists(daemon_script)) {
    stop("Cannot find reporter daemon script. Package may not be properly installed.", call. = FALSE)
  }
  
  # Prepare environment variables to pass library paths to daemon process
  # This ensures the daemon can load tasker and its dependencies
  lib_paths <- paste(.libPaths(), collapse = .Platform$path.sep)
  env_vars <- sprintf("R_LIBS_USER='%s'", lib_paths)
  
  # Start truly independent background R process using system() with nohup
  tryCatch({
    # Use nohup to make process completely independent
    r_cmd <- file.path(R.home("bin"), "Rscript")
    cmd <- sprintf("nohup env %s %s '%s' --interval %d --hostname '%s' > '%s' 2>&1 </dev/null & echo $!", 
                   env_vars, r_cmd, daemon_script, collection_interval, hostname, log_file)
    
    bg_pid <- as.integer(system(cmd, intern = TRUE))
    
    if (is.na(bg_pid) || bg_pid <= 0) {
      stop("Failed to start background process - got invalid PID")
    }
    
    # Give the process a moment to start and register
    Sys.sleep(1)
    
    # Verify it started successfully by checking if PID exists
    pid_check <- system2("ps", args = c("-p", bg_pid), stdout = FALSE, stderr = FALSE)
    process_alive <- (pid_check == 0)
    process_alive <- (pid_check == 0)
    
    if (process_alive) {
      if (!quiet) {
        message("[Reporter] Background reporter started successfully (PID: ", bg_pid, ")")
        message("[Reporter] Collection interval: ", collection_interval, " seconds")
        message("[Reporter] Reporter will persist after parent process exits")
        message("[Reporter] To stop: tasker::stop_reporter() or kill PID ", bg_pid)
        message("[Reporter] Stdout log: ", log_file)
        message("[Reporter] Stderr log: ", log_file)
      }
      
      return(list(
        status = "started",
        process_id = bg_pid,
        started_at = Sys.time(),
        process = NULL,  # No process handle - truly independent
        stdout_log = log_file,
        stderr_log = log_file
      ))
      
    } else {
      stop("Background process failed to start or died immediately")
    }
    
  }, error = function(e) {
    stop("Failed to start reporter: ", e$message)
  })
}


#' Check if Reporter is alive
#'
#' Comprehensive function to determine if a reporter process is actually running.
#' Uses ps package to check process existence if on the same machine,
#' otherwise falls back to checking heartbeat age from database.
#' Also validates hostname matching and heartbeat freshness.
#'
#' @param process_id Process ID to check
#' @param hostname Hostname of the process
#' @param max_heartbeat_age_seconds Maximum age for heartbeat to consider process alive (default: 60)
#' @param con Database connection for heartbeat checking (optional)
#'
#' @return List with is_alive (logical), status (character), heartbeat_age_seconds (integer)
#' @keywords internal
get_reporter_status <- function(process_id, hostname, max_heartbeat_age_seconds = 60, con = NULL) {
  
  # Get current machine hostname for comparison
  current_hostname <- Sys.info()["nodename"]
  is_same_machine <- (hostname == current_hostname)
  
  # Initialize return values
  is_alive <- FALSE
  status <- "UNKNOWN"
  heartbeat_age_seconds <- NA
  
  # Get database connection and heartbeat info first
  close_con <- FALSE
  if (is.null(con)) {
    con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (is.null(con)) {
      return(list(
        is_alive = FALSE,
        status = "DB_ERROR", 
        heartbeat_age_seconds = NA,
        same_machine = is_same_machine
      ))
    }
    close_con <- TRUE
  }
  
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  # Get heartbeat info from database
  tryCatch({
    table_name <- get_table_name("reporter_status", con, char = TRUE)
    
    # Database-specific SQL for heartbeat age
    config <- getOption("tasker.config")
    if (!is.null(config) && config$database$driver == "sqlite") {
      sql <- sprintf("
        SELECT 
          CAST((julianday('now') - julianday(last_heartbeat)) * 86400 AS INTEGER) as heartbeat_age_seconds,
          shutdown_requested
        FROM %s
        WHERE hostname = ? AND process_id = ?
      ", table_name)
    } else {
      sql <- sprintf("
        SELECT 
          EXTRACT(EPOCH FROM (NOW() - last_heartbeat))::INTEGER as heartbeat_age_seconds,
          shutdown_requested
        FROM %s
        WHERE hostname = $1 AND process_id = $2
      ", table_name)
    }
    
    result <- DBI::dbGetQuery(con, sql, params = list(hostname, process_id))
    
    if (nrow(result) > 0 && !is.na(result$heartbeat_age_seconds[1])) {
      heartbeat_age_seconds <- result$heartbeat_age_seconds[1]
      shutdown_requested <- result$shutdown_requested[1]
      
      # If shutdown was requested, mark as shutting down
      if (shutdown_requested) {
        status <- "SHUTTING_DOWN"
        is_alive <- FALSE
      } else if (heartbeat_age_seconds > max_heartbeat_age_seconds) {
        status <- "STALE"
        is_alive <- FALSE
      } else {
        # Heartbeat is recent, now check process existence if on same machine
        if (is_same_machine) {
          tryCatch({
            # Use ps package for accurate process checking
            p <- ps::ps_handle(process_id)
            
            # Check if it's not a zombie
            ps_status <- ps::ps_status(p)
            if (ps_status %in% c("zombie", "defunct")) {
              status <- "ZOMBIE"
              is_alive <- FALSE
            } else {
              status <- "RUNNING"
              is_alive <- TRUE
            }
          }, error = function(e) {
            # Process doesn't exist or can't be accessed
            status <- "DEAD"
            is_alive <- FALSE
          })
        } else {
          # Different machine - trust the heartbeat
          status <- "RUNNING"
          is_alive <- TRUE
        }
      }
    } else {
      # No database record found
      status <- "NOT_REGISTERED"
      is_alive <- FALSE
    }
  }, error = function(e) {
    # Database error
    status <- "DB_ERROR"
    is_alive <- FALSE
  })
  
  return(list(
    is_alive = is_alive,
    status = status,
    heartbeat_age_seconds = heartbeat_age_seconds,
    same_machine = is_same_machine
  ))
}


#' Check if auto-start should be enabled
#'
#' Internal function to determine if the reporter should 
#' be auto-started for new tasks.
#'
#' @param con Database connection
#'
#' @return TRUE if auto-start should be enabled, FALSE otherwise
#' @keywords internal
should_auto_start <- function(con = NULL) {

  # Allow disabling auto-start (e.g., in unit tests)
  if (isTRUE(getOption("tasker.reporter.auto_start", TRUE)) == FALSE) {
    return(FALSE)
  }
  if (Sys.getenv("TASKER_REPORTER_AUTO_START") %in% c("0", "false", "FALSE", "no", "NO")) {
    return(FALSE)
  }
  
  close_con <- FALSE
  if (is.null(con)) {
    con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (is.null(con)) return(FALSE)
    close_con <- TRUE
  }
  
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  # Check if reporter tables exist
  tryCatch({
    table_name <- get_table_name("reporter_status", con, char = TRUE)
    
    # Simple query to check if table exists and is accessible
    DBI::dbGetQuery(con, sprintf("SELECT 1 FROM %s LIMIT 1", table_name))
    
    return(TRUE)
    
  }, error = function(e) {
    # Tables don't exist or aren't accessible
    return(FALSE)
  })
}


#' Auto-start Reporter if needed
#'
#' Internal function called by task_start() to ensure a reporter
#' is running when tasks are started.
#'
#' @param hostname Hostname to check/start reporter on
#' @param con Database connection
#'
#' @return TRUE if reporter is running (or started), FALSE if unable to start
#' @keywords internal
auto_start_reporter <- function(hostname = Sys.info()["nodename"], con = NULL) {

  if (isTRUE(getOption("tasker.process_reporter.auto_start", TRUE)) == FALSE) {
    return(FALSE)
  }
  if (Sys.getenv("TASKER_PROCESS_REPORTER_AUTO_START") %in% c("0", "false", "FALSE", "no", "NO")) {
    return(FALSE)
  }
  
  # Check if auto-start is enabled
  if (!should_auto_start(con)) {
    return(FALSE)
  }
  
  # Check if reporter is already running
  existing_status <- get_reporter_database_status(hostname, con = con)
  
  if (!is.null(existing_status)) {
    # Verify it's actually alive
    if (get_reporter_status(existing_status$process_id, hostname)$is_alive) {
      return(TRUE)  # Already running
    }
  }
  
  # Try to start reporter
  tryCatch({
    result <- start_reporter(
      hostname = hostname,
      force = FALSE,
      quiet = TRUE,  # Don't spam messages during auto-start
      conn = con
    )
    
    return(result$status %in% c("started", "already_running"))
    
  }, error = function(e) {
    warning("Failed to auto-start reporter: ", e$message)
    return(FALSE)
  })
}