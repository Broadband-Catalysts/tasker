#' Load or set tasker configuration
#'
#' @param config_file Path to .tasker.yml config file (optional)
#' @param host Database host (overrides config file)
#' @param port Database port (overrides config file)
#' @param dbname Database name (overrides config file)
#' @param user Username (overrides config file)
#' @param password Password (overrides config file)
#' @param schema Schema name (overrides config file, default: "tasker")
#' @param driver Database driver (overrides config file, default: "postgresql")
#' @param start_dir Directory to start searching for .tasker.yml (default: current working directory)
#' @param reload Force reload configuration (default: FALSE)
#' @return Invisibly returns configuration list
#' @export
#'
#' @examples
#' \dontrun{
#' # Auto-discover .tasker.yml
#' tasker_config()
#'
#' # Load specific file
#' tasker_config(config_file = "/path/to/.tasker.yml")
#'
#' # Override settings
#' tasker_config(host = "localhost", port = 5433)
#' }
tasker_config <- function(config_file = NULL,
                          host = NULL,
                          port = NULL,
                          dbname = NULL,
                          user = NULL,
                          password = NULL,
                          schema = NULL,
                          driver = NULL,
                          start_dir = getwd(),
                          reload = FALSE) {
  
  # Return existing config if not reloading
  if (!reload && !is.null(getOption("tasker.config"))) {
    return(invisible(getOption("tasker.config")))
  }
  
  # Find configuration file
  if (is.null(config_file)) {
    config_file <- find_config_file(start_dir = start_dir)
  }
  
  # Check if explicit parameters were provided
  has_explicit_params <- !is.null(host) || !is.null(port) || !is.null(dbname) || 
                         !is.null(user) || !is.null(password) || !is.null(schema) || 
                         !is.null(driver)
  
  # Check if environment variables provide config
  has_env_config <- Sys.getenv("TASKER_DB_HOST") != "" && 
                    Sys.getenv("TASKER_DB_NAME") != ""
  
  # Error if no config file, no env vars, and no explicit params
  if (is.null(config_file) && !has_explicit_params && !has_env_config) {
    stop(
      "No tasker configuration found. Please:\n",
      "  1. Create .tasker.yml in your project root, OR\n",
      "  2. Set TASKER_DB_* environment variables (at minimum: TASKER_DB_HOST and TASKER_DB_NAME), OR\n",
      "  3. Call tasker_config() with explicit parameters (host, dbname, user, etc.)\n",
      "\nSearched from: ", start_dir,
      call. = FALSE
    )
  }
  
  # Start with base config structure
  config <- list(
    database = list(
      host = "localhost",
      port = 5432,
      dbname = NULL,
      user = Sys.getenv("USER"),
      password = NULL,
      schema = "tasker",
      driver = "postgresql"
    )
  )
  
  # Load from file if available
  if (!is.null(config_file) && file.exists(config_file)) {
    yaml_config <- load_yaml_config(config_file)
    config <- merge_configs(config, yaml_config)
    config$loaded_from <- config_file
    
    # Set environment variables from config if present
    if (!is.null(yaml_config$environment) && is.list(yaml_config$environment)) {
      for (var_name in names(yaml_config$environment)) {
        var_value <- as.character(yaml_config$environment[[var_name]])
        do.call(Sys.setenv, setNames(list(var_value), var_name))
      }
    }
  }
  
  # Load from environment variables
  env_config <- load_env_config()
  config <- merge_configs(config, env_config)
  
  # Apply parameter overrides
  if (!is.null(host)) config$database$host <- host
  if (!is.null(port)) config$database$port <- as.integer(port)
  if (!is.null(dbname)) config$database$dbname <- dbname
  if (!is.null(user)) config$database$user <- user
  if (!is.null(password)) config$database$password <- password
  if (!is.null(schema)) config$database$schema <- schema
  if (!is.null(driver)) config$database$driver <- driver
  
  validate_config(config)
  
  config$loaded_at <- Sys.time()
  options(tasker.config = config)
  
  message("tasker configuration loaded successfully")
  if (!is.null(config$loaded_from)) {
    message("  Config file: ", config$loaded_from)
  }
  message("  Database: ", config$database$user, "@", 
          config$database$host, ":", config$database$port, 
          "/", config$database$dbname)
  
  invisible(config)
}
