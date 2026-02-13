# tests/testthat/test-tasker_cluster_packages.R
# Unit tests for package/namespace loading in tasker_cluster()

library(testthat)
library(parallel)

# =============================================================================
# Input Validation Tests
# =============================================================================

test_that("tasker_cluster validates namespaces parameter", {
  # Valid character vector
  expect_no_error(
    tasker_cluster(ncores = 1, namespaces = c("jsonlite", "httr"))
  )
  
  # Invalid: non-character
  expect_error(
    tasker_cluster(ncores = 1, namespaces = 123),
    "'namespaces' must be a character vector"
  )
  
  # Invalid: list instead of vector
  expect_error(
    tasker_cluster(ncores = 1, namespaces = list("jsonlite")),
    "'namespaces' must be a character vector"
  )
})

test_that("tasker_cluster validates packages parameter", {
  # Valid character vector
  expect_no_error(
    tasker_cluster(ncores = 1, packages = c("dplyr", "sf"))
  )
  
  # Invalid: non-character
  expect_error(
    tasker_cluster(ncores = 1, packages = 123),
    "'packages' must be a character vector"
  )
  
  # Invalid: NULL should be allowed
  expect_no_error(
    tasker_cluster(ncores = 1, packages = NULL)
  )
})

test_that("tasker_cluster accepts both namespaces and packages", {
  # Both specified
  cl <- tasker_cluster(
    ncores = 1,
    namespaces = c("jsonlite"),
    packages = c("utils")
  )
  expect_s3_class(cl, "cluster")
  stop_tasker_cluster(cl)
  
  # Only namespaces
  cl <- tasker_cluster(ncores = 1, namespaces = c("jsonlite"))
  expect_s3_class(cl, "cluster")
  stop_tasker_cluster(cl)
  
  # Only packages
  cl <- tasker_cluster(ncores = 1, packages = c("utils"))
  expect_s3_class(cl, "cluster")
  stop_tasker_cluster(cl)
  
  # Neither (should use auto-detection)
  cl <- tasker_cluster(ncores = 1)
  expect_s3_class(cl, "cluster")
  stop_tasker_cluster(cl)
})

# =============================================================================
# Auto-Detection Tests
# =============================================================================

test_that("tasker_cluster auto-detects attached packages", {
  # Attach a package if not already attached
  if (!"glue" %in% .packages()) {
    library(glue)
    on.exit(detach("package:glue", unload = FALSE), add = TRUE)
  }
  
  cl <- tasker_cluster(ncores = 1)
  
  # Verify glue is available on worker (attached)
  result <- parallel::clusterEvalQ(cl, {
    # If glue is attached, it should be in search()
    "package:glue" %in% search()
  })
  
  expect_true(result[[1]], info = "glue should be attached on worker")
  
  stop_tasker_cluster(cl)
})

test_that("tasker_cluster auto-detects loaded namespaces", {
  # Load a namespace without attaching
  if (!"jsonlite" %in% loadedNamespaces()) {
    loadNamespace("jsonlite")
  }
  
  # Ensure it's NOT attached
  if ("package:jsonlite" %in% search()) {
    skip("jsonlite is attached, cannot test namespace-only loading")
  }
  
  cl <- tasker_cluster(ncores = 1)
  
  # Verify jsonlite namespace is loaded on worker but NOT attached
  result <- parallel::clusterEvalQ(cl, {
    list(
      loaded = "jsonlite" %in% loadedNamespaces(),
      attached = "package:jsonlite" %in% search()
    )
  })
  
  expect_true(result[[1]]$loaded, info = "jsonlite namespace should be loaded")
  expect_false(result[[1]]$attached, info = "jsonlite should NOT be attached")
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Explicit Package Loading Tests
# =============================================================================

test_that("tasker_cluster loads specified namespaces without attaching", {
  cl <- tasker_cluster(
    ncores = 1,
    namespaces = c("jsonlite")
  )
  
  # Check that jsonlite is loaded but not attached
  result <- parallel::clusterEvalQ(cl, {
    list(
      loaded = "jsonlite" %in% loadedNamespaces(),
      attached = "package:jsonlite" %in% search(),
      # Can use namespace functions
      can_use = tryCatch({
        jsonlite::fromJSON('{"a":1}')
        TRUE
      }, error = function(e) FALSE)
    )
  })
  
  expect_true(result[[1]]$loaded, info = "jsonlite should be loaded")
  expect_false(result[[1]]$attached, info = "jsonlite should NOT be attached")
  expect_true(result[[1]]$can_use, info = "jsonlite functions should be accessible")
  
  stop_tasker_cluster(cl)
})

test_that("tasker_cluster attaches specified packages", {
  cl <- tasker_cluster(
    ncores = 1,
    packages = c("glue")
  )
  
  # Check that glue is both loaded AND attached
  result <- parallel::clusterEvalQ(cl, {
    list(
      loaded = "glue" %in% loadedNamespaces(),
      attached = "package:glue" %in% search(),
      # Can use unqualified functions
      can_use_unqualified = tryCatch({
        glue("test {1+1}")
        TRUE
      }, error = function(e) FALSE)
    )
  })
  
  expect_true(result[[1]]$loaded, info = "glue should be loaded")
  expect_true(result[[1]]$attached, info = "glue should be attached")
  expect_true(result[[1]]$can_use_unqualified, 
              info = "glue functions should work without :: qualifier")
  
  stop_tasker_cluster(cl)
})

test_that("tasker_cluster handles both namespaces and packages correctly", {
  cl <- tasker_cluster(
    ncores = 1,
    namespaces = c("jsonlite"),
    packages = c("glue")
  )
  
  result <- parallel::clusterEvalQ(cl, {
    list(
      jsonlite_loaded = "jsonlite" %in% loadedNamespaces(),
      jsonlite_attached = "package:jsonlite" %in% search(),
      glue_loaded = "glue" %in% loadedNamespaces(),
      glue_attached = "package:glue" %in% search()
    )
  })
  
  # jsonlite: loaded but not attached
  expect_true(result[[1]]$jsonlite_loaded)
  expect_false(result[[1]]$jsonlite_attached)
  
  # glue: both loaded and attached
  expect_true(result[[1]]$glue_loaded)
  expect_true(result[[1]]$glue_attached)
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Merge Behavior Tests
# =============================================================================

test_that("tasker_cluster merges user-specified with auto-detected namespaces", {
  # Load a namespace
  if (!"jsonlite" %in% loadedNamespaces()) {
    loadNamespace("jsonlite")
  }
  
  # Create cluster with additional namespace
  cl <- tasker_cluster(
    ncores = 1,
    namespaces = c("httr")  # User-specified
    # jsonlite should be auto-detected
  )
  
  result <- parallel::clusterEvalQ(cl, {
    list(
      jsonlite = "jsonlite" %in% loadedNamespaces(),
      httr = "httr" %in% loadedNamespaces()
    )
  })
  
  expect_true(result[[1]]$jsonlite, info = "Auto-detected jsonlite should be loaded")
  expect_true(result[[1]]$httr, info = "User-specified httr should be loaded")
  
  stop_tasker_cluster(cl)
})

test_that("tasker_cluster merges user-specified with auto-detected packages", {
  # Attach a package
  if (!"glue" %in% .packages()) {
    library(glue)
    on.exit(detach("package:glue", unload = FALSE), add = TRUE)
  }
  
  # Create cluster with additional package (use grid which is typically not attached)
  cl <- tasker_cluster(
    ncores = 1,
    packages = c("grid")  # User-specified (not typically attached)
    # glue should be auto-detected
  )
  
  result <- parallel::clusterEvalQ(cl, {
    list(
      glue = "package:glue" %in% search(),
      grid = "package:grid" %in% search()
    )
  })
  
  expect_true(result[[1]]$glue, info = "Auto-detected glue should be attached")
  expect_true(result[[1]]$grid, info = "User-specified grid should be attached")
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Base Package Exclusion Tests
# =============================================================================

test_that("tasker_cluster excludes base packages from auto-detection", {
  # Base packages should always be available, no need to load/attach
  cl <- tasker_cluster(ncores = 1)
  
  result <- parallel::clusterEvalQ(cl, {
    # Check that base packages are available without explicit loading
    list(
      base_available = exists("list", where = "package:base"),
      utils_available = "package:utils" %in% search(),
      # We shouldn't see these in our explicit loading logic
      stats_in_namespaces = "stats" %in% loadedNamespaces()
    )
  })
  
  expect_true(result[[1]]$base_available)
  expect_true(result[[1]]$utils_available)
  expect_true(result[[1]]$stats_in_namespaces)
  
  stop_tasker_cluster(cl)
})

# =============================================================================
# Error Handling Tests
# =============================================================================

test_that("tasker_cluster handles non-existent packages gracefully", {
  # Non-existent package should cause error
  expect_error(
    {
      cl <- tasker_cluster(
        ncores = 1,
        packages = c("ThisPackageDoesNotExist12345")
      )
      stop_tasker_cluster(cl)
    },
    "there is no package|package.*not found"
  )
})

test_that("tasker_cluster handles non-existent namespaces gracefully", {
  # Non-existent namespace should cause error
  expect_error(
    {
      cl <- tasker_cluster(
        ncores = 1,
        namespaces = c("ThisNamespaceDoesNotExist12345")
      )
      stop_tasker_cluster(cl)
    },
    "there is no package|namespace.*not found"
  )
})

# =============================================================================
# Integration Tests
# =============================================================================

test_that("tasker_cluster packages work with actual parallel computation", {
  # Attach jsonlite for testing
  if (!"jsonlite" %in% .packages()) {
    library(jsonlite)
    on.exit(detach("package:jsonlite", unload = FALSE), add = TRUE)
  }
  
  cl <- tasker_cluster(ncores = 2)
  
  # Test that workers can use jsonlite functions
  test_data <- list(
    '{"name": "Alice", "age": 30}',
    '{"name": "Bob", "age": 25}'
  )
  
  results <- parallel::parLapply(cl, test_data, function(json_str) {
    parsed <- fromJSON(json_str)  # Unqualified - should work if attached
    parsed$name
  })
  
  expect_equal(results, list("Alice", "Bob"))
  
  stop_tasker_cluster(cl)
})

test_that("tasker_cluster with multiple workers loads packages correctly", {
  # Test with multiple local workers to verify package loading works with parLapply
  cl <- tasker_cluster(
    ncores = 2,
    packages = c("glue")
  )
  
  # Verify both workers have glue attached
  results <- parallel::clusterEvalQ(cl, {
    list(
      glue_attached = "package:glue" %in% search()
    )
  })
  
  expect_length(results, 2)
  expect_true(all(sapply(results, function(r) r$glue_attached)),
              info = "All workers should have glue attached")
  
  stop_tasker_cluster(cl)
})
