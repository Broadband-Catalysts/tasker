# Helper function to get table name with or without schema
get_table_name <- function(table, conn) {
  config <- getOption("tasker.config")
  if (is.null(config) || is.null(config$database) || is.null(config$database$driver)) {
    stop("tasker configuration not loaded. Call load_tasker_config() first.")
  }
  
  db_driver <- config$database$driver
  
  if (db_driver == "sqlite") {
    return(table)
  } else {
    schema <- config$database$schema
    if (is.null(schema) || nchar(schema) == 0) {
      return(table)
    }
    return(sprintf("%s.%s", schema, table))
  }
}

# Helper to prepare parameters for SQL queries (handle NULLs)
prepare_params <- function(...) {
  params <- list(...)
  # Convert NULL to NA for RSQLite compatibility
  lapply(params, function(x) if (is.null(x)) NA else x)
}

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
#' @param stage_order Stage ordering (optional)
#' @param task_order Task ordering within stage (optional)
#' @param conn Database connection (optional)
#' @return task_id (invisibly)
#' @export
#'
#' @examples
#' \dontrun{
#' register_task(stage = "PREREQ", name = "Install System Dependencies", type = "sh")
#' register_task(stage = "PREREQ", name = "Install R", type = "sh")
#' }
register_task <- function(stage,
                         name,
                         type,
                         description = NULL,
                         script_path = NULL,
                         script_filename = NULL,
                         log_path = NULL,
                         log_filename = NULL,
                         stage_order = NULL,
                         task_order = NULL,
                         conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  stages_table <- get_table_name("stages", conn)
  tasks_table <- get_table_name("tasks", conn)
  
  # Convert NULL to NA for glue_sql
  stage_order <- if (is.null(stage_order)) NA else stage_order
  description <- if (is.null(description)) NA else description
  script_path <- if (is.null(script_path)) NA else script_path
  script_filename <- if (is.null(script_filename)) NA else script_filename
  log_path <- if (is.null(log_path)) NA else log_path
  log_filename <- if (is.null(log_filename)) NA else log_filename
  task_order <- if (is.null(task_order)) NA else task_order
  
  tryCatch({
    stage_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {stages_table*} (stage_name, stage_order, description) 
               VALUES ({stage}, {stage_order}, {description}) 
               ON CONFLICT (stage_name) 
               DO UPDATE SET stage_order = COALESCE(EXCLUDED.stage_order, {stages_table*}.stage_order)
               RETURNING stage_id", .con = conn)
    )$stage_id
    
    task_id <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("INSERT INTO {tasks_table*} 
               (stage_id, task_name, task_type, task_order, description, 
                script_path, script_filename, log_path, log_filename)
               VALUES ({stage_id}, {name}, {type}, {task_order}, {description}, 
                       {script_path}, {script_filename}, {log_path}, {log_filename})
               ON CONFLICT (stage_id, task_name) 
               DO UPDATE SET 
                 task_type = EXCLUDED.task_type,
                 task_order = COALESCE(EXCLUDED.task_order, {tasks_table*}.task_order),
                 description = COALESCE(EXCLUDED.description, {tasks_table*}.description),
                 script_path = COALESCE(EXCLUDED.script_path, {tasks_table*}.script_path),
                 script_filename = COALESCE(EXCLUDED.script_filename, {tasks_table*}.script_filename),
                 log_path = COALESCE(EXCLUDED.log_path, {tasks_table*}.log_path),
                 log_filename = COALESCE(EXCLUDED.log_filename, {tasks_table*}.log_filename)
               RETURNING task_id", .con = conn)
    )$task_id
    
    invisible(task_id)
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}


#' Register multiple tasks at once
#'
#' @param tasks_df Data frame with columns: stage, name, type, and optional columns
#' @param conn Database connection (optional)
#' @return Vector of task_ids (invisibly)
#' @export
#'
#' @examples
#' \dontrun{
#' tasks <- data.frame(
#'   stage = c("PREREQ", "PREREQ"),
#'   name = c("Install System Dependencies", "Install R"),
#'   type = c("sh", "sh")
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
  
  required <- c("stage", "name", "type")
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
        stage_order = if ("stage_order" %in% names(row)) row$stage_order else NULL,
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


#' Get registered tasks
#'
#' @param stage Filter by stage (optional)
#' @param name Filter by task name (optional)
#' @param conn Database connection (optional)
#' @return Data frame with task information
#' @export
#'
#' @examples
#' \dontrun{
#' get_tasks()
#' get_tasks(stage = "PREREQ")
#' }
get_tasks <- function(stage = NULL, name = NULL, conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  stages_table <- get_table_name("stages", conn)
  tasks_table <- get_table_name("tasks", conn)
  
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
     FROM {tasks_table*} t
     JOIN {stages_table*} s ON t.stage_id = s.stage_id
     {where_sql*}
     ORDER BY s.stage_order NULLS LAST, s.stage_name, 
              t.task_order NULLS LAST, t.task_name",
    .con = conn
  )
  
  tryCatch({
    result <- DBI::dbGetQuery(conn, sql)
    
    result
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
