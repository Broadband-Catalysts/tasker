#' Ensure configuration is loaded
#'
#' @return TRUE if configured
#' @keywords internal
ensure_configured <- function() {
  config <- getOption("tasker.config")
  
  if (is.null(config)) {
    tryCatch({
      tasker_config()
    }, error = function(e) {
      stop(
        "tasker is not configured. Please:\n",
        "  1. Create .tasker.yml in your project root, OR\n",
        "  2. Set TASKER_DB_* environment variables, OR\n",
        "  3. Call tasker_config() with explicit parameters\n",
        "\nError: ", e$message,
        call. = FALSE
      )
    })
  }
  
  TRUE
}
