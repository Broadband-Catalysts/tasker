# tasker Configuration System - Implementation Reference

**Date:** 2025-12-21  
**Purpose:** Reference implementation for configuration loading system

---

## File: R/config.R

```r
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
#' @param reload Force reload configuration (default: FALSE)
#' @return Invisibly returns configuration list
#' @export
#'
#' @examples
#' # Auto-discover .tasker.yml
#' tasker_config()
#'
#' # Load specific file
#' tasker_config(config_file = "/path/to/.tasker.yml")
#'
#' # Override settings
#' tasker_config(host = "localhost", port = 5433)
tasker_config <- function(config_file = NULL,
                          host = NULL,
                          port = NULL,
                          dbname = NULL,
                          user = NULL,
                          password = NULL,
                          schema = NULL,
                          driver = NULL,
                          reload = FALSE) {
  
  # Check if already loaded and not reloading
  if (!reload && !is.null(getOption("tasker.config"))) {
    return(invisible(getOption("tasker.config")))
  }
  
  # Step 1: Start with defaults
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
  
  # Step 2: Load configuration file if available
  if (is.null(config_file)) {
    config_file <- find_config_file()
  }
  
  if (!is.null(config_file) && file.exists(config_file)) {
    yaml_config <- load_yaml_config(config_file)
    config <- merge_configs(config, yaml_config)
    config$loaded_from <- config_file
  }
  
  # Step 3: Apply environment variables
  env_config <- load_env_config()
  config <- merge_configs(config, env_config)
  
  # Step 4: Apply explicit parameters (highest priority)
  if (!is.null(host)) config$database$host <- host
  if (!is.null(port)) config$database$port <- as.integer(port)
  if (!is.null(dbname)) config$database$dbname <- dbname
  if (!is.null(user)) config$database$user <- user
  if (!is.null(password)) config$database$password <- password
  if (!is.null(schema)) config$database$schema <- schema
  if (!is.null(driver)) config$database$driver <- driver
  
  # Step 5: Validate configuration
  validate_config(config)
  
  # Step 6: Store in options
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
    
    # Move up one directory
    parent_dir <- dirname(current_dir)
    
    # Check if we've reached the filesystem root
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
    
    # Expand environment variables
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
    # Replace ${VAR} with environment variable value
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
      # Recursively merge lists
      base[[name]] <- merge_configs(base[[name]], overlay[[name]])
    } else if (!is.null(overlay[[name]])) {
      # Override with non-null values
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
  # Check required fields
  required <- c("host", "port", "dbname", "user")
  missing <- setdiff(required, names(config$database))
  
  if (length(missing) > 0) {
    stop("Missing required configuration: ", paste(missing, collapse = ", "))
  }
  
  # Validate driver
  valid_drivers <- c("postgresql", "sqlite", "mysql")
  if (!config$database$driver %in% valid_drivers) {
    stop("Invalid driver '", config$database$driver, 
         "'. Must be one of: ", paste(valid_drivers, collapse = ", "))
  }
  
  # Validate port
  if (!is.numeric(config$database$port) || 
      config$database$port < 1 || 
      config$database$port > 65535) {
    stop("Invalid port: ", config$database$port, ". Must be 1-65535")
  }
  
  TRUE
}


#' Ensure configuration is loaded
#'
#' Internal function called by all tasker functions to ensure
#' configuration is loaded before use. No-op if already loaded.
#'
#' @return TRUE if configured
#' @keywords internal
ensure_configured <- function() {
  config <- getOption("tasker.config")
  
  if (is.null(config)) {
    # Try to auto-load configuration
    tryCatch({
      tasker_config()
    }, error = function(e) {
      stop(
        "tasker is not configured. Please:\n",
        "  1. Create .tasker.yml in your project root, OR\n",
        "  2. Set TASKER_DB_* environment variables, OR\n",
        "  3. Call tasker_config() with explicit parameters\n",
        "\nError: ", e$message
      )
    })
  }
  
  TRUE
}
```

---

## Example .tasker.yml

```yaml
# tasker configuration file
# Place in project root directory

database:
  # Database connection settings
  host: db.example.com
  port: 5432
  dbname: geodb
  user: tasker_user
  
  # Use environment variable for password (recommended)
  password: ${TASKER_DB_PASSWORD}
  
  # Schema where tasker tables are located
  schema: tasker
  
  # Database driver: postgresql, sqlite, or mysql
  driver: postgresql

# Optional: Connection pool settings
pool:
  min_size: 1
  max_size: 5
  idle_timeout: 300  # seconds

# Optional: Stage detection patterns (regex)
stage_patterns:
  PREREQ: "^(prereq|setup|install)"
  DAILY: "^DAILY_"
  MONTHLY: "^MONTHLY_"
  ANNUAL_DEC: "^ANNUAL_DEC_"
  ANNUAL_JUN: "^ANNUAL_JUN_"

# Optional: Logging settings
logging:
  level: INFO  # DEBUG, INFO, WARN, ERROR
  file: tasker.log
  console: true
```

---

## Example .tasker.yml.example (for version control)

```yaml
# tasker configuration file template
# Copy to .tasker.yml and customize

database:
  host: your-db-host
  port: 5432
  dbname: your-database
  user: your-username
  
  # IMPORTANT: Use environment variable for password
  # Set TASKER_DB_PASSWORD in your environment
  password: ${TASKER_DB_PASSWORD}
  
  schema: tasker
  driver: postgresql

# Uncomment to customize connection pooling
# pool:
#   min_size: 1
#   max_size: 5
#   idle_timeout: 300

# Uncomment to customize stage patterns
# stage_patterns:
#   PREREQ: "^(prereq|setup)"
#   DAILY: "^DAILY_"
#   CUSTOM: "^CUSTOM_"
```

---

## Integration Example

**File: R/track_init.R**

```r
#' Initialize task tracking
#'
#' @param task_name Name of task being tracked
#' @param total_subtasks Expected number of subtasks
#' @param stage Pipeline stage
#' @param db_conn Database connection (optional)
#' @return Tracking run_id (UUID)
#' @export
track_init <- function(task_name,
                       total_subtasks = NULL,
                       stage = NULL,
                       db_conn = NULL) {
  
  # Ensure configuration is loaded
  ensure_configured()
  
  # Get connection
  if (is.null(db_conn)) {
    db_conn <- get_db_connection()
  }
  
  # ... rest of function ...
}
```

---

## Usage Examples

### Example 1: Auto-discovery

```r
# Project structure:
# /home/user/myproject/
# ├── .tasker.yml
# ├── scripts/
# │   └── daily/
# │       └── process.R

# In process.R:
library(tasker)

# Configuration loaded automatically from ../../.tasker.yml
track_init("process.R")
```

### Example 2: Explicit file

```r
# Load specific configuration
tasker_config(config_file = "~/.tasker-dev.yml")

# Now use tasker
track_init("my_script.R")
```

### Example 3: Override settings

```r
# Load default config but override host
tasker_config(host = "localhost", port = 5433)

track_init("test_script.R")
```

### Example 4: Environment variables only

```bash
# In ~/.bashrc or ~/.Renviron
export TASKER_DB_HOST=db.example.com
export TASKER_DB_PORT=5432
export TASKER_DB_NAME=geodb
export TASKER_DB_USER=tasker_user
export TASKER_DB_PASSWORD=secret123
export TASKER_DB_SCHEMA=tasker
```

```r
# No config file needed
library(tasker)

# Configuration loaded from environment
track_init("my_script.R")
```

### Example 5: Check configuration

```r
# Load configuration
tasker_config()

# View current configuration
config <- get_tasker_config()
str(config)

# Output:
# List of 3
#  $ database    :List of 7
#   ..$ host    : chr "db.example.com"
#   ..$ port    : int 5432
#   ..$ dbname  : chr "geodb"
#   ..$ user    : chr "tasker_user"
#   ..$ password: chr "***"
#   ..$ schema  : chr "tasker"
#   ..$ driver  : chr "postgresql"
#  $ loaded_from : chr "/home/user/project/.tasker.yml"
#  $ loaded_at   : POSIXct[1:1], format: "2025-12-21 15:30:45"
```

---

## Testing Configuration

```r
# Test configuration discovery
test_that("find_config_file works", {
  # Create temp config
  tmpdir <- tempdir()
  config_path <- file.path(tmpdir, ".tasker.yml")
  writeLines("database:\n  host: localhost", config_path)
  
  # Should find it
  found <- find_config_file(tmpdir)
  expect_equal(found, normalizePath(config_path))
  
  # Should not find in subdirectory
  subdir <- file.path(tmpdir, "subdir")
  dir.create(subdir)
  found <- find_config_file(subdir)
  expect_equal(found, normalizePath(config_path))
  
  # Cleanup
  unlink(config_path)
  unlink(subdir, recursive = TRUE)
})

test_that("configuration precedence works", {
  # Set env var
  Sys.setenv(TASKER_DB_HOST = "env.example.com")
  
  # Create config file
  tmpfile <- tempfile(fileext = ".yml")
  writeLines("database:\n  host: file.example.com", tmpfile)
  
  # Explicit parameter should win
  config <- tasker_config(
    config_file = tmpfile,
    host = "explicit.example.com"
  )
  
  expect_equal(config$database$host, "explicit.example.com")
  
  # Cleanup
  unlink(tmpfile)
  Sys.unsetenv("TASKER_DB_HOST")
})

test_that("environment variable expansion works", {
  Sys.setenv(TEST_PASSWORD = "secret123")
  
  tmpfile <- tempfile(fileext = ".yml")
  writeLines("database:\n  password: ${TEST_PASSWORD}", tmpfile)
  
  config <- tasker_config(config_file = tmpfile)
  
  expect_equal(config$database$password, "secret123")
  
  # Cleanup
  unlink(tmpfile)
  Sys.unsetenv("TEST_PASSWORD")
})
```

---

## Dependencies

Add to DESCRIPTION:

```
Imports:
    DBI,
    yaml
Suggests:
    RPostgres,
    RSQLite,
    RMariaDB
```

---

**Status:** ✅ **Implementation Reference Complete**
