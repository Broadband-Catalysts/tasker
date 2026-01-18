#!/usr/bin/env Rscript
# Process Reporter Daemon
# Background service that monitors and reports process metrics to database
# 
# This script is launched by tasker::start_reporter() as a standalone
# background process that persists independently of the parent R session.

# Parse command line arguments - use simple parsing since argparse may not be available
args <- commandArgs(trailingOnly = TRUE)

# Simple named argument parsing
collection_interval_seconds <- 10  # default
hostname <- Sys.info()["nodename"]  # default

# Parse --interval and --hostname arguments
i <- 1
while (i <= length(args)) {
  if (args[i] == "--interval" && i < length(args)) {
    collection_interval_seconds <- as.integer(args[i + 1])
    i <- i + 2
  } else if (args[i] == "--hostname" && i < length(args)) {
    hostname <- args[i + 1]
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

# Load configuration
tasker_config()

# Verify configuration loaded
if (is.null(getOption("tasker.config"))) {
  stop("Failed to load tasker configuration in background process")
}

# The main loop will handle reporter registration through update_reporter_heartbeat()
# Run main loop (this will handle its own database connection)
tasker:::reporter_main_loop(
  collection_interval_seconds = collection_interval_seconds,
  hostname = hostname
)
