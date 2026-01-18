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
    message("[Process Reporter] Starting reporter service on host: ", hostname)
  }
  
  # Check if reporter is already running
  existing_status <- get_reporter_database_status(hostname, con = conn)
  
  if (!is.null(existing_status) && !force) {
    # Check if the process is actually alive
    if (get_reporter_status(existing_status$process_id, hostname)$is_alive) {
      if (!quiet) {
        message("[Process Reporter] Reporter already running (PID: ", existing_status$process_id, ")")
      }
      return(list(
        status = "already_running",
        process_id = existing_status$process_id,
        started_at = existing_status$started_at,
        process = NULL
      ))
    } else {
      if (!quiet) {
        message("[Process Reporter] Existing reporter appears dead, starting new one")
      }
    }
  } else if (!is.null(existing_status) && force) {
    if (!quiet) {
      message("[Process Reporter] Force restart requested, stopping existing reporter")
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
  log_file <- file.path(log_path, sprintf("process_reporter_%s_%s.log", 
                                          hostname, 
                                          format(Sys.time(), "%Y%m%d_%H%M%S")))
  
  # Prepare arguments for background process
  args <- list(
    collection_interval_seconds = collection_interval,
    hostname = hostname,
    config = current_config
  )
  
  # Start background R process using callr::r_bg()
  tryCatch({
    bg_process <- callr::r_bg(
      func = function(collection_interval_seconds, hostname, config, working_dir) {
        # Set working directory first to ensure config can be found
        setwd(working_dir)
        
        # Load the package in background process
        library(tasker)
        
        # Load configuration explicitly (since auto-load was removed)
        tasker_config()
        
        # Verify configuration loaded
        if (is.null(getOption("tasker.config"))) {
          stop("Failed to load tasker configuration in background process")
        }
        
        # Register this reporter process
        con <- tasker::get_db_connection()
        reporter_pid <- Sys.getpid()
        tasker:::register_reporter(con, hostname, reporter_pid)
        DBI::dbDisconnect(con)
        
        # Run main loop (this will handle its own database connection)
        tasker:::reporter_main_loop(
          collection_interval_seconds = collection_interval_seconds,
          hostname = hostname
        )
      },
      args = list(
        collection_interval_seconds = collection_interval,
        hostname = hostname,
        config = current_config,
        working_dir = getwd()
      ),
      package = TRUE,  # Ensure package environment is available
      stdout = log_file,
      stderr = log_file,  # Same file for both stdout and stderr
      supervise = supervise
    )
    
    # Give the process a moment to start and register
    Sys.sleep(1)
    
    # Verify it started successfully
    if (bg_process$is_alive()) {
      bg_pid <- bg_process$get_pid()
      
      if (!quiet) {
        message("[Process Reporter] Background reporter started successfully (PID: ", bg_pid, ")")
        message("[Process Reporter] Collection interval: ", collection_interval, " seconds")
        if (!supervise) {
          message("[Process Reporter] Reporter will persist after parent process exits")
          message("[Process Reporter] To stop: tasker::stop_reporter() or kill PID ", bg_pid)
        }
        message("[Process Reporter] Stdout log: ", log_file)
        message("[Process Reporter] Stderr log: ", log_file)  # Same file for both
      }
      
      return(list(
        status = "started",
        process_id = bg_pid,
        started_at = Sys.time(),
        process = bg_process,
        stdout_log = log_file,
        stderr_log = log_file
      ))
      
    } else {
      stop("Background process failed to start or died immediately")
    }
    
  }, error = function(e) {
    stop("Failed to start process reporter: ", e$message)
  })
}


#' Check if Process Reporter is alive
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
    table_name <- get_table_name("process_reporter_status", con, char = TRUE)
    
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
#' Internal function to determine if the process reporter should 
#' be auto-started for new tasks.
#'
#' @param con Database connection
#'
#' @return TRUE if auto-start should be enabled, FALSE otherwise
#' @keywords internal
should_auto_start <- function(con = NULL) {

  # Allow disabling auto-start (e.g., in unit tests)
  if (isTRUE(getOption("tasker.process_reporter.auto_start", TRUE)) == FALSE) {
    return(FALSE)
  }
  if (Sys.getenv("TASKER_PROCESS_REPORTER_AUTO_START") %in% c("0", "false", "FALSE", "no", "NO")) {
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
  
  # Check if process reporter tables exist
  tryCatch({
    table_name <- get_table_name("process_reporter_status", con, char = TRUE)
    
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
    warning("Failed to auto-start process reporter: ", e$message)
    return(FALSE)
  })
}