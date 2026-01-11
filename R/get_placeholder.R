#' Get SQL placeholder for parameter
#' 
#' Returns the correct parameter placeholder syntax for the database
#' 
#' @param n Parameter number (1-based)
#' @param conn Database connection (optional)
#' @return Placeholder string ("$1" for PostgreSQL, "?" for SQLite/MySQL)
#' @keywords internal
get_placeholder <- function(n = NULL, conn = NULL) {
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  if (driver == "postgresql") {
    if (is.null(n)) return("$")
    return(paste0("$", n))
  } else {
    # SQLite and MySQL use ?
    return("?")
  }
}
