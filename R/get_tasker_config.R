#' Get current tasker configuration
#'
#' @return List with configuration settings, or NULL if not loaded
#' @export
get_tasker_config <- function() {
  getOption("tasker.config")
}
