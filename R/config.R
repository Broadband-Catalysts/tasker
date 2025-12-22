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
  
  # Start with existing config if reload and config exists
  if (reload && !is.null(getOption("tasker.config"))) {
    config <- getOption("tasker.config")
  } else if (!reload && !is.null(getOption("tasker.config"))) {
    return(invisible(getOption("tasker.config")))
  } else {
    # Default config
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
  }
  
  # Only reload from file if not reloading with overrides
  if (!reload || is.null(getOption("tasker.config"))) {
    if (is.null(config_file)) {
      config_file <- find_config_file(start_dir = start_dir)
    }
    
    if (!is.null(config_file) && file.exists(config_file)) {
      yaml_config <- load_yaml_config(config_file)
      config <- merge_configs(config, yaml_config)
      config$loaded_from <- config_file
    }
    
    env_config <- load_env_config()
    config <- merge_configs(config, env_config)
  }
  
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


#' Find .tasker.yml configuration file
#'
#' @param start_dir Starting directory (default: current working directory)
#' @param filename Configuration filename (default: ".tasker.yml")
#' @param max_depth Maximum directory levels to search up (default: 10)
#' @return Path to config file, or NULL if not found
#' @export
find_config_file <- function(start_dir = getwd(), 
                             filename = ".tasker.yml",
                             max_depth = 10) {
  
  current_dir <- normalizePath(start_dir, mustWork = FALSE)
  
  for (i in 1:max_depth) {
    config_path <- file.path(current_dir, filename)
    
    if (file.exists(config_path)) {
      return(normalizePath(config_path))
    }
    
    parent_dir <- dirname(current_dir)
    
    if (parent_dir == current_dir) {
      break
    }
    
    current_dir <- parent_dir
  }
  
  return(NULL)
}


#' Get current tasker configuration
#'
#' @return List with configuration settings, or NULL if not loaded
#' @export
get_tasker_config <- function() {
  getOption("tasker.config")
}


#' Load YAML configuration file
#'
#' @param config_file Path to YAML file
#' @return List with configuration
#' @keywords internal
load_yaml_config <- function(config_file) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' required for configuration files. Install with: install.packages('yaml')")
  }
  
  tryCatch({
    config <- yaml::read_yaml(config_file)
    config <- expand_env_vars(config)
    config
  }, error = function(e) {
    stop("Failed to parse configuration file '", config_file, "': ", e$message)
  })
}


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


#' Expand environment variables in configuration
#'
#' @param config Configuration list
#' @return Configuration list with expanded variables
#' @keywords internal
expand_env_vars <- function(config) {
  if (is.list(config)) {
    lapply(config, expand_env_vars)
  } else if (is.character(config)) {
    pattern <- "\\$\\{([^}]+)\\}"
    matches <- gregexpr(pattern, config, perl = TRUE)
    
    if (matches[[1]][1] != -1) {
      for (match_info in regmatches(config, matches)[[1]]) {
        var_name <- sub("\\$\\{([^}]+)\\}", "\\1", match_info, perl = TRUE)
        var_value <- Sys.getenv(var_name, "")
        config <- sub(match_info, var_value, config, fixed = TRUE)
      }
    }
    
    config
  } else {
    config
  }
}


#' Merge two configuration lists
#'
#' @param base Base configuration
#' @param overlay Configuration to overlay
#' @return Merged configuration
#' @keywords internal
merge_configs <- function(base, overlay) {
  if (!is.list(overlay) || length(overlay) == 0) {
    return(base)
  }
  
  for (name in names(overlay)) {
    if (is.list(overlay[[name]]) && is.list(base[[name]])) {
      base[[name]] <- merge_configs(base[[name]], overlay[[name]])
    } else if (!is.null(overlay[[name]])) {
      base[[name]] <- overlay[[name]]
    }
  }
  
  base
}


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
    missing <- setdiff(required, names(config$database))
    
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


#' Ensure configuration is loaded
#'
#' @return TRUE if configured
#' @keywords internal
ensure_configured <- function() {
  config <- getOption("tasker.config")
  
  if (is.null(config)) {
    tryCatch({
      tasker_config()
    }, error = function(e) {
      stop(
        "tasker is not configured. Please:\n",
        "  1. Create .tasker.yml in your project root, OR\n",
        "  2. Set TASKER_DB_* environment variables, OR\n",
        "  3. Call tasker_config() with explicit parameters\n",
        "\nError: ", e$message,
        call. = FALSE
      )
    })
  }
  
  TRUE
}
