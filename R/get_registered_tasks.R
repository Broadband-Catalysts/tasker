#' Get registered tasks with full details
#'
#' Retrieves task registration information from the tasks and stages tables.
#' This is different from get_tasks() which retrieves task execution status.
#'
#' @param stage Filter by stage (optional)
#' @param name Filter by task name (optional)
#' @param conn Database connection (optional)
#' @return Data frame with task registration information
#' @export
#'
#' @examples
#' \dontrun{
#' get_registered_tasks()
#' get_registered_tasks(stage = "PREREQ")
#' }
get_registered_tasks <- function(stage = NULL, name = NULL, conn = NULL) {
  ensure_configured()
  
  # Input validation
  if (!is.null(stage) && (!is.character(stage) || length(stage) != 1)) {
    stop("'stage' must be a single character string if provided", call. = FALSE)
  }
  
  if (!is.null(name) && (!is.character(name) || length(name) != 1)) {
    stop("'name' must be a single character string if provided", call. = FALSE)
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
  
  stages_table <- get_table_name("stages", conn)
  tasks_table  <- get_table_name("tasks",  conn)
  
  # Build WHERE clause
  where_parts <- c()
  
  if (!is.null(stage)) {
    where_parts <- c(where_parts, glue::glue("s.stage_name = {DBI::dbQuoteLiteral(conn, stage)}"))
  }
  
  if (!is.null(name)) {
    where_parts <- c(where_parts, glue::glue("t.task_name = {DBI::dbQuoteLiteral(conn, name)}"))
  }
  
  where_sql <- if (length(where_parts) > 0) {
    DBI::SQL(paste("WHERE", paste(where_parts, collapse = " AND ")))
  } else {
    DBI::SQL("")
  }
  
  sql <- glue::glue_sql(
    "SELECT s.stage_id, s.stage_name, s.stage_order,
            t.task_id, t.task_name, t.task_type, t.task_order,
            t.description, t.script_path, t.script_filename,
            t.log_path, t.log_filename,
            t.created_at, t.updated_at
     FROM {tasks_table} t
     JOIN {stages_table} s ON t.stage_id = s.stage_id
     {where_sql*}
     ORDER BY COALESCE(s.stage_order, 99999), s.stage_name, 
              COALESCE(t.task_order, 99999), t.task_name",
    .con = conn
  )
  
  tryCatch({
    result <- DBI::dbGetQuery(conn, sql)
    
    result
    
  }, error = function(e) {
    stop("Failed to retrieve registered tasks: ", conditionMessage(e), call. = FALSE)
  })
}
