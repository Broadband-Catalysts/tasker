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
  
  # Input validation
  if (!is.null(ncores)) {
    if (!is.numeric(ncores) || length(ncores) != 1 || ncores < 1) {
      stop("'ncores' must be a positive integer", call. = FALSE)
    }
    ncores <- as.integer(ncores)
  }
  
  if (!is.null(packages)) {
    if (!is.character(packages)) {
      stop("'packages' must be a character vector of package names", call. = FALSE)
    }
  }
  
  if (!is.null(export)) {
    if (!is.character(export)) {
      stop("'export' must be a character vector of object names", call. = FALSE)
    }
  }
  
  if (!is.logical(load_all) || length(load_all) != 1) {
    stop("'load_all' must be TRUE or FALSE", call. = FALSE)
  }
  
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
        # Restore subtask counter - access internal environment safely
        tryCatch({
          env <- get(".tasker_env", envir = asNamespace("tasker"))
          env$subtask_counter <- subtask_counter
        }, error = function(e) {
          warning("Failed to restore subtask counter on worker: ", e$message)
        })
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
