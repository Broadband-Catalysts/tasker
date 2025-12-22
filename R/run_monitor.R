#' Launch the Tasker Pipeline Monitor
#'
#' Launches the Shiny application for monitoring task progress.
#'
#' @param port Integer port number for the Shiny app (default: NULL for random port)
#' @param host Character host IP address (default: "127.0.0.1")
#' @param launch.browser Logical whether to launch browser automatically (default: TRUE)
#' @param config_file Optional path to .tasker.yml config file
#'
#' @return No return value, called for side effect of launching Shiny app
#' @export
#'
#' @examples
#' \dontrun{
#'   # Launch the monitor
#'   run_monitor()
#'   
#'   # Launch on specific port
#'   run_monitor(port = 8080)
#'   
#'   # Use specific config file
#'   run_monitor(config_file = "/path/to/.tasker.yml")
#' }
run_monitor <- function(port = NULL, host = "127.0.0.1", launch.browser = TRUE, config_file = NULL) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Package 'shiny' is required to run the monitor. Please install it with: install.packages('shiny')")
  }
  
  if (!requireNamespace("DT", quietly = TRUE)) {
    stop("Package 'DT' is required to run the monitor. Please install it with: install.packages('DT')")
  }
  
  # Pre-load configuration before launching app
  tryCatch({
    if (!is.null(config_file)) {
      tasker_config(config_file = config_file)
    } else {
      tasker_config()
    }
  }, error = function(e) {
    stop(
      "Failed to load tasker configuration. ",
      "The monitor needs a valid .tasker.yml file or environment variables set.\n",
      "Error: ", e$message,
      call. = FALSE
    )
  })
  
  app_dir <- system.file("shiny", package = "tasker")
  
  if (app_dir == "") {
    stop("Could not find Shiny app directory. Please reinstall the tasker package.")
  }
  
  message("Starting Tasker Pipeline Monitor...")
  message("Press Ctrl+C or Esc to stop the server")
  
  shiny::runApp(
    appDir = app_dir,
    port = port,
    host = host,
    launch.browser = launch.browser
  )
}
