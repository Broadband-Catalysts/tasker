# PostgreSQL-specific test helpers
# Uses connection info from .Renviron to create temporary test schema

#' Check if PostgreSQL is available for testing
#' 
#' @return TRUE if PostgreSQL credentials are available, FALSE otherwise
postgresql_available <- function() {
  # Check for required environment variables
  Sys.getenv("BBC_DB_HOST") != "" && 
    Sys.getenv("BBC_DB_RW_USER") != "" && 
    Sys.getenv("BBC_DB_RW_PASSWORD") != ""
}

#' Setup PostgreSQL test database with temporary schema
#' 
#' Creates a temporary schema (tasker_test_RANDOM) on the PostgreSQL database
#' specified in .Renviron. Tests run in isolation and schema is dropped on exit.
#' 
#' @return List with connection and schema name
setup_postgresql_test <- function() {
  # Check if we're in an environment that can access PostgreSQL
  # (This allows tests to skip if not in the right environment)
  skip_if_no_postgresql <- function() {
    # Check for required environment variables
    if (Sys.getenv("BBC_DB_HOST") == "" || 
        Sys.getenv("BBC_DB_RW_USER") == "" || 
        Sys.getenv("BBC_DB_RW_PASSWORD") == "") {
      skip("PostgreSQL credentials not available (BBC_DB_* environment variables)")
    }
  }
  
  skip_if_no_postgresql()
  
  # Generate random schema name for isolation
  schema_name <- paste0("tasker_test_", 
                        format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
                        sample(1000:9999, 1))
  
  # Connect to PostgreSQL using environment variables
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("BBC_DB_HOST"),
    port = as.integer(Sys.getenv("BBC_DB_PORT", "5432")),
    dbname = Sys.getenv("BBC_DB_DATABASE", "geodb"),
    user = Sys.getenv("BBC_DB_RW_USER"),
    password = Sys.getenv("BBC_DB_RW_PASSWORD")
  )
  
  # Create temporary schema
  DBI::dbExecute(con, sprintf("CREATE SCHEMA %s", schema_name))
  
  # Set search path to use temporary schema
  DBI::dbExecute(con, sprintf("SET search_path TO %s, public", schema_name))
  
  # Configure tasker to use this PostgreSQL connection with temporary schema
  tasker::tasker_config(
    driver = "postgresql",
    host = Sys.getenv("BBC_DB_HOST"),
    port = as.integer(Sys.getenv("BBC_DB_PORT", "5432")),
    dbname = Sys.getenv("BBC_DB_DATABASE", "geodb"),
    user = Sys.getenv("BBC_DB_RW_USER"),
    password = Sys.getenv("BBC_DB_RW_PASSWORD"),
    schema = schema_name,
    reload = TRUE
  )
  
  # Disable auto-start of reporter
  options(tasker.process_reporter.auto_start = FALSE)
  
  # Allow skip_backup=TRUE in tests
  options(tasker.confirm_skip_backup = TRUE)
  
  # Setup tasker schema in temporary schema
  tasker::setup_tasker_db(force = TRUE, quiet = TRUE, skip_backup = TRUE)
  
  # Return connection and schema info
  return(list(
    con = con,
    schema = schema_name
  ))
}

#' Cleanup PostgreSQL test database
#' 
#' Drops the temporary test schema and disconnects
#' 
#' @param test_info List returned from setup_postgresql_test()
cleanup_postgresql_test <- function(test_info) {
  if (is.null(test_info) || !is.list(test_info)) {
    return(invisible(NULL))
  }
  
  con <- test_info$con
  schema <- test_info$schema
  
  tryCatch({
    # Drop the temporary schema
    if (!is.null(schema) && DBI::dbIsValid(con)) {
      DBI::dbExecute(con, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
    }
    
    # Disconnect
    if (!is.null(con) && DBI::dbIsValid(con)) {
      DBI::dbDisconnect(con)
    }
  }, error = function(e) {
    warning("Error during PostgreSQL test cleanup: ", e$message)
  })
  
  # Clear tasker config
  options(tasker.config = NULL)
  options(tasker.process_reporter.auto_start = NULL)
  
  invisible(NULL)
}

#' Check if PostgreSQL testing is available
#' 
#' @return TRUE if PostgreSQL credentials are set, FALSE otherwise
postgresql_available <- function() {
  Sys.getenv("BBC_DB_HOST") != "" && 
    Sys.getenv("BBC_DB_RW_USER") != "" && 
    Sys.getenv("BBC_DB_RW_PASSWORD") != ""
}
