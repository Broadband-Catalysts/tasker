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
