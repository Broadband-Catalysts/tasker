#' Create Tasker Configuration
#'
#' Interactive function to create a .tasker.yml configuration file.
#' Prompts for any values not provided as arguments.
#'
#' @param path Directory where the .tasker.yml file should be created. Defaults to current directory.
#' @param force Logical; if TRUE, overwrites existing .tasker.yml file. Default is FALSE.
#' @param db_driver Database driver: "postgresql" or "sqlite"
#' @param db_host Database host (PostgreSQL only)
#' @param db_port Database port (PostgreSQL only)
#' @param db_name Database name (PostgreSQL only)
#' @param db_schema Schema name (PostgreSQL only)
#' @param db_user Database user (PostgreSQL only)
#' @param db_password Database password (PostgreSQL only)
#' @param db_path SQLite database file path (SQLite only)
#' @param log_path Directory for log files
#' @param script_path Directory for script files
#' @param pipeline_name Name of the pipeline
#' @param pipeline_version Version of the pipeline
#'
#' @return Invisibly returns the path to the created configuration file.
#' @export
#'
#' @examples
#' \dontrun{
#'   # Interactive configuration
#'   create_tasker_config()
#'   
#'   # With arguments, no prompting
#'   create_tasker_config(
#'     db_driver = "postgresql",
#'     db_host = "localhost",
#'     db_name = "mydb",
#'     db_user = "user",
#'     db_password = "pass",
#'     pipeline_name = "My Pipeline"
#'   )
#' }
create_tasker_config <- function(
    path = ".", 
    force = FALSE,
    db_driver = NULL,
    db_host = NULL,
    db_port = NULL,
    db_name = NULL,
    db_schema = NULL,
    db_user = NULL,
    db_password = NULL,
    db_path = NULL,
    log_path = NULL,
    script_path = NULL,
    pipeline_name = NULL,
    pipeline_version = NULL
) {
  config_file <- file.path(path, ".tasker.yml")
  
  # Check if file already exists
  if (file.exists(config_file) && !force) {
    stop("Configuration file already exists at: ", config_file, 
         "\nUse force = TRUE to overwrite.")
  }
  
  # Only show header if we need to prompt
  need_prompt <- is.null(db_driver) || is.null(pipeline_name) ||
    (is.null(log_path) || is.null(script_path))
  
  if (need_prompt) {
    cat("\n=== Tasker Configuration Setup ===\n\n")
  }
  
  # Database configuration
  if (is.null(db_driver)) {
    cat("Database Configuration:\n")
    db_driver <- readline("Database driver (postgresql/sqlite) [postgresql]: ")
    if (db_driver == "") db_driver <- "postgresql"
  }
  
  if (db_driver == "postgresql") {
    if (is.null(db_host)) {
      db_host <- readline("Database host [localhost]: ")
      if (db_host == "") db_host <- "localhost"
    }
    
    if (is.null(db_port)) {
      db_port <- readline("Database port [5432]: ")
      if (db_port == "") db_port <- "5432"
    }
    
    if (is.null(db_name)) {
      db_name <- readline("Database name: ")
    }
    
    if (is.null(db_schema)) {
      db_schema <- readline("Schema name [tasker]: ")
      if (db_schema == "") db_schema <- "tasker"
    }
    
    if (is.null(db_user)) {
      db_user <- readline("Database user: ")
    }
    
    if (is.null(db_password)) {
      db_password <- readline("Database password: ")
    }
    
  } else if (db_driver == "sqlite") {
    if (is.null(db_path)) {
      db_path <- readline("SQLite database file path [./tasker.db]: ")
      if (db_path == "") db_path <- "./tasker.db"
    }
  } else {
    stop("Unsupported database driver: ", db_driver)
  }
  
  # Logging configuration
  if (is.null(log_path) || is.null(script_path)) {
    cat("\nLogging Configuration:\n")
  }
  
  if (is.null(log_path)) {
    log_path <- readline("Log file directory [./logs]: ")
    if (log_path == "") log_path <- "./logs"
  }
  
  if (is.null(script_path)) {
    script_path <- readline("Script directory [./scripts]: ")
    if (script_path == "") script_path <- "./scripts"
  }
  
  # Pipeline configuration
  if (is.null(pipeline_name) || is.null(pipeline_version)) {
    cat("\nPipeline Configuration:\n")
  }
  
  if (is.null(pipeline_name)) {
    pipeline_name <- readline("Pipeline name: ")
  }
  
  if (is.null(pipeline_version)) {
    pipeline_version <- readline("Pipeline version [1.0]: ")
    if (pipeline_version == "") pipeline_version <- "1.0"
  }
  
  # Build configuration content
  if (db_driver == "postgresql") {
    config_content <- sprintf(
"# Tasker Configuration
# This file configures the tasker package for tracking pipeline execution

database:
  driver: %s
  host: %s
  port: %s
  dbname: %s
  schema: %s
  user: %s
  password: \"%s\"

logging:
  log_path: %s
  script_path: %s

pipeline:
  name: %s
  version: %s
",
      db_driver, db_host, db_port, db_name, db_schema, db_user, db_password,
      log_path, script_path, pipeline_name, pipeline_version
    )
  } else {
    config_content <- sprintf(
"# Tasker Configuration
# This file configures the tasker package for tracking pipeline execution

database:
  driver: %s
  path: %s

logging:
  log_path: %s
  script_path: %s

pipeline:
  name: %s
  version: %s
",
      db_driver, db_path,
      log_path, script_path, pipeline_name, pipeline_version
    )
  }
  
  # Write configuration file
  writeLines(config_content, config_file)
  
  cat("\n✓ Configuration file created at:", config_file, "\n")
  cat("\nYou can now use tasker functions which will automatically load this configuration.\n")
  
  invisible(config_file)
}
