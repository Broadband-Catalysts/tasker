#' Check Process Reporter Status
#'
#' Displays information about all running process reporters in the database.
#' Shows hostname, PID, version, heartbeat status, and whether the process
#' is still alive.
#'
#' @param con Database connection (NULL = get default)
#' @param quiet If TRUE, returns data without printing (default: FALSE)
#'
#' @return Data frame with reporter information, or NULL if no reporters found
#' @export
#'
#' @examples
#' \dontrun{
#' # Display all process reporters
#' check_process_reporter()
#' 
#' # Get data without printing
#' reporters <- check_process_reporter(quiet = TRUE)
#' }
check_process_reporter <- function(con = NULL, quiet = FALSE) {
  
  close_con <- FALSE
  if (is.null(con)) {
    con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (is.null(con)) {
      if (!quiet) message("Cannot connect to database")
      return(NULL)
    }
    close_con <- TRUE
  }
  
  on.exit({
    if (close_con && !is.null(con)) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  })
  
  # Query all process reporters
  result <- tryCatch({
    table_name <- get_table_name("process_reporter_status", con, char = TRUE)
    
    # Database-specific timestamp difference calculation
    config <- getOption("tasker.config")
    if (!is.null(config) && config$database$driver == "sqlite") {
      sql <- sprintf("
        SELECT 
          hostname,
          process_id,
          started_at,
          last_heartbeat,
          version,
          shutdown_requested,
          CAST((julianday('now') - julianday(last_heartbeat)) * 86400 AS INTEGER) as heartbeat_age_seconds
        FROM %s
        ORDER BY hostname
      ", table_name)
    } else {
      # PostgreSQL
      sql <- sprintf("
        SELECT 
          hostname,
          process_id,
          started_at,
          last_heartbeat,
          version,
          shutdown_requested,
          EXTRACT(EPOCH FROM (NOW() - last_heartbeat))::INTEGER as heartbeat_age_seconds
        FROM %s
        ORDER BY hostname
      ", table_name)
    }
    
    DBI::dbGetQuery(con, sql)
  }, error = function(e) {
    if (!quiet) warning("Failed to query reporter status: ", e$message)
    return(NULL)
  })
  
  if (is.null(result) || nrow(result) == 0) {
    if (!quiet) message("No process reporters found in database")
    return(NULL)
  }
  
  # Check if each process is actually alive
  if (requireNamespace("ps", quietly = TRUE)) {
    result$is_alive <- sapply(seq_len(nrow(result)), function(i) {
      tryCatch({
        is_reporter_alive(result$process_id[i], result$hostname[i])
      }, error = function(e) {
        NA  # Can't determine if alive
      })
    })
  } else {
    result$is_alive <- NA
  }
  
  # Add status summary
  result$status <- sapply(seq_len(nrow(result)), function(i) {
    if (is.na(result$is_alive[i])) {
      return("UNKNOWN")
    } else if (!result$is_alive[i]) {
      return("DEAD")
    } else if (result$shutdown_requested[i]) {
      return("SHUTTING_DOWN")
    } else if (result$heartbeat_age_seconds[i] > 60) {
      return("STALE")
    } else {
      return("RUNNING")
    }
  })
  
  if (!quiet) {
    cat("\n")
    cat("================================================================================\n")
    cat("Process Reporter Status\n")
    cat("================================================================================\n\n")
    
    if (nrow(result) == 1) {
      cat("Found 1 process reporter:\n\n")
    } else {
      cat("Found", nrow(result), "process reporters:\n\n")
    }
    
    for (i in seq_len(nrow(result))) {
      cat("Hostname:      ", result$hostname[i], "\n")
      cat("Process ID:    ", result$process_id[i], "\n")
      cat("Status:        ", result$status[i], "\n")
      cat("Version:       ", ifelse(is.na(result$version[i]), "(unknown)", result$version[i]), "\n")
      cat("Started:       ", result$started_at[i], "\n")
      cat("Last Heartbeat:", result$last_heartbeat[i], "(", 
          result$heartbeat_age_seconds[i], "seconds ago)\n")
      
      if (result$shutdown_requested[i]) {
        cat("               *** Shutdown requested ***\n")
      }
      
      if (result$status[i] == "STALE") {
        cat("               ⚠️  Heartbeat is stale (>60s old)\n")
      }
      
      if (result$status[i] == "DEAD") {
        cat("               ❌ Process is not running\n")
      }
      
      if (i < nrow(result)) {
        cat("\n")
        cat("--------------------------------------------------------------------------------\n\n")
      }
    }
    
    cat("\n")
    cat("================================================================================\n\n")
  }
  
  invisible(result)
}
