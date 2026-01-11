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
  
  # Export run_id to cluster
  parallel::clusterExport(cl, "run_id", envir = environment())
  
  # Export subtask counter state if it exists
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
  
  invisible(run_id)
}
