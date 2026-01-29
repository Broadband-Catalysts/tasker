#' Register a task in the tasker system
#'
#' @param stage Stage name (e.g., "PREREQ", "STATIC", "DAILY")
#' @param name Task name
#' @param type Task type (e.g., "R", "python", "sh")
#' @param description Task description (optional)
#' @param script_path Path to script directory (optional)
#' @param script_filename Script filename (optional)
#' @param log_path Path to log directory (optional)
#' @param log_filename Log filename (optional)
#' @param stage_order Stage ordering (required)
#' @param task_order Task ordering within stage (optional)
#' @param conn Database connection (optional)
#' @return task_id (invisibly)
#' @export
#'
#' @examples
#' \dontrun{
#' register_task(stage = "PREREQ", name = "Install System Dependencies", 
#'               type = "sh", stage_order = 1)
#' register_task(stage = "PREREQ", name = "Install R", 
#'               type = "sh", stage_order = 1)
#' }
register_task <- function(stage,
                         name,
                         type,
                         description     = NULL,
                         script_path     = NULL,
                         script_filename = NULL,
                         log_path        = NULL,
                         log_filename    = NULL,
                         stage_order,
                         task_order      = NULL,
                         conn            = NULL) {
  ensure_configured()
  
  # Input validation
  if (missing(stage) || !is.character(stage) || length(stage) != 1 || nchar(trimws(stage)) == 0) {
    stop("'stage' must be a non-empty character string", call. = FALSE)
  }
  
  if (missing(name) || !is.character(name) || length(name) != 1 || nchar(trimws(name)) == 0) {
    stop("'name' must be a non-empty character string", call. = FALSE)
  }
  
  if (missing(type) || !is.character(type) || length(type) != 1 || nchar(trimws(type)) == 0) {
    stop("'type' must be a non-empty character string (e.g., 'R', 'python', 'sh')", call. = FALSE)
  }
  
  # Validate stage_order is required
  if (missing(stage_order) || is.null(stage_order) || is.na(stage_order)) {
    stop("'stage_order' is required and must be a non-NA number", call. = FALSE)
  }
  
  if (!is.numeric(stage_order) || length(stage_order) != 1) {
    stop("'stage_order' must be a single number", call. = FALSE)
  }
  stage_order <- as.integer(stage_order)
  
  if (!is.null(task_order)) {
    if (!is.numeric(task_order) || length(task_order) != 1) {
      stop("'task_order' must be a single number if provided", call. = FALSE)
    }
    task_order <- as.integer(task_order)
  }
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  stages_table <- get_table_name("stages", conn)
  tasks_table  <- get_table_name("tasks", conn)
  
  tryCatch({
    # Handle NULL values in SQL - use SQL NULL literal for NULL/NA values
    description_sql <- if (is.null(description) || is.na(description)) DBI::SQL("NULL") else description
    
    stage_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {stages_table} (stage_name, stage_order, description) 
               VALUES ({stage}, {stage_order}, {description_sql}) 
               ON CONFLICT (stage_name) 
               DO UPDATE SET stage_order = {stage_order},
                             description = COALESCE(EXCLUDED.description, {stages_table}.description)
               RETURNING stage_id", .con = conn)
    )$stage_id
    
    # Handle NULL values for task fields
    script_path_sql      <- if (is.null(script_path)      || is.na(script_path))      DBI::SQL("NULL") else script_path
    
    # Auto-extract script_filename from script_path if not provided
    if ((is.null(script_filename) || is.na(script_filename)) && !is.null(script_path) && !is.na(script_path)) {
      script_filename <- basename(script_path)
    }
    
    script_filename_sql  <- if (is.null(script_filename)  || is.na(script_filename))  DBI::SQL("NULL") else script_filename
    log_path_sql         <- if (is.null(log_path)         || is.na(log_path))         DBI::SQL("NULL") else log_path
    log_filename_sql     <- if (is.null(log_filename)     || is.na(log_filename))     DBI::SQL("NULL") else log_filename
    task_order_sql       <- if (is.null(task_order)       || is.na(task_order))       DBI::SQL("NULL") else task_order
    description_task_sql <- if (is.null(description)      || is.na(description))      DBI::SQL("NULL") else description
    
    task_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {tasks_table} 
               (stage_id, task_name, task_type, task_order, description, 
                script_path, script_filename, log_path, log_filename)
               VALUES ({stage_id}, {name}, {type}, {task_order_sql}, {description_task_sql}, 
                       {script_path_sql}, {script_filename_sql}, {log_path_sql}, {log_filename_sql})
               ON CONFLICT (stage_id, task_name) 
               DO UPDATE SET 
                 task_type = EXCLUDED.task_type,
                 task_order = COALESCE(EXCLUDED.task_order, {tasks_table}.task_order),
                 description = COALESCE(EXCLUDED.description, {tasks_table}.description),
                 script_path = COALESCE(EXCLUDED.script_path, {tasks_table}.script_path),
                 script_filename = COALESCE(EXCLUDED.script_filename, {tasks_table}.script_filename),
                 log_path = COALESCE(EXCLUDED.log_path, {tasks_table}.log_path),
                 log_filename = COALESCE(EXCLUDED.log_filename, {tasks_table}.log_filename)
               RETURNING task_id", .con = conn)
    )$task_id
    
    invisible(task_id)
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
