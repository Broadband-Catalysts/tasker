test_that("config loading works", {
  # Test that we can set and get config
  skip_if_not(requireNamespace("yaml", quietly = TRUE))
  
  # Create temp config file
  temp_dir <- tempdir()
  config_file <- file.path(temp_dir, ".tasker.yml")
  
  config_content <- list(
    database = list(
      host = "testhost",
      port = 5432,
      dbname = "testdb",
      schema = "tasker"
    )
  )
  
  yaml::write_yaml(config_content, config_file)
  
  # Load config
  tasker_config(config_file = config_file)
  
  # Check that options are set
  expect_true(!is.null(getOption("tasker.config")))
  cfg <- getOption("tasker.config")
  expect_equal(cfg$database$host, "testhost")
  expect_equal(cfg$database$dbname, "testdb")
  
  # Cleanup
  unlink(config_file)
  options(tasker.config = NULL)
})

test_that("config can be overridden", {
  # Set initial config
  tasker_config(
    host = "host1",
    dbname = "db1"
  )
  
  cfg <- getOption("tasker.config")
  expect_equal(cfg$database$host, "host1")
  
  # Override with all required params
  tasker_config(host = "host2", dbname = "db1", reload = TRUE)
  
  cfg <- getOption("tasker.config")
  expect_equal(cfg$database$host, "host2")
  expect_equal(cfg$database$dbname, "db1")
  
  options(tasker.config = NULL)
})

test_that("find_config_file searches parent directories", {
  # Create nested directory structure
  temp_dir <- tempdir()
  nested_dir <- file.path(temp_dir, "level1", "level2", "level3")
  dir.create(nested_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Put config file at level1
  config_file <- file.path(temp_dir, "level1", ".tasker.yml")
  writeLines("database:\n  host: test", config_file)
  
  # Search from level3
  found <- find_config_file(start_dir = nested_dir)
  
  expect_equal(found, config_file)
  
  # Cleanup
  unlink(file.path(temp_dir, "level1"), recursive = TRUE)
})
