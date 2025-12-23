# Internal utility functions for tasker package

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


#' Prepare parameters for SQL queries (handle NULLs)
#' @param ... Parameters to prepare
#' @return List of parameters with NULL converted to NA
#' @keywords internal
prepare_params <- function(...) {
  params <- list(...)
  # Convert NULL to NA for RSQLite compatibility
  lapply(params, function(x) if (is.null(x)) NA else x)
}


#' Get parent process ID
#' @return Parent PID or NULL
#' @keywords internal
get_parent_pid <- function() {
  tryCatch({
    if (.Platform$OS.type == "unix") {
      ppid <- system2("ps", c("-o", "ppid=", "-p", Sys.getpid()), 
                      stdout = TRUE, stderr = FALSE)
      as.integer(trimws(ppid))
    } else {
      NULL
    }
  }, error = function(e) NULL)
}


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
