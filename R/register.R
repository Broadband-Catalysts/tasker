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
  
  config <- getOption("tasker.config")
  schema <- config$database$schema
  
  tryCatch({
    stage_id <- DBI::dbGetQuery(
      conn,
      sprintf("INSERT INTO %s.stages (stage_name, stage_order, description) 
               VALUES ($1, $2, $3) 
               ON CONFLICT (stage_name) 
               DO UPDATE SET stage_order = COALESCE(EXCLUDED.stage_order, %s.stages.stage_order)
               RETURNING stage_id", schema, schema),
      params = list(stage, stage_order, description)
    )$stage_id
    
    task_id <- DBI::dbGetQuery(
      conn,
      sprintf("INSERT INTO %s.tasks 
               (stage_id, task_name, task_type, task_order, description, 
                script_path, script_filename, log_path, log_filename)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
               ON CONFLICT (stage_id, task_name) 
               DO UPDATE SET 
                 task_type = EXCLUDED.task_type,
                 task_order = COALESCE(EXCLUDED.task_order, %s.tasks.task_order),
                 description = COALESCE(EXCLUDED.description, %s.tasks.description),
                 script_path = COALESCE(EXCLUDED.script_path, %s.tasks.script_path),
                 script_filename = COALESCE(EXCLUDED.script_filename, %s.tasks.script_filename),
                 log_path = COALESCE(EXCLUDED.log_path, %s.tasks.log_path),
                 log_filename = COALESCE(EXCLUDED.log_filename, %s.tasks.log_filename)
               RETURNING task_id", schema, schema, schema, schema, schema, schema, schema),
      params = list(stage_id, name, type, task_order, description,
                   script_path, script_filename, log_path, log_filename)
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
  
  config <- getOption("tasker.config")
  schema <- config$database$schema
  
  where_clauses <- c()
  params <- list()
  
  if (!is.null(stage)) {
    where_clauses <- c(where_clauses, "s.stage_name = $1")
    params <- c(params, list(stage))
  }
  
  if (!is.null(name)) {
    param_num <- length(params) + 1
    where_clauses <- c(where_clauses, sprintf("t.task_name = $%d", param_num))
    params <- c(params, list(name))
  }
  
  where_sql <- if (length(where_clauses) > 0) {
    paste("WHERE", paste(where_clauses, collapse = " AND "))
  } else {
    ""
  }
  
  sql <- sprintf(
    "SELECT s.stage_id, s.stage_name, s.stage_order,
            t.task_id, t.task_name, t.task_type, t.task_order,
            t.description, t.script_path, t.script_filename,
            t.log_path, t.log_filename,
            t.created_at, t.updated_at
     FROM %s.tasks t
     JOIN %s.stages s ON t.stage_id = s.stage_id
     %s
     ORDER BY s.stage_order NULLS LAST, s.stage_name, 
              t.task_order NULLS LAST, t.task_name",
    schema, schema, where_sql
  )
  
  tryCatch({
    result <- if (length(params) > 0) {
      DBI::dbGetQuery(conn, sql, params = params)
    } else {
      DBI::dbGetQuery(conn, sql)
    }
    
    result
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
