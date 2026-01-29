#' Register multiple tasks at once
#'
#' @param tasks_df Data frame with columns: stage, name, type, stage_order, and optional columns
#' @param conn Database connection (optional)
#' @return Vector of task_ids (invisibly)
#' @export
#'
#' @examples
#' \dontrun{
#' tasks <- data.frame(
#'   stage = c("PREREQ", "PREREQ"),
#'   name = c("Install System Dependencies", "Install R"),
#'   type = c("sh", "sh"),
#'   stage_order = c(1, 1)
#' )
#' register_tasks(tasks)
#' }
register_tasks <- function(tasks_df, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  required <- c("stage", "name", "type", "stage_order")
  missing <- setdiff(required, names(tasks_df))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }
  
  task_ids <- vector("integer", nrow(tasks_df))
  
  tryCatch({
    for (i in seq_len(nrow(tasks_df))) {
      row <- tasks_df[i, ]
      
      task_ids[i] <- register_task(
        stage = row$stage,
        name = row$name,
        type = row$type,
        description = if ("description" %in% names(row)) row$description else NULL,
        script_path = if ("script_path" %in% names(row)) row$script_path else NULL,
        script_filename = if ("script_filename" %in% names(row)) row$script_filename else NULL,
        log_path = if ("log_path" %in% names(row)) row$log_path else NULL,
        log_filename = if ("log_filename" %in% names(row)) row$log_filename else NULL,
        stage_order = row$stage_order,
        task_order = if ("task_order" %in% names(row)) row$task_order else NULL,
        conn = conn
      )
    }
    
    invisible(task_ids)
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
