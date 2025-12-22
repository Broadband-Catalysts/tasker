# Test helpers

#' Check if test database is available
check_test_db_available <- function() {
  # Check for test database environment variables
  has_config <- !is.null(Sys.getenv("TASKER_TEST_DB_HOST", unset = NA)) &&
                !is.null(Sys.getenv("TASKER_TEST_DB_NAME", unset = NA))
  
  if (!has_config) {
    return(FALSE)
  }
  
  # Try to connect
  tryCatch({
    conn <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("TASKER_TEST_DB_HOST"),
      dbname = Sys.getenv("TASKER_TEST_DB_NAME"),
      user = Sys.getenv("TASKER_TEST_DB_USER", Sys.getenv("USER")),
      password = Sys.getenv("TASKER_TEST_DB_PASSWORD", "")
    )
    DBI::dbDisconnect(conn)
    return(TRUE)
  }, error = function(e) {
    return(FALSE)
  })
}

#' Get test database connection
get_test_db_connection <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("TASKER_TEST_DB_HOST"),
    dbname = Sys.getenv("TASKER_TEST_DB_NAME"),
    user = Sys.getenv("TASKER_TEST_DB_USER", Sys.getenv("USER")),
    password = Sys.getenv("TASKER_TEST_DB_PASSWORD", "")
  )
}

#' Setup test database schema
setup_test_db <- function() {
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  # Clean up existing test schema
  DBI::dbExecute(conn, "DROP SCHEMA IF EXISTS tasker CASCADE")
  
  # Create new schema
  setup_tasker_db(conn)
}

#' Clean up test database
cleanup_test_db <- function() {
  if (!check_test_db_available()) {
    return(invisible(NULL))
  }
  
  conn <- get_test_db_connection()
  on.exit(DBI::dbDisconnect(conn))
  
  # Drop test schema
  DBI::dbExecute(conn, "DROP SCHEMA IF EXISTS tasker CASCADE")
}
