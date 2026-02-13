#' Initialize parallel cluster with tasker configuration
#'
#' This function simplifies setting up parallel processing with tasker by
#' automatically handling package loading, object export, and context initialization
#' on all workers. It encapsulates the common pattern of cluster setup, reducing
#' boilerplate from 8-10 lines to 1-2 lines.
#'
#' All packages currently loaded in the main session are automatically replicated
#' on workers, preserving the distinction between loaded namespaces (loaded via
#' \code{loadNamespace()}) and attached packages (loaded via \code{library()}).
#' This ensures workers have the same package environment as the main session.
#'
#' @param ncores Number of cores or named numeric vector for distributed processing.
#'   Can be:
#'   - A single number: creates workers on localhost (e.g., 16)
#'   - A named numeric vector: distributes workers across hosts 
#'     (e.g., c("manager"=16, "worker2"=16))
#'   - NULL (default): auto-detect as c("localhost"=max(detectCores() - 2, 32))
#'   
#'   For remote hosts:
#'   - SSH access must be configured (passwordless SSH keys recommended)
#'   - Rscript must be in the PATH on remote hosts
#'   - The project directory must exist at the same path on all hosts
#'     (e.g., via NFS mount or synchronized git repositories)
#'   - Workers will automatically start in the same working directory as the
#'     master process and hence will use the .Renviron and .Rprofile files (enabling renv activation)
#' @param namespaces Character vector of package names to load on workers using
#'   \code{loadNamespace()} (optional). These packages will be loaded but not
#'   attached to the search path. Additionally, all namespaces currently loaded
#'   in the main session are automatically loaded on workers.
#' @param packages Character vector of package names to attach on workers using
#'   \code{library()} (optional). These packages will be attached to the worker's
#'   search path. Additionally, all packages currently attached in the main
#'   session are automatically attached on workers.
#' @param export Character vector of object names to export to workers (optional).
#'   The active run_id is always exported automatically if one exists.
#' @param setup_expr Expression to evaluate on each worker after packages are loaded
#'   (e.g., for creating database connections). The expression should return NULL
#'   or a serializable value to avoid serialization errors. (optional)
#' @param envir Environment to export objects from (default: parent.frame())
#' @param load_all If TRUE, call devtools::load_all() on workers (default: FALSE)
#' @param debug If TRUE, display debugging information including command strings (default: FALSE)
#' @return Cluster object from parallel::makeCluster()
#'
#' @seealso [export_tasker_context()] to add context to existing clusters,
#'   [stop_tasker_cluster()] to properly shut down clusters,
#'   [subtask_increment()] for atomic progress updates in parallel workers
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Simple setup with auto-detection
#' # All currently loaded/attached packages replicated on workers
#' library(dplyr)
#' library(sf)
#' cl <- tasker_cluster()
#' results <- parLapply(cl, items, worker_function)
#' stop_tasker_cluster(cl)
#'
#' # With custom namespaces and packages
#' cl <- tasker_cluster(
#'   ncores = 16,
#'   namespaces = c("jsonlite", "httr"),  # Loaded but not attached
#'   packages = c("dplyr", "sf"),         # Attached to search path
#'   export = c("counties", "data_path")
#' )
#'
#' # With database connections
#' cl <- tasker_cluster(
#'   ncores = 8,
#'   setup_expr = quote({
#'     devtools::load_all()
#'     con <- dbConnectBBC(mode = "rw")
#'     NULL  # Important: return NULL to avoid serialization error
#'   })
#' )
#'
#' # Distributed processing across multiple hosts
#' cl <- tasker_cluster(
#'   ncores = c("manager" = 16, "worker2" = 16),
#'   export = c("data_path"),
#'   setup_expr = quote({
#'     devtools::load_all()
#'     con <- dbConnectBBC(mode = "rw")
#'     NULL
#'   })
#' )
#'
#' # Full example with context
#' task_start("PROCESS", "County Analysis")
#' subtask_start("Process counties", items_total = 3143)
#'
#' cl <- tasker_cluster(ncores = 16, export = "counties")
#' results <- parLapplyLB(cl, counties, function(county_fips) {
#'   result <- process_county(county_fips)
#'   subtask_increment(increment = 1, quiet = TRUE)
#'   return(result)
#' })
#' stop_tasker_cluster(cl)
#'
#' subtask_complete()
#' task_complete()
#' }
tasker_cluster <- function(ncores     = NULL,
                           namespaces = NULL,
                           packages   = NULL,
                           export     = NULL,
                           setup_expr = NULL,
                           envir      = parent.frame(),
                           load_all   = FALSE,
                           debug      = FALSE) {
  
  # Input validation
  if (!is.null(ncores)) {
    if (!is.numeric(ncores)) {
      stop("'ncores' must be a positive integer or named numeric vector", call. = FALSE)
    }
    
    # Check for valid values
    if (any(ncores < 1)) {
      stop("All ncores values must be positive integers", call. = FALSE)
    }
    
    # Preserve names before converting to integer
    ncores_names <- names(ncores)
    
    # If single value, ensure it's unnamed
    if (length(ncores) == 1 && !is.null(ncores_names)) {
      # Convert single named value to named vector format
      # e.g., c("host"=8) stays as is
      ncores <- as.integer(ncores)
      names(ncores) <- ncores_names
    } else if (length(ncores) == 1) {
      # Single unnamed value - will use localhost
      ncores <- as.integer(ncores)
    } else {
      # Multiple values - must be named
      if (is.null(ncores_names) || any(ncores_names == "")) {
        stop("Multiple ncores values must be named with hostnames", call. = FALSE)
      }
      ncores <- as.integer(ncores)
      names(ncores) <- ncores_names  # Restore names after conversion
    }
  }
  
  if (!is.null(namespaces) && !is.character(namespaces)) {
      stop("'namespaces' must be a character vector of package names", call. = FALSE)
  }
  
  if (!is.null(packages) && !is.character(packages)) {
      stop("'packages' must be a character vector of package names", call. = FALSE)
  }
  
  if (!is.null(export) && !is.character(export)) {
      stop("'export' must be a character vector of object names", call. = FALSE)
  }
  
  if (!is.logical(load_all) || length(load_all) != 1) {
    stop("'load_all' must be TRUE or FALSE", call. = FALSE)
  }
  
  if (!is.logical(debug) || length(debug) != 1) {
    stop("'debug' must be TRUE or FALSE", call. = FALSE)
  }
  
  # Auto-detect number of cores
  if (is.null(ncores)) {
    detected <- parallel::detectCores() - 2
    detected <- max(1, min(detected, 32))  # At least 1, max 32 by default
    ncores <- c("localhost" = detected)
    names(ncores) <- "localhost"
  }

  # Detect currently loaded and attached packages
  # loadedNamespaces() returns all loaded namespaces (attached or not)
  # search() returns attached packages with "package:" prefix
  loaded_namespaces <- loadedNamespaces()
  
  # Extract attached package names from search() which returns entries like "package:dplyr"
  search_results <- search()
  attached_packages <- gsub("^package:", "", search_results[grepl("^package:", search_results)])
  
  # Packages that are loaded but NOT attached (use loadNamespace)
  namespaces_only <- setdiff(loaded_namespaces, attached_packages)
  
  # Merge user-specified packages with auto-detected ones
  if (!is.null(namespaces)) {
    # User-specified namespaces to load (not attach)
    namespaces_only <- unique(c(namespaces, namespaces_only))
  }
  
  if (!is.null(packages)) {
    # User-specified packages to attach (use library)
    attached_packages <- unique(c(packages, attached_packages))
  }
  
  # Remove base packages from both lists (they're always available)
  base_packages <- c("base", "tools", "utils", "grDevices", "graphics", 
                     "stats", "datasets", "methods", "parallel")
  namespaces_only <- setdiff(namespaces_only, base_packages)
  attached_packages <- setdiff(attached_packages, base_packages)
  
  # Create cluster specification
  # If ncores is a named vector, expand to host list for makeCluster
  # If ncores is a single number, use it directly (localhost)
  if (length(ncores) == 1 && is.null(names(ncores))) {
    # Single unnamed number - use localhost
    cluster_spec <- ncores
    total_workers <- ncores
    message(sprintf("Creating cluster with %d workers on localhost", total_workers))
    has_remote_hosts <- FALSE
  } else {
    # Named vector - distribute across hosts
    # Expand c("host1"=4, "host2"=2) to c("host1", "host1", "host1", "host1", "host2", "host2")
    cluster_spec <- unlist(mapply(
      function(host, count) rep(host, count),
      names(ncores),
      ncores,
      SIMPLIFY = FALSE,
      USE.NAMES = FALSE
    ))
    total_workers <- sum(ncores)
    
    # Check if we have any non-localhost hosts
    has_remote_hosts <- any(!names(ncores) %in% c("localhost", "127.0.0.1"))
    
    # Summarize distribution for user
    host_summary <- paste(sprintf("%s:%d", names(ncores), ncores), collapse=", ")
    message(sprintf("Creating cluster with %d workers across hosts: %s", 
                    total_workers, host_summary))
  }
  
  # Create cluster with renv support for remote hosts
  if (has_remote_hosts) {
    # Get current working directory to ensure remote workers start in same location
    # This is critical for renv to work properly - R must start in the project directory
    # so that .Rprofile can activate renv during R initialization
    working_dir <- getwd()
    
    # Create a simple wrapper script that changes to project directory before starting Rscript
    # This ensures Rscript starts in the correct location and .Rprofile activates renv properly
    wrapper_script <- file.path(working_dir, 
      sprintf(".tasker_rscript_%s.sh", format(Sys.time(), "%Y%m%d_%H%M%S")))
    writeLines(
      c(
        "#!/bin/bash",
        sprintf("cd '%s' || exit 1", working_dir),
        'exec Rscript "$@"'
      ),
      wrapper_script
    )
    Sys.chmod(wrapper_script, mode = "0755")
    
    message(sprintf("Remote workers will start in directory: %s", working_dir))
    
    if (debug) {
      cat("\n=== DEBUG: Cluster Configuration ===\n")
      cat(sprintf("Working directory: %s\n", working_dir))
      cat(sprintf("Cluster spec: %s\n", paste(cluster_spec, collapse=", ")))
      cat(sprintf("Wrapper script: %s\n", wrapper_script))
      cat(sprintf("Namespaces: %s\n", paste(loadedNamespaces(), collapse=", ")))
      cat("===================================\n\n")
    }
    
    cl <- parallelly::makeClusterPSOCK(
      cluster_spec,
      rscript = wrapper_script,
      homogeneous = TRUE  # Assume same directory structure on all hosts
    )
    
    # Store wrapper script path for cleanup
    attr(cl, "tasker_wrapper_script") <- wrapper_script

  } else {
    # Local cluster - no special handling needed
    if (debug) {
      cat("\n=== DEBUG: Cluster Configuration ===\n")
      cat(sprintf("Cluster spec: %s\n", paste(cluster_spec, collapse=", ")))
      cat("Local cluster (no custom rscript)\n")
      cat("===================================\n\n")
    }
    
    cl <- parallelly::makeClusterPSOCK(cluster_spec)
  }
  
  # Store cluster info for cleanup and tracking
  attr(cl, "tasker_managed") <- TRUE
  attr(cl, "tasker_created_at") <- Sys.time()
  
  # Store distribution info for debugging
  if (length(ncores) == 1 && is.null(names(ncores))) {
    attr(cl, "tasker_distribution") <- list(
      type = "localhost",
      total_workers = total_workers
    )
  } else {
    attr(cl, "tasker_distribution") <- list(
      type = "distributed",
      hosts = names(ncores),
      workers_per_host = as.integer(ncores),
      total_workers = total_workers
    )
  }
  
  # Disable renv watchdog on all workers to prevent extra processes
  parallel::clusterEvalQ(cl, {
    Sys.setenv(RENV_WATCHDOG_ENABLED = "FALSE")
    NULL
  })
  
  # Load namespaces on workers (for packages that were loaded but not attached)
  if (length(namespaces_only) > 0) {
    if (debug) {
      cat(sprintf("Loading namespaces on workers: %s\n", 
                  paste(namespaces_only, collapse=", ")))
    }
    for (pkg in namespaces_only) {
      parallel::clusterCall(cl, function(p) {
        loadNamespace(p)
        NULL
      }, p = pkg)
    }
  }
  
  # Attach packages on workers (for packages that were attached in main session)
  if (length(attached_packages) > 0) {
    if (debug) {
      cat(sprintf("Attaching packages on workers: %s\n", 
                  paste(attached_packages, collapse=", ")))
    }
    for (pkg in attached_packages) {
      parallel::clusterCall(cl, function(p) {
        library(p, character.only = TRUE)
        NULL
      }, p = pkg)
    }
  }
  
  # Export tasker configuration to workers (only if tasker is available)
  config <- getOption("tasker.config")
  if (!is.null(config)) {
    tryCatch({
      parallel::clusterExport(cl, "config", envir = environment())
      parallel::clusterEvalQ(cl, {
        if (requireNamespace("tasker", quietly = TRUE)) {
          options(tasker.config = config)
        }
        NULL
      })
    }, error = function(e) {
      if (debug) cat("Note: Skipped tasker config export (tasker not available on workers)\n")
    })
  }
  
  # Export active run context if it exists (only if tasker is available on workers)
  run_id <- tryCatch(tasker_context(), error = function(e) NULL)
  if (!is.null(run_id)) {
    tryCatch({
      parallel::clusterExport(cl, "run_id", envir = environment())
      
      # Export subtask counter state
      subtask_counter <- .tasker_env$subtask_counter
      if (!is.null(subtask_counter)) {
        parallel::clusterExport(cl, "subtask_counter", envir = environment())
      }
      
      # Initialize context on workers (only if tasker is available)
      if (!is.null(subtask_counter)) {
        parallel::clusterEvalQ(cl, { 
          # Only initialize if tasker package is available
          if (requireNamespace("tasker", quietly = TRUE)) {
            tasker::tasker_context(run_id)
            # Restore subtask counter - access internal environment safely
            tryCatch({
              env <- get(".tasker_env", envir = asNamespace("tasker"))
              env$subtask_counter <- subtask_counter
            }, error = function(e) {
              warning("Failed to restore subtask counter on worker: ", e$message)
            })
          }
          NULL 
        })
      } else {
        parallel::clusterEvalQ(cl, { 
          # Only initialize if tasker package is available
          if (requireNamespace("tasker", quietly = TRUE)) {
            tasker::tasker_context(run_id)
          }
          NULL 
        })
      }
    }, error = function(e) {
      if (debug) cat("Note: Skipped run context export (tasker not available on workers)\n")
    })
  }
  
  # Export additional objects if specified
  if (!is.null(export) && length(export) > 0) {
    parallel::clusterExport(cl, export, envir = envir)
  }
  
  # Run setup expression on workers if provided
  if (!is.null(setup_expr)) {
    # Export the expression to workers
    parallel::clusterExport(cl, "setup_expr", envir = environment())
    
    # Evaluate at the top level of each worker so variables persist
    result <- parallel::clusterEvalQ(cl, {
      tryCatch({
        # Evaluate at top level - assignments will go into worker's global env
        eval(setup_expr)
        # Always return NULL to avoid serialization issues
        NULL
      }, error = function(e) {
        # Log error but don't fail - some setup is optional
        warning("Setup expression failed on worker: ", e$message)
        NULL
      })
    })
  }

  return(cl)
}
