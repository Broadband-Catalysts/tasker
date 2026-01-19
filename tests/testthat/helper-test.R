# Test helpers

# Use SQLite for testing by default
get_test_db_path <- function() {
  file.path(tempdir(), "tasker_test.db")
}

#' Setup test database with SQLite
setup_test_db <- function() {
  db_path <- get_test_db_path()
  
  # Remove existing test database
  if (file.exists(db_path)) {
    unlink(db_path)
  }
  
  # Configure tasker to use SQLite
  tasker::tasker_config(
    driver = "sqlite",
    dbname = db_path,
    schema = "",  # SQLite doesn't use schemas
    reload = TRUE
  )

  # Avoid callr background processes during unit tests
  options(tasker.process_reporter.auto_start = FALSE)
  
  # Create full schema (tables + reporter tables + views)
  tasker::setup_tasker_db(force = TRUE, quiet = TRUE)

  # Persist the path for callers that need it
  options(tasker.test_db_path = db_path)

  # Return a DBI connection for convenience (many tests expect a connection)
  tasker:::ensure_configured()
  con <- tasker::get_db_connection()
  return(con)
}

#' Clean up test database
cleanup_test_db <- function(con = NULL) {
  # Accept either a DBI connection or a path to the DB file
  if (!is.null(con)) {
    if (is.character(con)) {
      db_path <- con
      if (file.exists(db_path)) unlink(db_path)
    } else {
      # try disconnecting if it's a DBI connection
      tryCatch({
        if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
      }, error = function(e) NULL)
      # remove file from known test path as well
      db_path <- get_test_db_path()
      if (file.exists(db_path)) unlink(db_path)
    }
  } else {
    # No arg provided: remove the default test DB path
    db_path <- get_test_db_path()
    if (file.exists(db_path)) unlink(db_path)
  }
  
  # Clear config
  options(tasker.config = NULL)
  options(tasker.process_reporter.auto_start = NULL)
  
  invisible(NULL)
}

#' Get test database connection
get_test_db_connection <- function() {
  tasker:::ensure_configured()
  tasker::get_db_connection()
}
