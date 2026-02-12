#!/usr/bin/env Rscript
# Reporter Daemon
# Background service that monitors and reports process metrics to database
# 
# This script is launched by tasker::start_reporter() as a standalone
# background process that persists independently of the parent R session.

# Parse command line arguments - use simple parsing since argparse may not be available
args <- commandArgs(trailingOnly = TRUE)

# Simple named argument parsing
collection_interval_seconds <- 10  # default
hostname <- Sys.info()["nodename"]  # default
config_file <- NULL  # default - use normal config search

# Parse --interval, --hostname, and --config-file arguments
i <- 1
while (i <= length(args)) {
  if (args[i] == "--interval" && i < length(args)) {
    collection_interval_seconds <- as.integer(args[i + 1])
    i <- i + 2
  } else if (args[i] == "--hostname" && i < length(args)) {
    hostname <- args[i + 1]
    i <- i + 2
  } else if (args[i] == "--config-file" && i < length(args)) {
    config_file <- args[i + 1]
    i <- i + 2
  } else {
    # Skip unknown arguments
    i <- i + 1
  }
}

# Validate arguments
if (is.na(collection_interval_seconds) || collection_interval_seconds <= 0) {
  collection_interval_seconds <- 10
}
if (is.na(hostname) || hostname == "") {
  hostname <- Sys.info()["nodename"]
}

# Library paths are inherited from R_LIBS_USER environment variable
# (set by parent process when launching this daemon)

# Load tasker package
library(tasker)

# Load configuration - use specified config file if provided
if (!is.null(config_file)) {
  tasker_config(config_file = config_file)
} else {
  tasker_config()
}

# Verify configuration loaded
if (is.null(getOption("tasker.config"))) {
  stop("Failed to load tasker configuration in background process")
}

# Check if another reporter is already running for this hostname
# This prevents duplicate reporters when daemon is started directly or via race conditions
current_pid <- Sys.getpid()
tryCatch({
  con <- tasker:::get_db_connection()
  existing_status <- tasker:::get_reporter_database_status(hostname, con = con)
  
  if (!is.null(existing_status) && existing_status$process_id != current_pid) {
    # Check if the existing process is actually alive
    status <- tasker:::get_reporter_status(existing_status$process_id, hostname, con = con)
    
    if (status$is_alive) {
      message("[Reporter] ", Sys.time(), " Another reporter already running (PID: ", 
              existing_status$process_id, "). Exiting.")
      DBI::dbDisconnect(con)
      quit(save = "no", status = 0)
    } else {
      message("[Reporter] ", Sys.time(), " Existing reporter appears dead (PID: ", 
              existing_status$process_id, "). Proceeding to start.")
    }
  }
  
  DBI::dbDisconnect(con)
}, error = function(e) {
  # If we can't check (e.g., DB error), log and proceed anyway
  warning("[Reporter] ", Sys.time(), " Could not check for existing reporter: ", e$message)
})

# The main loop will handle reporter registration through update_reporter_heartbeat()
# Run main loop (this will handle its own database connection)
tasker:::reporter_main_loop(
  collection_interval_seconds = collection_interval_seconds,
  hostname = hostname
)
