#' Validate configuration
#'
#' @param config Configuration list
#' @return TRUE if valid (or stops with error)
#' @keywords internal
validate_config <- function(config) {
  # For SQLite, only dbname is required
  if (config$database$driver == "sqlite") {
    if (is.null(config$database$dbname) || config$database$dbname == "") {
      stop("Missing required configuration for SQLite: dbname (file path)")
    }
  } else {
    # For PostgreSQL/MySQL, require host, port, dbname, user
    required <- c("host", "port", "dbname", "user")
    missing <- character(0)
    
    for (field in required) {
      if (is.null(config$database[[field]]) || config$database[[field]] == "") {
        missing <- c(missing, field)
      }
    }
    
    if (length(missing) > 0) {
      stop("Missing required configuration: ", paste(missing, collapse = ", "))
    }
    
    if (!is.numeric(config$database$port) || 
        config$database$port < 1 || 
        config$database$port > 65535) {
      stop("Invalid port: ", config$database$port, ". Must be 1-65535")
    }
  }
  
  valid_drivers <- c("postgresql", "sqlite", "mysql")
  if (!config$database$driver %in% valid_drivers) {
    stop("Invalid driver '", config$database$driver, 
         "'. Must be one of: ", paste(valid_drivers, collapse = ", "))
  }
  
  TRUE
}
