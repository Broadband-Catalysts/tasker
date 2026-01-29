#' Register a task in the tasker system
#'
#' When called from within a script, this function can automatically detect and
#' use sensible defaults for script paths and log filenames (with warnings).
#'
#' @param stage Stage name (e.g., "PREREQ", "STATIC", "DAILY")
#' @param name Task name
#' @param type Task type (e.g., "R", "python", "sh"). If NULL and script_filename
#'   is available, auto-detects from file extension (.R → "R", .py → "python", 
#'   .sh → "sh") with warning
#' @param description Task description (optional)
#' @param script_path Path to script directory. If NULL and executing from a
#'   script, defaults to the directory of the currently executing script (with warning)
#' @param script_filename Script filename. If NULL and script_path is provided,
#'   extracts filename from script_path. If both are NULL and executing from a
#'   script, defaults to the currently executing script filename (with warning)
#' @param log_path Path to log directory. If NULL and script_path is detected,
#'   defaults to same as script_path (with warning)
#' @param log_filename Log filename. If NULL and script_filename is available,
#'   defaults to script_filename with extension changed (.R → .Rout, .sh/.py → .log)
#'   (with warning)
#' @param stage_order Stage ordering (required)
#' @param task_order Task ordering within stage (optional)
#' @param conn Database connection (optional)
#' @return task_id (invisibly)
#' @export
#'
#' @examples
#' \dontrun{
#' # Explicit specification (no warnings)
#' register_task(stage = "PREREQ", name = "Install System Dependencies", 
#'               type = "sh", stage_order = 1,
#'               script_path = "/path/to/scripts",
#'               script_filename = "01_install.sh",
#'               log_path = "/path/to/logs",
#'               log_filename = "01_install.log")
#' 
#' # Auto-detection from script context (issues warnings)
#' register_task(stage = "PREREQ", name = "Install R", 
#'               type = "sh", stage_order = 1)
#' }
register_task <- function(stage,
                         name,
                         type            = NULL,
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
  
  # Type validation will happen after potential auto-detection below
  
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
  
  # Apply sensible defaults with warnings when parameters are missing
  defaults_applied <- FALSE
  
  # Detect current script if needed
  detected_script_filename <- NULL
  detected_script_path <- NULL
  
  if (is.null(script_filename) || is.null(script_path)) {
    detected_script_filename <- get_script_filename()
    if (!is.null(detected_script_filename)) {
      # Get full path using command line args or this.path
      args <- commandArgs(trailingOnly = FALSE)
      file_arg <- grep("^--file=", args, value = TRUE)
      if (length(file_arg) > 0) {
        full_path <- sub("^--file=", "", file_arg[1])
        detected_script_path <- dirname(full_path)
      } else {
        tryCatch({
          full_path <- this.path::this.path()
          if (!is.null(full_path) && nchar(full_path) > 0) {
            detected_script_path <- dirname(full_path)
          }
        }, error = function(e) {})
      }
    }
  }
  
  # Apply defaults for script_filename
  if (is.null(script_filename) && !is.null(detected_script_filename)) {
    script_filename <- detected_script_filename
    warning("'script_filename' not specified, using detected value: ", script_filename, call. = FALSE)
    defaults_applied <- TRUE
  }
  
  # Apply defaults for script_path
  if (is.null(script_path) && !is.null(detected_script_path)) {
    script_path <- detected_script_path
    warning("'script_path' not specified, using detected value: ", script_path, call. = FALSE)
    defaults_applied <- TRUE
  }
  
  # Extract script_filename from script_path if not provided
  if (is.null(script_filename) && !is.null(script_path)) {
    script_filename <- basename(script_path)
    warning("'script_filename' not specified, extracting from script_path: ", script_filename, call. = FALSE)
    defaults_applied <- TRUE
  }
  
  # Auto-detect type from script_filename extension if not provided
  if ((missing(type) || is.null(type)) && !is.null(script_filename)) {
    if (grepl("\\.R$", script_filename, ignore.case = TRUE)) {
      type <- "R"
    } else if (grepl("\\.py$", script_filename, ignore.case = TRUE)) {
      type <- "python"
    } else if (grepl("\\.sh$", script_filename, ignore.case = TRUE)) {
      type <- "sh"
    } else {
      # Unknown extension - require explicit type
      type <- NULL
    }
    
    if (!is.null(type)) {
      warning("'type' not specified, detected from script extension: ", type, call. = FALSE)
      defaults_applied <- TRUE
    }
  }
  
  # Validate type (now that it may have been auto-detected)
  if (is.null(type) || !is.character(type) || length(type) != 1 || nchar(trimws(type)) == 0) {
    stop("'type' must be a non-empty character string (e.g., 'R', 'python', 'sh'). ",
         "Could not auto-detect from script filename.", call. = FALSE)
  }
  
  # Apply defaults for log_path (same as script_path)
  if (is.null(log_path) && !is.null(script_path)) {
    log_path <- script_path
    warning("'log_path' not specified, using same as script_path: ", log_path, call. = FALSE)
    defaults_applied <- TRUE
  }
  
  # Apply defaults for log_filename based on script_filename
  if (is.null(log_filename) && !is.null(script_filename)) {
    # Determine log extension based on script type
    if (grepl("\\.R$", script_filename, ignore.case = TRUE)) {
      log_filename <- sub("\\.R$", ".Rout", script_filename, ignore.case = TRUE)
    } else if (grepl("\\.sh$", script_filename, ignore.case = TRUE)) {
      log_filename <- sub("\\.sh$", ".log", script_filename, ignore.case = TRUE)
    } else if (grepl("\\.py$", script_filename, ignore.case = TRUE)) {
      log_filename <- sub("\\.py$", ".log", script_filename, ignore.case = TRUE)
    } else {
      # Unknown extension, use .log as default
      log_filename <- paste0(script_filename, ".log")
    }
    warning("'log_filename' not specified, using derived value: ", log_filename, call. = FALSE)
    defaults_applied <- TRUE
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
