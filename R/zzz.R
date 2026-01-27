#' Package loading hooks
#' 
#' @name tasker-hooks
#' @keywords internal
NULL

#' Initialize logging on package load
#' 
#' Automatically configures logger with sensible defaults when tasker is loaded.
#' 
#' @rdname tasker-hooks
#' @keywords internal
.onLoad <- function(libname, pkgname) {
  
  # Check for user-specified log level
  log_level <- getOption("tasker.log_level")
  if (is.null(log_level)) {
    log_level <- Sys.getenv("TASKER_LOG_LEVEL", "")
    if (log_level == "") {
      log_level <- NULL  # Will auto-detect
    }
  }
  
  # Initialize logging with defaults (WARN level - quiet by default)
  tryCatch({
    setup_logging(
      log_level = if (is.null(log_level)) "WARN" else log_level,
      namespace = "tasker"
    )
  }, error = function(e) {
    if (requireNamespace("logger", quietly = TRUE)) {
      warning("Failed to initialize tasker logging: ", e$message)
    }
  })
}

#' @rdname tasker-hooks
#' @keywords internal
.onAttach <- function(libname, pkgname) {
  config <- getOption("tasker.config")
  if (!is.null(config)) {
    packageStartupMessage("tasker configuration loaded successfully")
    packageStartupMessage("  Config file: ", attr(config, "config_file"))
    packageStartupMessage("  Database: ", config$database$user, "@", config$database$host, ":", config$database$port, "/", config$database$dbname)
  }
}