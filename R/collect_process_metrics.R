#' Collect process metrics for a running task
#'
#' Collects comprehensive resource usage metrics for a specific task's process,
#' including CPU, memory, I/O, and child process aggregates. Validates process
#' start time to detect PID reuse.
#'
#' @param run_id Task run ID (UUID)
#' @param process_id Main process PID
#' @param hostname Hostname where process is running (default: current host)
#' @param include_children Collect child process aggregate info (default: TRUE)
#' @param timeout_seconds Maximum time to spend collecting metrics (default: 5)
#' @param prev_start_time Previous process start time for PID reuse detection (optional)
#' @param scale_cpu_by_cores Scale CPU percentage by number of CPU cores (default: FALSE)
#'
#' @return List with metrics data or error information
#' @export
#'
#' @examples
#' \dontrun{
#' metrics <- collect_process_metrics(
#'   run_id = "550e8400-e29b-41d4-a716-446655440000",
#'   process_id = 12345
#' )
#' }
collect_process_metrics <- function(
    run_id,
    process_id,
    hostname = Sys.info()["nodename"],
    include_children = TRUE,
    timeout_seconds = 5,
    prev_start_time = NULL,
    scale_cpu_by_cores = FALSE
) {
  
  collection_start <- Sys.time()
  
  # Initialize result structure
  result <- list(
    run_id = run_id,
    process_id = process_id,
    hostname = hostname,
    collection_error = FALSE,
    error_message = NULL,
    error_type = NULL,
    is_alive = TRUE
  )
  
  # Wrap collection in timeout
  tryCatch({
    R.utils::withTimeout({
      
      # Get process handle
      p <- tryCatch(
        ps::ps_handle(process_id),
        error = function(e) {
          if (grepl("No such (process|file|directory)", e$message, ignore.case = TRUE)) {
            result$collection_error <<- TRUE
            result$error_type <<- "PROCESS_DIED"
            result$error_message <<- sprintf("Process %d no longer exists", process_id)
            result$is_alive <<- FALSE
            return(NULL)
          } else {
            stop(e)
          }
        }
      )
      
      if (is.null(p)) return(result)
      
      # Get process start time
      process_start_time <- tryCatch(
        ps::ps_create_time(p),
        error = function(e) {
          result$collection_error <<- TRUE
          result$error_type <<- "PS_ERROR"
          result$error_message <<- paste("Failed to get process start time:", e$message)
          return(NULL)
        }
      )
      
      if (!is.null(process_start_time)) {
        result$process_start_time <- process_start_time
        
        # Check for PID reuse
        if (!is.null(prev_start_time) && 
            abs(as.numeric(difftime(process_start_time, prev_start_time, units = "secs"))) > 1) {
          result$collection_error <- TRUE
          result$error_type <- "PID_REUSED"
          result$error_message <- sprintf(
            "Process PID %d was reused (start time changed)",
            process_id
          )
          result$is_alive <- FALSE
          return(result)
        }
      }
      
      # Check if process is zombie
      status <- tryCatch(ps::ps_status(p), error = function(e) NULL)
      if (!is.null(status) && status %in% c("zombie", "defunct")) {
        result$collection_error <- TRUE
        result$error_type <- "ZOMBIE_PROCESS"
        result$error_message <- sprintf("Process %d is %s", process_id, status)
        result$is_alive <- FALSE
        return(result)
      }
      
      # CPU usage - Calculate percentage based on CPU time difference
      # Store previous CPU times in a package environment for tracking
      if (!exists(".cpu_time_cache", envir = .GlobalEnv)) {
        assign(".cpu_time_cache", new.env(hash = TRUE), envir = .GlobalEnv)
        # Cache CPU count since it's constant for the system - calculate once
        assign(".cpu_count_cached", tryCatch(ps::ps_cpu_count(), error = function(e) 1), envir = .GlobalEnv)
      }
      cpu_cache <- get(".cpu_time_cache", envir = .GlobalEnv)
      num_cores <- get(".cpu_count_cached", envir = .GlobalEnv)
      
      cpu_times <- tryCatch(ps::ps_cpu_times(p), error = function(e) NULL)
      if (!is.null(cpu_times)) {
        current_time <- Sys.time()
        current_total <- cpu_times["user"] + cpu_times["system"]
        cache_key <- as.character(process_id)
        
        # Check if we have a previous measurement
        if (exists(cache_key, envir = cpu_cache)) {
          prev_data <- get(cache_key, envir = cpu_cache)
          time_diff <- as.numeric(difftime(current_time, prev_data$time, units = "secs"))
          
          if (time_diff > 0 && time_diff < 300) {  # Reasonable time interval (< 5 minutes)
            cpu_diff <- current_total - prev_data$cpu_total
            # Convert to percentage: CPU time delta / elapsed time * 100
            # Optionally scale by CPU cores if requested
            if (scale_cpu_by_cores) {
              result$cpu_percent <- (cpu_diff / time_diff / num_cores) * 100
            } else {
              result$cpu_percent <- (cpu_diff / time_diff) * 100
            }
          } else {
            result$cpu_percent <- NA_real_  # First measurement or too much time passed
          }
        } else {
          result$cpu_percent <- NA_real_  # First measurement
        }
        
        # Store current measurement for next time
        assign(cache_key, list(time = current_time, cpu_total = current_total), envir = cpu_cache)
      } else {
        result$cpu_percent <- NA_real_
      }
      
      # Include CPU core count in results for client-side scaling
      result$cpu_cores <- num_cores
      
      # Memory usage
      mem_info <- tryCatch(ps::ps_memory_info(p), error = function(e) NULL)
      if (!is.null(mem_info)) {
        result$memory_mb <- mem_info["rss"] / 1024^2
        result$memory_vms_mb <- mem_info["vms"] / 1024^2
      }
      
      # Memory percent
      result$memory_percent <- tryCatch(
        ps::ps_memory_percent(p),
        error = function(e) NA_real_
      )
      
      # Number of threads
      result$num_threads <- tryCatch(
        ps::ps_num_threads(p),
        error = function(e) NA_integer_
      )
      
      # Open files / file descriptors
      result$num_fds <- tryCatch(
        ps::ps_num_fds(p),
        error = function(e) NA_integer_
      )
      
      # Open files count
      open_files <- tryCatch(
        length(ps::ps_open_files(p)),
        error = function(e) NA_integer_
      )
      result$open_files <- open_files
      
      # Child process aggregates (direct children only)
      if (include_children) {
        children <- tryCatch(
          ps::ps_children(p, recursive = FALSE),
          error = function(e) list()
        )
        
        result$child_count <- length(children)
        
        if (length(children) > 0) {
          child_cpu <- sapply(children, function(c) {
            tryCatch(ps::ps_cpu_percent(c), error = function(e) 0)
          })
          result$child_total_cpu_percent <- sum(child_cpu, na.rm = TRUE)
          
          child_mem <- sapply(children, function(c) {
            tryCatch({
              mem <- ps::ps_memory_info(c)
              mem["rss"] / 1024^2
            }, error = function(e) 0)
          })
          result$child_total_memory_mb <- sum(child_mem, na.rm = TRUE)
        } else {
          result$child_total_cpu_percent <- 0
          result$child_total_memory_mb <- 0
        }
      }
      
    }, timeout = timeout_seconds, onTimeout = "silent")
    
  }, TimeoutException = function(e) {
    result$collection_error <- TRUE
    result$error_type <- "COLLECTION_TIMEOUT"
    result$error_message <- sprintf("Metrics collection exceeded %d seconds", timeout_seconds)
  }, error = function(e) {
    result$collection_error <- TRUE
    result$error_type <- "UNKNOWN"
    result$error_message <- paste("Unexpected error:", conditionMessage(e))
  })
  
  # Record collection duration
  result$collection_duration_ms <- as.integer(
    difftime(Sys.time(), collection_start, units = "secs") * 1000
  )
  
  # Add reporter version
  result$reporter_version <- as.character(packageVersion("tasker"))
  
  return(result)
}
