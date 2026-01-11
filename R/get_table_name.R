#' Get table name with or without schema
#' @param table Table name
#' @param conn Database connection
#' @return SQL identifier with schema prefix if applicable
#' @keywords internal
get_table_name <- function(table, conn) {
  config <- getOption("tasker.config")
  if (is.null(config) || is.null(config$database) || is.null(config$database$driver)) {
    stop("tasker configuration not loaded. Call load_tasker_config() first.")
  }
  
  db_driver <- config$database$driver
  
  if (db_driver == "sqlite") {
    return(DBI::SQL(table))
  } else {
    schema <- config$database$schema
    if (is.null(schema) || nchar(schema) == 0) {
      return(DBI::SQL(table))
    }
    return(DBI::SQL(sprintf("%s.%s", schema, table)))
  }
}
