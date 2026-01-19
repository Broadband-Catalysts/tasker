#' Get table name with or without schema
#' @param table Table name
#' @param conn Database connection
#' @param char Return character string instead of DBI::SQL object (default: FALSE)
#' @return SQL identifier with schema prefix if applicable, or character string if char=TRUE
#' @keywords internal
get_table_name <- function(table, conn, char = FALSE) {
  config <- getOption("tasker.config")
  if (is.null(config) || is.null(config$database) || is.null(config$database$driver)) {
    stop("tasker configuration not loaded. Call load_tasker_config() first.")
  }
  
  db_driver <- config$database$driver
  
  if (db_driver == "sqlite") {
    result <- table
  } else {
    schema <- config$database$schema
    if (is.null(schema) || nchar(schema) == 0) {
      result <- table
    } else {
      result <- sprintf("%s.%s", schema, table)
    }
  }
  
  if (char) {
    return(result)
  } else {
    return(DBI::SQL(result))
  }
}
