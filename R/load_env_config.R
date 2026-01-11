#' Load configuration from environment variables
#'
#' @return List with configuration from environment
#' @keywords internal
load_env_config <- function() {
  config <- list(database = list())
  
  if (Sys.getenv("TASKER_DB_HOST") != "") {
    config$database$host <- Sys.getenv("TASKER_DB_HOST")
  }
  
  if (Sys.getenv("TASKER_DB_PORT") != "") {
    config$database$port <- as.integer(Sys.getenv("TASKER_DB_PORT"))
  }
  
  if (Sys.getenv("TASKER_DB_NAME") != "") {
    config$database$dbname <- Sys.getenv("TASKER_DB_NAME")
  }
  
  if (Sys.getenv("TASKER_DB_USER") != "") {
    config$database$user <- Sys.getenv("TASKER_DB_USER")
  }
  
  if (Sys.getenv("TASKER_DB_PASSWORD") != "") {
    config$database$password <- Sys.getenv("TASKER_DB_PASSWORD")
  }
  
  if (Sys.getenv("TASKER_DB_SCHEMA") != "") {
    config$database$schema <- Sys.getenv("TASKER_DB_SCHEMA")
  }
  
  if (Sys.getenv("TASKER_DB_DRIVER") != "") {
    config$database$driver <- Sys.getenv("TASKER_DB_DRIVER")
  }
  
  config
}
