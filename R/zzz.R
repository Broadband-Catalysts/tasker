#' Package loading hooks
#' 
#' @name tasker-hooks
#' @keywords internal
NULL

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