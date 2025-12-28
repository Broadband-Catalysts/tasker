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
  tasker_config(
    driver = "sqlite",
    dbname = db_path,
    schema = "",  # SQLite doesn't use schemas
    reload = TRUE
  )
  
  # Create schema
  setup_tasker_db(force = TRUE)
  
  invisible(db_path)
}

#' Clean up test database
cleanup_test_db <- function() {
  db_path <- get_test_db_path()
  if (file.exists(db_path)) {
    unlink(db_path)
  }
  
  # Clear config
  options(tasker.config = NULL)
  
  invisible(NULL)
}

#' Get test database connection
get_test_db_connection <- function() {
  tasker:::ensure_configured()
  tasker::get_db_connection()
}
