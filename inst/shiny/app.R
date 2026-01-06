library(shiny)
library(bslib)
library(DT)
library(dplyr)
library(lubridate)
library(shinyWidgets)
library(shinyjs)

devtools::load_all()

# Load configuration from .tasker.yml file
# Try several locations in order of preference
config_file <- NULL
search_paths <- c(
  "/home/warnes/src/fccData/.tasker.yml",
  "~/.tasker.yml",
  "./.tasker.yml"
)

TASKER_MONITOR_HOST <- Sys.getenv("TASKER_MONITOR_HOST", unset = "0.0.0.0")
TASKER_MONITOR_PORT <- as.numeric(Sys.getenv("TASKER_MONITOR_PORT", unset = "3838"))

# ============================================================================
# PROGRESS DATA HARVESTING: Non-reactive storage for completion time prediction
# ============================================================================

# Create environment for storing progress history (avoids reactive loops)
progress_history_env <- new.env(parent = emptyenv())


for (path in search_paths) {
  expanded_path <- path.expand(path)
  if (file.exists(expanded_path)) {
    config_file <- expanded_path
    message("Found tasker config at: ", config_file)
    break
  }
}

if (is.null(config_file)) {
  stop("No tasker configuration found. Searched: ", paste(search_paths, collapse=", "))
}

# Load and set configuration
config <- tasker::tasker_config(config_file = config_file)

# Read build information once at startup
# Assign to global environment so ui.R can access them
build_info_file <- "/app/build_info.txt"
if (file.exists(build_info_file)) {
  build_info_lines <- tryCatch({
    readLines(build_info_file, warn = FALSE)
  }, error = function(e) character(0))
  
  BUILD_TIME <<- if (length(build_info_lines) >= 1) {
    sub("BUILD_TIME=", "", build_info_lines[1])
  } else {
    "Unknown"
  }
  
  GIT_COMMIT <<- if (length(build_info_lines) >= 2) {
    sub("GIT_COMMIT=", "", build_info_lines[2])
  } else {
    "Unknown"
  }

  GIT_BRANCH <<- if (length(build_info_lines) >= 3) {
    sub("GIT_BRANCH=", "", build_info_lines[3])
  } else {
    "Unknown"
  }
} else {
  BUILD_TIME <<- "Unknown"
  GIT_COMMIT <<- "Unknown"
  GIT_BRANCH <<- "Unknown"
}

# Load UI
source("ui.R", local = TRUE)
source("server.R", local=TRUE)

# Helper functions
badge <- function(status) {
  bg_class <- switch(status,
    "COMPLETED" = "success",
    "RUNNING" = "warning",
    "FAILED" = "danger",
    "STARTED" = "info",
    "SKIPPED" = "secondary",
    "primary"
  )
  tags$span(class = paste("badge", paste0("bg-", bg_class)), status)
}

format_duration <- function(start, end) {
  sapply(seq_along(start), function(i) {
    s <- start[i]
    e <- end[i]
    
    if (is.na(s)) return("-")
    if (is.na(e)) e <- Sys.time()
    
    dur <- as.duration(interval(s, e))
    period <- seconds_to_period(as.numeric(dur, "seconds"))
    
    h <- hour(period)
    m <- minute(period)
    sec <- round(second(period))
    
    if (h > 0) {
      sprintf("%02d:%02d:%02d", h, m, sec)
    } else if (m > 0) {
      sprintf("%02d:%02d", m, sec)
    } else {
      sprintf("%ds", sec)
    }
  })
}

shiny::addResourcePath("www", normalizePath("www"))

shinyApp(
  ui = ui, 
  server = server, 
  options= list(
    host=TASKER_MONITOR_HOST,
    port=TASKER_MONITOR_PORT
  )
)
