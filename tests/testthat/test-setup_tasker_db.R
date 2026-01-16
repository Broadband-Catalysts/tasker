library(testthat)

test_that("setup_tasker_db creates SQLite schema", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")

  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)

  expect_true(DBI::dbExistsTable(con, "stages"))
  expect_true(DBI::dbExistsTable(con, "tasks"))
  expect_true(DBI::dbExistsTable(con, "task_runs"))
  expect_true(DBI::dbExistsTable(con, "subtask_progress"))

  expect_true(DBI::dbExistsTable(con, "process_metrics"))
  expect_true(DBI::dbExistsTable(con, "process_reporter_status"))
  expect_true(DBI::dbExistsTable(con, "process_metrics_retention"))

  # Views
  expect_true(DBI::dbExistsTable(con, "current_task_status"))
  expect_true(DBI::dbExistsTable(con, "active_tasks"))
  expect_true(DBI::dbExistsTable(con, "current_task_status_with_metrics"))
  expect_true(DBI::dbExistsTable(con, "task_runs_with_latest_metrics"))
})

test_that("setup_tasker_db(force=TRUE) drops existing SQLite data", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")

  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO stages (stage_name, description) VALUES ('TO_BE_DROPPED', 'x')")
  n_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages")$n
  expect_equal(n_before, 1)

  expect_warning(tasker::setup_tasker_db(force = TRUE), "Dropping existing SQLite")

  n_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages")$n
  expect_equal(n_after, 0)
})

test_that("setup_tasker_db rolls back on schema SQL failure (SQLite)", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")

  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO stages (stage_name, description) VALUES ('FAIL_TEST', 'should remain')")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages WHERE stage_name = 'FAIL_TEST'")$n, 1)

  broken_sql <- tempfile(fileext = ".sql")
  writeLines(
    c(
      "-- Intentional failure",
      "CREATE TABLE IF NOT EXISTS will_not_matter (id INTEGER);",
      "CREATE VIEW broken_view AS SELECT * FROM definitely_missing_table;"
    ),
    broken_sql
  )

  expect_error(
    tasker::setup_tasker_db(conn = con, force = FALSE, schema_sql_file = broken_sql),
    "definitely_missing_table|no such table|Failed",
    ignore.case = TRUE
  )

  # Existing data should still be present
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages WHERE stage_name = 'FAIL_TEST'")$n, 1)
})

test_that("setup_tasker_db(force=TRUE) rolls back destructive changes on failure (SQLite)", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")

  db_path <- setup_test_db()
  con <- get_test_db_connection()
  on.exit(cleanup_test_db(con), add = TRUE)

  DBI::dbExecute(con, "INSERT INTO stages (stage_name, description) VALUES ('SURVIVE_FORCE_FAIL', 'should remain')")
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages WHERE stage_name = 'SURVIVE_FORCE_FAIL'")$n, 1)

  broken_sql <- tempfile(fileext = ".sql")
  writeLines(
    c(
      "-- Intentional failure after a DDL statement",
      "CREATE TABLE IF NOT EXISTS will_not_matter2 (id INTEGER);",
      "CREATE VIEW broken_view2 AS SELECT * FROM definitely_missing_table2;"
    ),
    broken_sql
  )

  expect_error(
    tasker::setup_tasker_db(conn = con, force = TRUE, schema_sql_file = broken_sql),
    "definitely_missing_table2|no such table|Failed",
    ignore.case = TRUE
  )

  # Because the SQLite path is transactional, the force-drop should be rolled back.
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM stages WHERE stage_name = 'SURVIVE_FORCE_FAIL'")$n, 1)
})
