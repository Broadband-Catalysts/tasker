library(testthat)

test_that("critical schema columns exist", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")

  con <- setup_test_db()
  on.exit(cleanup_test_db(con), add = TRUE)

  # Helper to get column names for SQLite (works for tests which use SQLite)
  cols <- function(table) {
    info <- DBI::dbGetQuery(con, sprintf("PRAGMA table_info('%s')", table))
    tolower(info$name)
  }

  # stages
  st_cols <- cols('stages')
  expect_true('updated_at' %in% st_cols)

  # tasks
  task_cols <- cols('tasks')
  expect_true(all(c('created_at', 'updated_at', 'task_name') %in% task_cols))

  # task_runs
  tr_cols <- cols('task_runs')
  expect_true(all(c('start_time', 'end_time', 'last_update', 'status') %in% tr_cols))

  # subtask_progress
  sp_cols <- cols('subtask_progress')
  expect_true(all(c('start_time', 'end_time', 'last_update', 'items_total') %in% sp_cols))

  # process_metrics
  pm_cols <- cols('process_metrics')
  expect_true(all(c('metric_id', 'cpu_percent', 'memory_mb', 'timestamp') %in% pm_cols))
})
