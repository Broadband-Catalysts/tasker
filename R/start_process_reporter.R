#' Start Process Reporter Service
#'
#' Starts a background process reporter daemon to monitor running tasks.
#' Uses callr::r_bg() to create a persistent background R process.
#'
#' @param collection_interval How often to collect metrics in seconds (default: 10)
#' @param hostname Hostname for reporter (default: current host)
#' @param force Force restart if reporter already running (default: FALSE)
#' @param quiet Suppress startup messages (default: FALSE)
#' @param conn Database connection (NULL = get default)
#'
#' @return List with process handle and status information
#' @export
#'
#' @examples
#' \dontrun{
#' # Start process reporter
#' reporter <- start_process_reporter()
#' 
#' # Check if it's running
#' reporter$process$is_alive()
#' 
#' # Stop reporter gracefully
#' stop_process_reporter()
#' }
start_process_reporter <- function(
    collection_interval = 10,
    hostname = Sys.info()["nodename"],
    force = FALSE,
    quiet = FALSE,
    conn = NULL
) {
  
  if (!quiet) {
    message("[Process Reporter] Starting reporter service on host: ", hostname)
  }
  
  # Check if reporter is already running
  existing_status <- get_process_reporter_status(hostname, con = conn)
  
  if (!is.null(existing_status) && !force) {
    # Check if the process is actually alive
    if (is_reporter_alive(existing_status$process_id, hostname)) {
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
    stop_process_reporter(hostname, timeout = 10, con = conn)
    Sys.sleep(2)  # Brief pause for clean shutdown
  }
  
  # Prepare arguments for background process
  args <- list(
    collection_interval_seconds = collection_interval,
    hostname = hostname
  )
  
  # Start background R process using callr::r_bg()
  tryCatch({
    bg_process <- callr::r_bg(
      func = function(collection_interval_seconds, hostname) {
        # Load the package in background process
        library(tasker)
        
        # Register this reporter process
        con <- tasker::get_db_connection()
        reporter_pid <- Sys.getpid()
        tasker:::register_reporter(con, hostname, reporter_pid)
        DBI::dbDisconnect(con)
        
        # Run main loop (this will handle its own database connection)
        tasker:::process_reporter_main_loop(
          collection_interval_seconds = collection_interval_seconds,
          hostname = hostname
        )
      },
      args = args,
      package = TRUE,  # Ensure package environment is available
      stdout = tempfile("process_reporter_", fileext = ".log"),
      stderr = tempfile("process_reporter_err_", fileext = ".log")
    )
    
    # Give the process a moment to start and register
    Sys.sleep(1)
    
    # Verify it started successfully
    if (bg_process$is_alive()) {
      bg_pid <- bg_process$get_pid()
      
      if (!quiet) {
        message("[Process Reporter] Background reporter started successfully (PID: ", bg_pid, ")")
        message("[Process Reporter] Collection interval: ", collection_interval, " seconds")
        message("[Process Reporter] Stdout log: ", bg_process$get_output_file())
        message("[Process Reporter] Stderr log: ", bg_process$get_error_file())
      }
      
      return(list(
        status = "started",
        process_id = bg_pid,
        started_at = Sys.time(),
        process = bg_process,
        stdout_log = bg_process$get_output_file(),
        stderr_log = bg_process$get_error_file()
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
#' Internal function to verify if a reporter process is actually running.
#' Uses ps package to check process existence.
#'
#' @param process_id Process ID to check
#' @param hostname Hostname (for logging)
#'
#' @return TRUE if process exists and is not zombie, FALSE otherwise
#' @keywords internal
is_reporter_alive <- function(process_id, hostname) {
  
  tryCatch({
    # Check if process exists
    p <- ps::ps_handle(process_id)
    
    # Check if it's not a zombie
    status <- ps::ps_status(p)
    if (status %in% c("zombie", "defunct")) {
      return(FALSE)
    }
    
    return(TRUE)
    
  }, error = function(e) {
    # Process doesn't exist or can't be accessed
    return(FALSE)
  })
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


#' Auto-start Process Reporter if needed
#'
#' Internal function called by task_start() to ensure a process reporter
#' is running when tasks are started.
#'
#' @param hostname Hostname to check/start reporter on
#' @param con Database connection
#'
#' @return TRUE if reporter is running (or started), FALSE if unable to start
#' @keywords internal
auto_start_process_reporter <- function(hostname = Sys.info()["nodename"], con = NULL) {
  
  # Check if auto-start is enabled
  if (!should_auto_start(con)) {
    return(FALSE)
  }
  
  # Check if reporter is already running
  existing_status <- get_process_reporter_status(hostname, con = con)
  
  if (!is.null(existing_status)) {
    # Verify it's actually alive
    if (is_reporter_alive(existing_status$process_id, hostname)) {
      return(TRUE)  # Already running
    }
  }
  
  # Try to start reporter
  tryCatch({
    result <- start_process_reporter(
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