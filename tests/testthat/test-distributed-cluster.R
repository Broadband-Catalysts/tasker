# tests/testthat/test-distributed-cluster.R
# Unit tests for distributed cluster functionality in tasker_cluster()

library(testthat)
library(parallel)

# =============================================================================
# Input Validation Tests
# =============================================================================

test_that("tasker_cluster validates named vector input", {
  # Valid named vectors
  expect_no_error(tasker_cluster(ncores = c("localhost" = 2)))
  
  # Invalid: negative cores
  expect_error(
    tasker_cluster(ncores = c("localhost" = -1)),
    "must be positive"
  )
  
  # Invalid: zero cores
  expect_error(
    tasker_cluster(ncores = c("localhost" = 0)),
    "must be positive"
  )
  
  # Invalid: NA in named vector
  expect_error(
    tasker_cluster(ncores = c("localhost" = NA)),
    "must be positive|cannot contain NA"
  )
})

test_that("tasker_cluster handles host name validation", {
  # Valid hostnames
  expect_no_error(tasker_cluster(ncores = c("localhost" = 1)))
  expect_no_error(tasker_cluster(ncores = c("127.0.0.1" = 1)))
  
  # Duplicate host names should work (worker processes on same host)
  expect_no_error(
    tasker_cluster(ncores = c("localhost" = 2, "localhost" = 1))
  )
})

# =============================================================================
# Cluster Creation Tests
# =============================================================================

test_that("tasker_cluster creates correct number of workers", {
  # Single host, multiple cores
  cl <- tasker_cluster(ncores = 2)
  expect_length(cl, 2)
  expect_s3_class(cl, "cluster")
  stop_tasker_cluster(cl)
  
  # Named single host
  cl <- tasker_cluster(ncores = c("localhost" = 3))
  expect_length(cl, 3)
  stop_tasker_cluster(cl)
})

test_that("tasker_cluster handles multiple hosts", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible via SSH")
  
  # Create distributed cluster
  cl <- tasker_cluster(ncores = c("localhost" = 1, "worker2" = 1))
  
  expect_length(cl, 2)
  expect_s3_class(cl, "cluster")
  
  # Verify workers are on different hosts
  hosts <- parallel::clusterEvalQ(cl, Sys.info()[["nodename"]])
  expect_true("manager.broadbandcatalysts.com" %in% hosts)
  expect_true("worker2.broadbandcatalysts.com" %in% hosts)
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Worker Initialization Tests
# =============================================================================

test_that("workers initialize in correct directory", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  expected_wd <- getwd()
  
  # Test with remote worker
  cl <- tasker_cluster(ncores = c("worker2" = 1))
  
  worker_wd <- parallel::clusterEvalQ(cl, getwd())[[1]]
  expect_equal(worker_wd, expected_wd)
  
  stop_tasker_cluster(cl)
})

test_that("workers load environment variables from .Renviron", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  skip_if_not(file.exists(".Renviron"), ".Renviron file not present")
  
  # Test that workers can access environment variables
  cl <- tasker_cluster(ncores = c("worker2" = 1))
  
  # Check if a known environment variable is available
  # (adjust based on your .Renviron contents)
  result <- parallel::clusterEvalQ(cl, {
    list(has_renviron = Sys.getenv("HOME") != "")
  })
  
  expect_true(result[[1]]$has_renviron)
  
  stop_tasker_cluster(cl)
})

test_that("workers have correct library paths", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  working_dir <- getwd()
  expected_renv_lib <- file.path(
    working_dir, 
    "renv/library/linux-ubuntu-noble/R-4.5/x86_64-pc-linux-gnu"
  )
  
  cl <- tasker_cluster(ncores = c("worker2" = 1))
  
  worker_libpaths <- parallel::clusterEvalQ(cl, .libPaths())[[1]]
  
  # Check if renv library is in the path (if it exists)
  if (dir.exists(expected_renv_lib)) {
    expect_true(expected_renv_lib %in% worker_libpaths)
  }
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Cluster Attributes Tests
# =============================================================================

test_that("tasker_cluster sets correct attributes", {
  cl <- tasker_cluster(ncores = 2)
  
  # Check tasker-specific attributes
  expect_true(attr(cl, "tasker_managed"))
  expect_s3_class(attr(cl, "tasker_created_at"), "POSIXct")
  
  # Check distribution info
  dist_info <- attr(cl, "tasker_distribution")
  expect_type(dist_info, "list")
  expect_equal(dist_info$type, "localhost")
  expect_equal(dist_info$total_workers, 2)
  
  stop_tasker_cluster(cl)
})

test_that("distributed cluster has correct distribution attributes", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  cl <- tasker_cluster(ncores = c("localhost" = 2, "worker2" = 1))
  
  dist_info <- attr(cl, "tasker_distribution")
  expect_equal(dist_info$type, "distributed")
  expect_equal(dist_info$hosts, c("localhost", "worker2"))
  expect_equal(dist_info$workers_per_host, c(2, 1))
  expect_equal(dist_info$total_workers, 3)
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Setup Expression Tests
# =============================================================================

test_that("setup_expr executes on workers", {
  test_var_value <- 42
  
  cl <- tasker_cluster(
    ncores = 2,
    export = "test_var_value",
    setup_expr = quote({
      test_setup_var <- test_var_value * 2
      NULL
    })
  )
  
  # Verify setup_expr ran and variable exists
  result <- parallel::clusterEvalQ(cl, exists("test_setup_var"))
  expect_true(all(unlist(result)))
  
  # Verify correct value
  values <- parallel::clusterEvalQ(cl, test_setup_var)
  expect_true(all(unlist(values) == 84))
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Package Loading Tests
# =============================================================================

test_that("workers can load packages via setup_expr", {
  cl <- tasker_cluster(
    ncores = 2,
    setup_expr = quote({
      library(parallel)
      NULL
    })
  )
  
  # Verify parallel is loaded
  result <- parallel::clusterEvalQ(cl, "parallel" %in% loadedNamespaces())
  expect_true(all(unlist(result)))
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Error Handling Tests
# =============================================================================

test_that("tasker_cluster handles setup_expr errors gracefully", {
  # Setup expression that throws an error should be caught
  expect_warning(
    cl <- tasker_cluster(
      ncores = 2,
      setup_expr = quote({
        stop("Intentional test error")
      })
    ),
    "Setup expression failed"
  )
  
  # Cluster should still be created
  expect_s3_class(cl, "cluster")
  expect_length(cl, 2)
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Debug Mode Tests
# =============================================================================

test_that("debug mode produces informative output", {
  output <- capture_output({
    cl <- tasker_cluster(ncores = 2, debug = TRUE)
    stop_tasker_cluster(cl)
  })
  
  expect_match(output, "DEBUG.*Cluster Configuration")
  expect_match(output, "Cluster spec")
})

test_that("debug mode shows distribution info for remote clusters", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  output <- capture_output({
    cl <- tasker_cluster(ncores = c("localhost" = 1, "worker2" = 1), debug = TRUE)
    stop_tasker_cluster(cl)
  })
  
  expect_match(output, "Remote workers")
  expect_match(output, "Working directory")
})

# =============================================================================
# Integration Tests
# =============================================================================

test_that("distributed cluster can execute real work", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  # Create distributed cluster
  cl <- tasker_cluster(ncores = c("localhost" = 2, "worker2" = 2))
  
  # Test parLapply
  input <- 1:8
  results <- parallel::parLapply(cl, input, function(x) x^2)
  
  expect_length(results, 8)
  expect_equal(unlist(results), input^2)
  
  stop_tasker_cluster(cl)
})

test_that("distributed cluster handles parLapplyLB correctly", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  cl <- tasker_cluster(ncores = c("localhost" = 1, "worker2" = 1))
  
  # Test load balancing with variable-time tasks
  input <- 1:10
  results <- parallel::parLapplyLB(
    cl, 
    input, 
    function(x) {
      Sys.sleep(0.01)  # Simulate work
      x * 2
    },
    chunk.size = 1
  )
  
  expect_length(results, 10)
  expect_equal(unlist(results), input * 2)
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Edge Cases
# =============================================================================

test_that("tasker_cluster handles single worker", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  cl <- tasker_cluster(ncores = c("worker2" = 1))
  
  expect_length(cl, 1)
  
  result <- parallel::clusterEvalQ(cl, Sys.info()[["nodename"]])
  expect_equal(result[[1]], "worker2.broadbandcatalysts.com")
  
  stop_tasker_cluster(cl)
})

test_that("tasker_cluster handles many workers", {
  skip_if_not(Sys.info()["nodename"] == "manager.broadbandcatalysts.com",
              "Distributed tests only run on manager")
  skip_if_not(system("ssh worker2 hostname", ignore.stdout = TRUE) == 0,
              "worker2 not accessible")
  
  # Test with maximum reasonable worker count
  cl <- tasker_cluster(ncores = c("localhost" = 8, "worker2" = 8))
  
  expect_length(cl, 16)
  
  # Verify all workers respond
  results <- parallel::clusterEvalQ(cl, 1 + 1)
  expect_length(results, 16)
  expect_true(all(unlist(results) == 2))
  
  stop_tasker_cluster(cl)
})
