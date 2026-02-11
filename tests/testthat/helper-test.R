# Test helpers

#' Get verbosity setting for SQL scripts during tests
#' 
#' Checks TASKER_TEST_SQL_VERBOSE environment variable to determine if
#' SQL script execution should be verbose. Defaults to FALSE (quiet) unless
#' explicitly set to "true", "1", or "yes".
#' 
#' @return Logical indicating if SQL scripts should print verbose output
#' @examples
#' # In tests:
#' bbcDB::dbExecuteScript(conn, schema_file, .quiet = !sql_script_verbose())
sql_script_verbose <- function() {
  env_val <- Sys.getenv("TASKER_TEST_SQL_VERBOSE", "false")
  tolower(env_val) %in% c("true", "1", "yes")
}

# Use SQLite for testing by default
get_test_db_path <- function() {
  file.path(tempdir(), "tasker_test.db")
}

#' Setup test database with SQLite
setup_test_db <- function() {
  db_path <- get_test_db_path()
  
  # Remove existing test database
  if (file.exists(db_path)) {
    unlink(db_path)
  }
  
  # Configure tasker to use SQLite
  tasker::tasker_config(
    driver = "sqlite",
    dbname = db_path,
    schema = "",  # SQLite doesn't use schemas
    reload = TRUE
  )

  # Avoid callr background processes during unit tests
  options(tasker.process_reporter.auto_start = FALSE)
  
  # Create full schema (tables + reporter tables + views)
  # Use environment variable to control SQL verbosity during testing
  tasker::setup_tasker_db(force = TRUE, quiet = !sql_script_verbose())

  # Persist the path for callers that need it
  options(tasker.test_db_path = db_path)

  # Return a DBI connection for convenience (many tests expect a connection)
  tasker:::ensure_configured()
  con <- tasker::get_db_connection()
  return(con)
}

#' Clean up test database
cleanup_test_db <- function(con = NULL) {
  # Accept either a DBI connection or a path to the DB file
  if (!is.null(con)) {
    if (is.character(con)) {
      db_path <- con
      if (file.exists(db_path)) unlink(db_path)
    } else {
      # try disconnecting if it's a DBI connection
      tryCatch({
        if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
      }, error = function(e) NULL)
      # remove file from known test path as well
      db_path <- get_test_db_path()
      if (file.exists(db_path)) unlink(db_path)
    }
  } else {
    # No arg provided: remove the default test DB path
    db_path <- get_test_db_path()
    if (file.exists(db_path)) unlink(db_path)
  }
  
  # Clear config
  options(tasker.config = NULL)
  options(tasker.process_reporter.auto_start = NULL)
  
  invisible(NULL)
}

#' Get test database connection
get_test_db_connection <- function() {
  tasker:::ensure_configured()
  tasker::get_db_connection()
}

#' Create temporary config file for reporter background processes
#' 
#' Creates a .tasker.yml config file pointing to the test SQLite database
#' so that spawned reporter processes connect to the test DB instead of production.
#' 
#' @return Path to temporary config file
create_test_config_file <- function() {
  db_path <- getOption("tasker.test_db_path", get_test_db_path())
  
  # Create temp config file
  config_file <- tempfile(pattern = "tasker_test_config_", fileext = ".yml")
  
  # Write config pointing to test database
  config_content <- sprintf("
database:
  driver: sqlite
  dbname: %s
  schema: ''
", db_path)
  
  writeLines(config_content, config_file)
  
  return(config_file)
}
#' Cleanup orphaned reporter processes from test execution
#' 
#' Finds and terminates any reporter processes that were spawned by this test
#' process (identified by parent PID). This prevents reporter process leakage
#' that can exhaust database connections.
#' 
#' **Problem:** Tests that start reporter processes using start_reporter() create
#' background R processes via callr::r_bg(). If tests fail or don't properly clean up,
#' these reporter processes continue running and maintain database connections.
#' Over multiple test runs, this exhausts the database connection pool.
#' 
#' **Solution:** This function finds all running R processes whose parent PID matches
#' the current test process, checks if they're reporters (by looking for the
#' process_reporter_main_loop function in their command line), and terminates them.
#' 
#' @param timeout Maximum seconds to wait for graceful shutdown (default: 5)
#' @param con Database connection (optional, uses configured connection if NULL)
#' @param quiet Suppress informational messages (default: FALSE)
#' 
#' @return List with:
#'   - found: Number of orphaned reporters found
#'   - stopped: Number successfully stopped
#'   - failed: Number that failed to stop
#'   
#' @details
#' This function should be called:
#' 1. In teardown files (tests/testthat/teardown-*.R) to clean up after all tests
#' 2. In individual test on.exit() handlers that spawn reporters
#' 3. Before test runs to ensure clean slate
#' 
#' The function performs these steps:
#' 1. Get current test process PID
#' 2. Find all R processes that are children of this PID
#' 3. Check each for reporter-specific patterns (process_reporter_main_loop)
#' 4. Attempt graceful shutdown via stop_reporter() 
#' 5. Force-kill any that don't stop gracefully
#' 
#' @examples
#' \dontrun{
#' # At end of test file
#' cleanup_test_reporters()
#' 
#' # In test with on.exit
#' on.exit({
#'   cleanup_test_reporters(quiet = TRUE)
#'   cleanup_test_db()
#' }, add = TRUE)
#' }
cleanup_test_reporters <- function(timeout = 5, con = NULL, quiet = FALSE) {
  if (!requireNamespace("ps", quietly = TRUE)) {
    if (!quiet) message("ps package not available, skipping reporter cleanup")
    return(list(found = 0, stopped = 0, failed = 0))
  }
  
  # Import stringr functions for clean string matching
  import::from(stringr, str_detect, regex)
  
  current_pid <- Sys.getpid()
  found <- 0
  stopped <- 0
  failed <- 0
  
  # Get database connection if not provided
  close_con <- FALSE
  if (is.null(con)) {
    con <- tryCatch(get_test_db_connection(), error = function(e) NULL)
    if (!is.null(con)) close_con <- TRUE
  }
  
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  # Find all reporter processes spawned by this test process
  tryCatch({
    all_procs <- ps::ps()
    
    # Find R processes that are children of current test process
    child_r_procs <- all_procs |>
      dplyr::filter(
        ppid == current_pid,
        str_detect(name, regex("(R|Rscript)", ignore_case = TRUE))
      )
    
    if (nrow(child_r_procs) == 0) {
      if (!quiet) message("No child R processes found")
      return(list(found = 0, stopped = 0, failed = 0))
    }
    
    # Check each child process to see if it's a reporter
    for (i in seq_len(nrow(child_r_procs))) {
      proc_pid <- child_r_procs$pid[i]
      
      # Try to get command line to confirm it's a reporter
      is_reporter <- FALSE
      tryCatch({
        proc_info <- ps::ps_handle(proc_pid)
        cmdline <- paste(ps::ps_cmdline(proc_info), collapse = " ")
        
        # Reporter processes run process_reporter_main_loop or contain reporter config
        if (grepl("process_reporter_main_loop|reporter.*config|start_reporter", cmdline, ignore.case = TRUE)) {
          is_reporter <- TRUE
        }
      }, error = function(e) {
        # Process may have already exited or access denied
      })
      
      if (is_reporter) {
        found <- found + 1
        
        if (!quiet) {
          message(sprintf("Found orphaned reporter process: PID %d", proc_pid))
        }
        
        # Try graceful shutdown first if we have database access
        graceful_stop <- FALSE
        if (!is.null(con)) {
          # Try to find hostname for this reporter in database
          tryCatch({
            table_name <- tasker:::get_table_name("reporter_status", con, char = TRUE)
            query <- sprintf("SELECT hostname FROM %s WHERE process_id = %d", table_name, proc_pid)
            result <- DBI::dbGetQuery(con, query)
            
            if (nrow(result) > 0) {
              hostname <- result$hostname[1]
              if (!quiet) message(sprintf("  Attempting graceful shutdown for hostname: %s", hostname))
              
              graceful_result <- tryCatch(
                tasker::stop_reporter(hostname, timeout = timeout, con = con),
                error = function(e) FALSE
              )
              
              graceful_stop <- isTRUE(graceful_result)
            }
          }, error = function(e) {
            # Database query failed, will try force kill
          })
        }
        
        # If graceful stop failed or wasn't attempted, force kill
        if (!graceful_stop) {
          kill_result <- tryCatch({
            if (!quiet) message(sprintf("  Force killing PID %d", proc_pid))
            proc_handle <- ps::ps_handle(proc_pid)
            ps::ps_kill(proc_handle)
            
            # Wait briefly to confirm termination
            Sys.sleep(0.5)
            
            # Check if process is gone
            !ps::ps_is_running(proc_handle)
          }, error = function(e) {
            FALSE
          })
          
          if (kill_result) {
            stopped <- stopped + 1
          } else {
            failed <- failed + 1
            if (!quiet) warning(sprintf("  Failed to stop reporter PID %d", proc_pid))
          }
        } else {
          stopped <- stopped + 1
        }
      }
    }
    
  }, error = function(e) {
    if (!quiet) warning("Error during reporter cleanup: ", e$message)
  })
  
  if (!quiet && found > 0) {
    message(sprintf("Reporter cleanup: found=%d, stopped=%d, failed=%d", found, stopped, failed))
  }
  
  return(list(found = found, stopped = stopped, failed = failed))
}