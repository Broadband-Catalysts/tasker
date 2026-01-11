#' Build parameterized SQL with correct placeholders
#' 
#' Replaces $1, $2, etc. with correct placeholders for the database
#' 
#' @param sql SQL string with $1, $2, ... placeholders
#' @param conn Database connection (optional)
#' @return SQL string with correct placeholders
#' @keywords internal
build_sql <- function(sql, conn = NULL) {
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  if (driver == "sqlite" || driver == "mysql") {
    # Replace $1, $2, ... with ?
    sql <- gsub("\\$[0-9]+", "?", sql)
  }
  
  sql
}
