#' Launch the Tasker Pipeline Monitor
#'
#' Launches the Shiny application for monitoring task progress.
#'
#' @param port Integer port number for the Shiny app (default: NULL for random port)
#' @param host Character host IP address (default: "127.0.0.1")
#' @param launch.browser Logical whether to launch browser automatically (default: TRUE)
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
#' }
run_monitor <- function(port = NULL, host = "127.0.0.1", launch.browser = TRUE) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Package 'shiny' is required to run the monitor. Please install it with: install.packages('shiny')")
  }
  
  if (!requireNamespace("DT", quietly = TRUE)) {
    stop("Package 'DT' is required to run the monitor. Please install it with: install.packages('DT')")
  }
  
  app_dir <- system.file("shiny", package = "tasker")
  
  if (app_dir == "") {
    stop("Could not find Shiny app directory. Please reinstall the tasker package.")
  }
  
  shiny::runApp(
    appDir = app_dir,
    port = port,
    host = host,
    launch.browser = launch.browser
  )
}
