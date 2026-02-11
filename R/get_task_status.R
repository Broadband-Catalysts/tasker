#' Get current task status
#'
#' @param stage Filter by stage (optional)
#' @param task Filter by task name (optional)
#' @param status Filter by status (optional)
#' @param limit Maximum number of results (default: all)
#' @param conn Database connection (optional)
#' @return Data frame with task status
#'
#' @seealso [get_active_tasks()] to get only running tasks,
#'   [get_task_history()] to view detailed execution history,
#'   [get_subtask_progress()] to view subtask details for a run
#'
#' @export
#'
#' @examples
#' \dontrun{
#' get_task_status()
#' get_task_status(status = "RUNNING")
#' get_task_status(stage = "DAILY")
#' }
get_task_status <- function(stage = NULL, task = NULL, status = NULL,
                           limit = NULL, conn = NULL) {
  ensure_configured()
  
  # Input validation
  if (!is.null(limit)) {
    if (!is.numeric(limit) || length(limit) != 1 || limit < 1) {
      stop("'limit' must be a positive integer if provided", call. = FALSE)
    }
    limit <- as.integer(limit)
  }
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  # Ensure cleanup on exit
  on.exit({
    if (close_on_exit && !is.null(conn) && DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  schema <- if (driver == "postgresql") config$database$schema else ""
  
  # Use view with process metrics for comprehensive status
  table_ref <- if (nchar(schema) > 0) {
    DBI::Id(schema = schema, table = "current_task_status_with_metrics")
  } else {
    "current_task_status_with_metrics"
  }
  
  tryCatch({
    # Use dplyr to build query
    query <- dplyr::tbl(conn, table_ref)
    
    # Apply filters
    if (!is.null(stage)) {
      query <- dplyr::filter(query, .data$stage_name == !!stage)
    }
    
    if (!is.null(task)) {
      query <- dplyr::filter(query, .data$task_name == !!task)
    }
    
    if (!is.null(status)) {
      query <- dplyr::filter(query, .data$status == !!status)
    }
    
    # Order by stage_order, task_order, then most recent first
    query <- dplyr::arrange(query, .data$stage_order, .data$task_order, dplyr::desc(.data$start_time))
    
    # Apply limit if specified
    if (!is.null(limit)) {
      query <- dplyr::slice_head(query, n = as.integer(limit))
    }
    
    # Collect results
    result <- dplyr::collect(query)
    
    result
    
  }, error = function(e) {
    stop("Failed to retrieve task status: ", conditionMessage(e), call. = FALSE)
  })
}
