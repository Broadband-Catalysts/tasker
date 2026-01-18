test_that("get_monitor_connection validates config", {
  # Test error when config is NULL and no option set
  withr::local_options(list(tasker.config = NULL))
  expect_error(
    get_monitor_connection(config = NULL, session_con = NULL),
    "Tasker configuration not loaded"
  )
})

test_that("get_monitor_connection reuses valid connections", {
  # Create a mock config
  mock_config <- list(
    database = list(
      driver = "sqlite",
      dbname = ":memory:"
    )
  )
  
  # Create a connection
  con1 <- get_monitor_connection(config = mock_config, session_con = NULL)
  expect_true(DBI::dbIsValid(con1))
  
  # Should reuse the same connection if valid
  con2 <- get_monitor_connection(config = mock_config, session_con = con1)
  expect_identical(con1, con2)
  
  # Cleanup
  DBI::dbDisconnect(con1)
})

test_that("get_monitor_connection creates SQLite connection", {
  mock_config <- list(
    database = list(
      driver = "sqlite",
      dbname = ":memory:"
    )
  )
  
  con <- get_monitor_connection(config = mock_config)
  expect_s4_class(con, "SQLiteConnection")
  expect_true(DBI::dbIsValid(con))
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_monitor_connection handles unsupported database types", {
  mock_config <- list(
    database = list(
      driver = "unsupported_db",
      dbname = "test"
    )
  )
  
  expect_error(
    get_monitor_connection(config = mock_config),
    "Unsupported database type: unsupported_db"
  )
})

test_that("get_monitor_connection requires RPostgres for PostgreSQL", {
  skip_if_not_installed("mockery")
  
  mock_config <- list(
    database = list(
      driver = "postgresql",
      host = "localhost",
      port = 5432,
      dbname = "test",
      user = "test",
      password = "test"
    )
  )
  
  # Mock requireNamespace to return FALSE
  mockery::stub(
    get_monitor_connection,
    "requireNamespace",
    FALSE
  )
  
  expect_error(
    get_monitor_connection(config = mock_config),
    "RPostgres package required for PostgreSQL"
  )
})

test_that("get_monitor_connection requires RMariaDB for MySQL", {
  skip_if_not_installed("mockery")
  
  mock_config <- list(
    database = list(
      driver = "mysql",
      host = "localhost",
      port = 3306,
      dbname = "test",
      user = "test",
      password = "test"
    )
  )
  
  # Mock requireNamespace to return FALSE
  mockery::stub(
    get_monitor_connection,
    "requireNamespace",
    FALSE
  )
  
  expect_error(
    get_monitor_connection(config = mock_config),
    "RMariaDB package required for MySQL"
  )
})

test_that("get_monitor_connection requires RSQLite for SQLite", {
  skip_if_not_installed("mockery")
  
  mock_config <- list(
    database = list(
      driver = "sqlite",
      dbname = ":memory:"
    )
  )
  
  # Mock requireNamespace to return FALSE
  mockery::stub(
    get_monitor_connection,
    "requireNamespace",
    FALSE
  )
  
  expect_error(
    get_monitor_connection(config = mock_config),
    "RSQLite package required for SQLite"
  )
})

test_that("get_database_queries returns empty data frame for SQLite", {
  mock_config <- list(
    database = list(
      driver = "sqlite",
      dbname = ":memory:"
    )
  )
  
  con <- get_monitor_connection(config = mock_config)
  
  result <- get_database_queries(con, db_type = "sqlite")
  
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true(all(c("pid", "duration", "username", "query", "state") %in% names(result)))
  # Duration should be numeric type (for interval objects)
  expect_type(result$duration, "double")
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_database_queries respects status parameter", {
  mock_config <- list(
    database = list(
      driver = "sqlite",
      dbname = ":memory:"
    )
  )
  
  con <- get_monitor_connection(config = mock_config)
  
  # Test with default "active" status
  result_active <- get_database_queries(con, status = "active", db_type = "sqlite")
  expect_s3_class(result_active, "data.frame")
  
  # Test with "any" status
  result_any <- get_database_queries(con, status = "any", db_type = "sqlite")
  expect_s3_class(result_any, "data.frame")
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_database_queries handles unsupported database types", {
  # Create a mock connection (SQLite for simplicity)
  mock_config <- list(
    database = list(
      driver = "sqlite",
      dbname = ":memory:"
    )
  )
  con <- get_monitor_connection(config = mock_config)
  
  expect_error(
    get_database_queries(con, db_type = "unsupported_db"),
    "Unsupported database type: unsupported_db"
  )
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_database_queries uses config when db_type is NULL", {
  mock_config <- list(
    database = list(
      driver = "sqlite",
      dbname = ":memory:"
    )
  )
  
  # Set global option
  options(tasker.config = mock_config)
  on.exit(options(tasker.config = NULL), add = TRUE)
  
  con <- get_monitor_connection(config = mock_config)
  
  # Should use driver from config (SQLite returns empty data frame)
  result <- get_database_queries(con, db_type = NULL)
  
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true(all(c("pid", "duration", "username", "query", "state") %in% names(result)))
  
  # Cleanup
  DBI::dbDisconnect(con)
})

test_that("get_database_queries PostgreSQL query structure", {
  skip("Requires PostgreSQL database connection")
  
  # This test would need a real PostgreSQL connection
  # It's skipped by default but can be run in CI/CD with proper setup
  
  mock_config <- list(
    database = list(
      driver = "postgresql",
      host = Sys.getenv("TEST_PG_HOST", "localhost"),
      port = as.integer(Sys.getenv("TEST_PG_PORT", "5432")),
      dbname = Sys.getenv("TEST_PG_DBNAME", "test"),
      user = Sys.getenv("TEST_PG_USER", "test"),
      password = Sys.getenv("TEST_PG_PASSWORD", "test")
    )
  )
  
  con <- get_monitor_connection(config = mock_config)
  result <- get_database_queries(con, db_type = "postgresql")
  
  # Check expected columns
  expected_cols <- c("pid", "duration", "username", "query", "state")
  expect_true(all(expected_cols %in% names(result)))
  
  DBI::dbDisconnect(con)
})

test_that("get_database_queries MySQL query structure", {
  skip("Requires MySQL database connection")
  
  # This test would need a real MySQL connection
  # It's skipped by default but can be run in CI/CD with proper setup
  
  mock_config <- list(
    database = list(
      driver = "mysql",
      host = Sys.getenv("TEST_MYSQL_HOST", "localhost"),
      port = as.integer(Sys.getenv("TEST_MYSQL_PORT", "3306")),
      dbname = Sys.getenv("TEST_MYSQL_DBNAME", "test"),
      user = Sys.getenv("TEST_MYSQL_USER", "test"),
      password = Sys.getenv("TEST_MYSQL_PASSWORD", "test")
    )
  )
  
  con <- get_monitor_connection(config = mock_config)
  result <- get_database_queries(con, db_type = "mysql")
  
  # Check that result is a data frame
  expect_s3_class(result, "data.frame")
  
  DBI::dbDisconnect(con)
})
