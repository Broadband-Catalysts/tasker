#' Get subtask progress for multiple task runs (batch query)
#'
#' @param run_ids Vector of run IDs to fetch subtask progress for
#' @param conn Database connection (optional)
#' 
#' @return Data frame with subtask progress for all specified runs
#' @seealso [get_subtask_progress()] for single run queries
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Get subtasks for multiple runs
#' running_tasks <- get_task_status()
#' run_ids <- running_tasks$run_id[running_tasks$status %in% c("RUNNING", "STARTED")]
#' all_subtasks <- get_subtask_progress_batch(run_ids)
#' }
get_subtask_progress_batch <- function(run_ids, conn = NULL) {
  ensure_configured()
  
  # Helper function to create empty subtask progress data frame
  create_empty_subtask_df <- function() {
    data.frame(
      progress_id = integer(0),
      run_id = character(0),
      subtask_number = integer(0),
      subtask_name = character(0),
      status = character(0),
      start_time = as.POSIXct(character(0)),
      end_time = as.POSIXct(character(0)),
      last_update = as.POSIXct(character(0)),
      percent_complete = numeric(0),
      progress_message = character(0),
      items_total = integer(0),
      items_complete = integer(0),
      error_message = character(0)
    )
  }
  
  # Return empty data frame if no run_ids provided
  if (is.null(run_ids) || length(run_ids) == 0 || all(is.na(run_ids))) {
    return(create_empty_subtask_df())
  }
  
  # Remove NA values from run_ids
  run_ids <- run_ids[!is.na(run_ids)]
  
  if (length(run_ids) == 0) {
    return(create_empty_subtask_df())
  }
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    # Only disconnect if it's a regular connection, not a pool
    close_on_exit <- !inherits(conn, "Pool")
  }
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  schema <- if (driver == "postgresql") config$database$schema else ""
  
  subtask_table_ref <- if (nchar(schema) > 0) {
    paste0(schema, ".subtask_progress")
  } else {
    "subtask_progress"
  }
  
  # Build driver-appropriate SQL for integer casting
  if (driver == "postgresql") {
    items_select <- "items_total::INTEGER as items_total, items_complete::INTEGER as items_complete"
  } else {
    # SQLite and others: plain column selection
    items_select <- "items_total as items_total, items_complete as items_complete"
  }
  
  tryCatch({
    # Build IN clause with proper escaping
    run_ids_sql <- paste0("('", paste(run_ids, collapse = "','"), "')")
    
    result <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT progress_id, run_id, subtask_number, subtask_name,
                             status, start_time, end_time, last_update,
                             percent_complete, progress_message,
                             {DBI::SQL(items_select)},
                             error_message
                      FROM {DBI::SQL(subtask_table_ref)} 
                      WHERE run_id IN {DBI::SQL(run_ids_sql)}
                      ORDER BY run_id, subtask_number",
                     .con = conn)
    )
    
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
    
    return(result)
  }, error = function(e) {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
    stop(sprintf("Error fetching batch subtask progress: %s", e$message), call. = FALSE)
  })
}
