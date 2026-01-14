test_that("get_monitor_connection creates PostgreSQL connection", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RPostgres", quietly = TRUE))
  skip_on_cran()
  skip_if_not(Sys.getenv("TEST_POSTGRES") == "true", "PostgreSQL tests not enabled")
  
  # Setup config with PostgreSQL
  config <- list(
    database = list(
      driver = "postgresql",
      host = Sys.getenv("TEST_DB_HOST", "localhost"),
      port = as.integer(Sys.getenv("TEST_DB_PORT", "5432")),
      dbname = Sys.getenv("TEST_DB_NAME", "postgres"),
      user = Sys.getenv("TEST_DB_USER", "postgres"),
      password = Sys.getenv("TEST_DB_PASSWORD", "")
    )
  )
  
  # Create connection
  con <- get_monitor_connection(config = config)
  
  expect_true(DBI::dbIsValid(con))
  expect_s4_class(con, "PqConnection")
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_monitor_connection creates MySQL connection", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RMySQL", quietly = TRUE))
  skip_on_cran()
  skip_if_not(Sys.getenv("TEST_MYSQL") == "true", "MySQL tests not enabled")
  
  # Setup config with MySQL
  config <- list(
    database = list(
      driver = "mysql",
      host = Sys.getenv("TEST_MYSQL_HOST", "localhost"),
      port = as.integer(Sys.getenv("TEST_MYSQL_PORT", "3306")),
      dbname = Sys.getenv("TEST_MYSQL_DBNAME", "test"),
      user = Sys.getenv("TEST_MYSQL_USER", "root"),
      password = Sys.getenv("TEST_MYSQL_PASSWORD", "")
    )
  )
  
  # Create connection
  con <- get_monitor_connection(config = config)
  
  expect_true(DBI::dbIsValid(con))
  expect_s4_class(con, "MySQLConnection")
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_monitor_connection reuses valid connection", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RSQLite", quietly = TRUE))
  
  # Create a test SQLite connection
  temp_db <- tempfile(fileext = ".db")
  existing_con <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  
  config <- list(
    database = list(
      driver = "sqlite",
      dbname = temp_db
    )
  )
  
  # Should return the same connection
  con <- get_monitor_connection(config = config, session_con = existing_con)
  
  expect_identical(con, existing_con)
  expect_true(DBI::dbIsValid(con))
  
  # Cleanup
  DBI::dbDisconnect(existing_con)
  unlink(temp_db)
})

test_that("get_monitor_connection creates new connection when old is invalid", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RSQLite", quietly = TRUE))
  
  # Create and disconnect a connection (making it invalid)
  temp_db <- tempfile(fileext = ".db")
  old_con <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  DBI::dbDisconnect(old_con)
  
  config <- list(
    database = list(
      driver = "sqlite",
      dbname = temp_db
    )
  )
  
  # Should create a new connection
  con <- get_monitor_connection(config = config, session_con = old_con)
  
  expect_true(DBI::dbIsValid(con))
  expect_false(identical(con, old_con))
  
  # Cleanup
  DBI::dbDisconnect(con)
  unlink(temp_db)
})

test_that("get_monitor_connection uses config from options", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RSQLite", quietly = TRUE))
  
  temp_db <- tempfile(fileext = ".db")
  
  # Set config in options
  config <- list(
    database = list(
      driver = "sqlite",
      dbname = temp_db
    )
  )
  options(tasker.config = config)
  
  # Should use config from options
  con <- get_monitor_connection()
  
  expect_true(DBI::dbIsValid(con))
  
  # Cleanup
  DBI::dbDisconnect(con)
  unlink(temp_db)
  options(tasker.config = NULL)
})

test_that("get_monitor_connection fails with missing config", {
  # Clear options
  options(tasker.config = NULL)
  
  expect_error(
    get_monitor_connection(),
    "Tasker configuration not loaded"
  )
})

test_that("get_monitor_connection fails with unsupported database type", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  
  config <- list(
    database = list(
      driver = "oracle",  # Unsupported
      host = "localhost"
    )
  )
  
  expect_error(
    get_monitor_connection(config = config),
    "Unsupported database type: oracle"
  )
})

test_that("get_monitor_connection fails when required package missing", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  
  config <- list(
    database = list(
      driver = "postgresql",
      host = "localhost",
      port = 5432,
      dbname = "test"
    )
  )
  
  # Mock missing package
  mockery::stub(
    get_monitor_connection,
    "requireNamespace",
    FALSE
  )
  
  expect_error(
    get_monitor_connection(config = config),
    "RPostgres package required for PostgreSQL"
  )
})

test_that("get_database_queries works with PostgreSQL", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RPostgres", quietly = TRUE))
  skip_on_cran()
  skip_if_not(Sys.getenv("TEST_POSTGRES") == "true", "PostgreSQL tests not enabled")
  
  # Setup config
  config <- list(
    database = list(
      driver = "postgresql",
      host = Sys.getenv("TEST_DB_HOST", "localhost"),
      port = as.integer(Sys.getenv("TEST_DB_PORT", "5432")),
      dbname = Sys.getenv("TEST_DB_NAME", "postgres"),
      user = Sys.getenv("TEST_DB_USER", "postgres"),
      password = Sys.getenv("TEST_DB_PASSWORD", "")
    )
  )
  
  con <- get_monitor_connection(config = config)
  
  # Get queries
  queries <- get_database_queries(con, "postgresql")
  
  expect_s3_class(queries, "data.frame")
  expect_true("pid" %in% names(queries))
  expect_true("username" %in% names(queries))
  expect_true("query" %in% names(queries))
  expect_true("state" %in% names(queries))
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_database_queries works with MySQL", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RMySQL", quietly = TRUE))
  skip_on_cran()
  skip_if_not(Sys.getenv("TEST_MYSQL") == "true", "MySQL tests not enabled")
  
  # Setup config
  config <- list(
    database = list(
      driver = "mysql",
      host = Sys.getenv("TEST_MYSQL_HOST", "localhost"),
      port = as.integer(Sys.getenv("TEST_MYSQL_PORT", "3306")),
      dbname = Sys.getenv("TEST_MYSQL_DBNAME", "test"),
      user = Sys.getenv("TEST_MYSQL_USER", "root"),
      password = Sys.getenv("TEST_MYSQL_PASSWORD", "")
    )
  )
  
  con <- get_monitor_connection(config = config)
  
  # Get queries
  queries <- get_database_queries(con, "mysql")
  
  expect_s3_class(queries, "data.frame")
  # MySQL returns different column names
  expect_true(length(names(queries)) > 0)
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_database_queries uses config from options for db_type", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RSQLite", quietly = TRUE))
  
  # This test verifies the db_type detection from config
  # We'll use SQLite connection and set config driver to sqlite
  temp_db <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  
  config <- list(
    database = list(
      driver = "sqlite"
    )
  )
  options(tasker.config = config)
  
  # Should detect sqlite from config and return empty data frame
  result <- get_database_queries(con)
  
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  
  # Cleanup
  DBI::dbDisconnect(con)
  unlink(temp_db)
  options(tasker.config = NULL)
})

test_that("get_database_queries fails with unsupported database type", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RSQLite", quietly = TRUE))
  
  temp_db <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  
  expect_error(
    get_database_queries(con, "oracle"),
    "Unsupported database type: oracle"
  )
  
  # Cleanup
  DBI::dbDisconnect(con)
  unlink(temp_db)
})

test_that("get_database_queries returns data frame", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RSQLite", quietly = TRUE))
  
  # Create a SQLite connection and test with sqlite db_type
  temp_db <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  
  # SQLite returns empty data frame
  result <- get_database_queries(con, "sqlite")
  
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true(all(c("pid", "duration", "username", "query", "state") %in% names(result)))
  
  # Cleanup
  DBI::dbDisconnect(con)
  unlink(temp_db)
})

test_that("database monitoring functions work together", {
  skip_if_not(requireNamespace("DBI", quietly = TRUE))
  skip_if_not(requireNamespace("RSQLite", quietly = TRUE))
  
  # Integration test using SQLite
  temp_db <- tempfile(fileext = ".db")
  
  config <- list(
    database = list(
      driver = "sqlite",
      dbname = temp_db
    )
  )
  
  # Test connection lifecycle
  con1 <- get_monitor_connection(config = config)
  expect_true(DBI::dbIsValid(con1))
  
  # Reuse connection
  con2 <- get_monitor_connection(config = config, session_con = con1)
  expect_identical(con1, con2)
  
  # Close and recreate
  DBI::dbDisconnect(con1)
  expect_false(DBI::dbIsValid(con1))
  
  con3 <- get_monitor_connection(config = config, session_con = con1)
  expect_true(DBI::dbIsValid(con3))
  expect_false(identical(con1, con3))
  
  # Cleanup
  DBI::dbDisconnect(con3)
  unlink(temp_db)
})
