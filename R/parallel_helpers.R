#' Initialize parallel cluster with tasker configuration
#'
#' This function simplifies setting up parallel processing with tasker by
#' automatically handling package loading, object export, and context initialization
#' on all workers. It encapsulates the common pattern of cluster setup, reducing
#' boilerplate from 8-10 lines to 1-2 lines.
#'
#' @param ncores Number of cores (default: auto-detect as detectCores() - 2, max 32)
#' @param packages Character vector of package names to load on workers (optional).
#'   The tasker package is always loaded automatically.
#' @param export Character vector of object names to export to workers (optional).
#'   The active run_id is always exported automatically if one exists.
#' @param setup_expr Expression to evaluate on each worker after packages are loaded
#'   (e.g., for creating database connections). The expression should return NULL
#'   or a serializable value to avoid serialization errors. (optional)
#' @param envir Environment to export objects from (default: parent.frame())
#' @param load_all If TRUE, call devtools::load_all() on workers (default: FALSE)
#' @return Cluster object from parallel::makeCluster()
#' @export
#'
#' @examples
#' \dontrun{
#' # Simple setup with auto-detection
#' cl <- tasker_cluster()
#' results <- parLapply(cl, items, worker_function)
#' stop_tasker_cluster(cl)
#'
#' # With custom packages and objects
#' cl <- tasker_cluster(
#'   ncores = 16,
#'   packages = c("dplyr", "sf"),
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
tasker_cluster <- function(ncores = NULL, 
                           packages = NULL,
                           export = NULL,
                           setup_expr = NULL,
                           envir = parent.frame(),
                           load_all = FALSE) {
  
  # Auto-detect number of cores
  if (is.null(ncores)) {
    ncores <- parallel::detectCores() - 2
    ncores <- max(1, min(ncores, 32))  # At least 1, max 32 by default
  }
  
  # Create cluster
  cl <- parallel::makeCluster(ncores)
  
  # Store cluster info for cleanup and tracking
  attr(cl, "tasker_managed") <- TRUE
  attr(cl, "tasker_created_at") <- Sys.time()
  
  # Load tasker package on all workers
  # Try library() first, fall back to devtools::load_all() for development
  if (load_all) {
    # In development mode, try library first, fall back to load_all
    parallel::clusterEvalQ(cl, { 
      loaded <- suppressWarnings(require(tasker, quietly = TRUE))
      if (!loaded && requireNamespace("devtools", quietly = TRUE)) {
        devtools::load_all()
      }
      NULL 
    })
  } else {
    # Normal mode - just load the package
    parallel::clusterEvalQ(cl, { 
      library(tasker)
      NULL 
    })
  }
  
  # Load additional packages if specified
  if (!is.null(packages)) {
    for (pkg in packages) {
      parallel::clusterCall(cl, function(p) {
        library(p, character.only = TRUE)
        NULL
      }, p = pkg)
    }
  }
  
  # Export tasker configuration to workers
  config <- getOption("tasker.config")
  if (!is.null(config)) {
    parallel::clusterExport(cl, "config", envir = environment())
    parallel::clusterEvalQ(cl, {
      options(tasker.config = config)
      NULL
    })
  }
  
  # Export active run context if it exists
  run_id <- tryCatch(tasker_context(), error = function(e) NULL)
  if (!is.null(run_id)) {
    parallel::clusterExport(cl, "run_id", envir = environment())
    
    # Export subtask counter state
    subtask_counter <- .tasker_env$subtask_counter
    if (!is.null(subtask_counter)) {
      parallel::clusterExport(cl, "subtask_counter", envir = environment())
    }
    
    # Initialize context on workers
    if (!is.null(subtask_counter)) {
      parallel::clusterEvalQ(cl, { 
        tasker::tasker_context(run_id)
        # Restore subtask counter - access internal environment via get()
        env <- get(".tasker_env", envir = asNamespace("tasker"))
        env$subtask_counter <- subtask_counter
        NULL 
      })
    } else {
      parallel::clusterEvalQ(cl, { 
        tasker::tasker_context(run_id)
        NULL 
      })
    }
  }
  
  # Export additional objects if specified
  if (!is.null(export) && length(export) > 0) {
    parallel::clusterExport(cl, export, envir = envir)
  }
  
  # Run setup expression on workers if provided
  if (!is.null(setup_expr)) {
    parallel::clusterEvalQ(cl, {
      eval(setup_expr)
      NULL  # Always return NULL to avoid serialization issues
    })
  }
  
  return(cl)
}


#' Stop tasker-managed parallel cluster
#'
#' Cleanly shuts down a parallel cluster created with tasker_cluster().
#' This is a convenience wrapper around parallel::stopCluster() that handles
#' NULL clusters gracefully and provides informative messages.
#'
#' @param cl Cluster object from tasker_cluster()
#' @param quiet Suppress informational messages (default: FALSE)
#' @export
#'
#' @examples
#' \dontrun{
#' cl <- tasker_cluster(ncores = 8)
#' # ... do parallel work ...
#' stop_tasker_cluster(cl)
#' }
stop_tasker_cluster <- function(cl, quiet = FALSE) {
  if (is.null(cl)) {
    if (!quiet) {
      message("No cluster to stop (cl is NULL)")
    }
    return(invisible(NULL))
  }
  
  # Check if this is a tasker-managed cluster
  is_tasker_managed <- !is.null(attr(cl, "tasker_managed"))
  created_at <- attr(cl, "tasker_created_at")
  
  # Stop the cluster
  tryCatch({
    parallel::stopCluster(cl)
    
    if (!quiet && is_tasker_managed) {
      if (!is.null(created_at)) {
        duration <- difftime(Sys.time(), created_at, units = "secs")
        message(sprintf("Cluster stopped (active for %.1f seconds)", as.numeric(duration)))
      } else {
        message("Cluster stopped")
      }
    }
  }, error = function(e) {
    warning("Error stopping cluster: ", conditionMessage(e), call. = FALSE)
  })
  
  invisible(NULL)
}


#' Export tasker context to existing cluster
#'
#' If you have an existing parallel cluster (not created with tasker_cluster()),
#' this helper function exports the current tasker context to all workers.
#'
#' @param cl Existing cluster object
#' @param run_id Run ID to export (default: current active context)
#' @export
#'
#' @examples
#' \dontrun{
#' # Existing cluster setup
#' cl <- makeCluster(8)
#' clusterEvalQ(cl, library(tasker))
#'
#' # Start task and export context
#' task_start("STAGE", "Task")
#' export_tasker_context(cl)
#'
#' # Now workers can use context-based API
#' results <- parLapply(cl, items, function(x) {
#'   subtask_increment(increment = 1)
#'   process_item(x)
#' })
#' }
export_tasker_context <- function(cl, run_id = NULL) {
  # Get run_id from context if not provided
  if (is.null(run_id)) {
    run_id <- tasker_context()
    if (is.null(run_id)) {
      stop("No active tasker context. Call task_start() first or pass run_id explicitly.",
           call. = FALSE)
    }
  }
  
  # Export to cluster
  parallel::clusterExport(cl, "run_id", envir = environment())
  
  # Initialize context on workers
  parallel::clusterEvalQ(cl, { 
    tasker::tasker_context(run_id)
    NULL 
  })
  
  invisible(run_id)
}
