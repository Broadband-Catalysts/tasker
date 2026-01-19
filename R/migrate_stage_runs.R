#' Migrate Task Runs to Different Stage
#'
#' Migrates all task_runs from tasks in an old stage to corresponding tasks
#' in a new stage. Tasks are matched by task_name. Optionally deletes the
#' old stage and tasks after migration.
#'
#' This is useful when renaming stages or reorganizing the task hierarchy.
#' The function ensures referential integrity by updating task_runs before
#' attempting to delete old tasks.
#'
#' @param old_stage_name Name of the stage to migrate from
#' @param new_stage_name Name of the stage to migrate to (must exist)
#' @param delete_old_stage If TRUE, delete the old stage and its tasks after
#'   migration (default: FALSE for safety)
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param quiet If TRUE, suppress informational messages (default: FALSE)
#'
#' @return Invisibly returns a list with migration details:
#'   \item{tasks_migrated}{Number of tasks migrated}
#'   \item{runs_updated}{Number of task_runs updated}
#'   \item{old_tasks_deleted}{Number of old tasks deleted (if delete_old_stage=TRUE)}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Migrate runs from FCC_DOWNLOAD to DAILY_FCC_DOWNLOAD
#' migrate_stage_runs("FCC_DOWNLOAD", "DAILY_FCC_DOWNLOAD", delete_old_stage = TRUE)
#'
#' # Preview migration without deleting old stage
#' migrate_stage_runs("OLD_STAGE", "NEW_STAGE", delete_old_stage = FALSE)
#' }
migrate_stage_runs <- function(old_stage_name,
                               new_stage_name,
                               delete_old_stage = FALSE,
                               conn = NULL,
                               quiet = FALSE) {
  ensure_configured()
  
  # Input validation
  if (missing(old_stage_name) || !is.character(old_stage_name) || 
      length(old_stage_name) != 1 || nchar(trimws(old_stage_name)) == 0) {
    stop("'old_stage_name' must be a non-empty character string", call. = FALSE)
  }
  
  if (missing(new_stage_name) || !is.character(new_stage_name) || 
      length(new_stage_name) != 1 || nchar(trimws(new_stage_name)) == 0) {
    stop("'new_stage_name' must be a non-empty character string", call. = FALSE)
  }
  
  if (!is.logical(delete_old_stage) || length(delete_old_stage) != 1) {
    stop("'delete_old_stage' must be TRUE or FALSE", call. = FALSE)
  }
  
  close_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_conn <- TRUE
  }
  
  on.exit({
    if (close_conn && !is.null(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
  stages_table <- get_table_name("stages", conn)
  tasks_table <- get_table_name("tasks", conn)
  task_runs_table <- get_table_name("task_runs", conn)
  
  tryCatch({
    # Check that both stages exist
    old_stage_check <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT stage_id FROM {stages_table} WHERE stage_name = {old_stage_name}", 
                     .con = conn)
    )
    
    if (nrow(old_stage_check) == 0) {
      stop("Old stage '", old_stage_name, "' not found in database", call. = FALSE)
    }
    
    new_stage_check <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT stage_id FROM {stages_table} WHERE stage_name = {new_stage_name}", 
                     .con = conn)
    )
    
    if (nrow(new_stage_check) == 0) {
      stop("New stage '", new_stage_name, "' not found in database", call. = FALSE)
    }
    
    # Get tasks from both stages with matching task_names
    old_tasks <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT t.task_id, t.task_name, t.task_order 
                      FROM {tasks_table} t
                      JOIN {stages_table} s ON t.stage_id = s.stage_id
                      WHERE s.stage_name = {old_stage_name}
                      ORDER BY t.task_order", 
                     .con = conn)
    )
    
    if (nrow(old_tasks) == 0) {
      if (!quiet) {
        message("No tasks found in old stage '", old_stage_name, "' - nothing to migrate")
      }
      return(invisible(list(
        tasks_migrated = 0,
        runs_updated = 0,
        old_tasks_deleted = 0
      )))
    }
    
    new_tasks <- DBI::dbGetQuery(
      conn,
      glue::glue_sql("SELECT t.task_id, t.task_name, t.task_order 
                      FROM {tasks_table} t
                      JOIN {stages_table} s ON t.stage_id = s.stage_id
                      WHERE s.stage_name = {new_stage_name}
                      ORDER BY t.task_order", 
                     .con = conn)
    )
    
    if (nrow(new_tasks) == 0) {
      stop("New stage '", new_stage_name, "' has no tasks - cannot migrate", call. = FALSE)
    }
    
    if (!quiet) {
      message("Migrating task runs from '", old_stage_name, "' to '", new_stage_name, "'...")
      message("Found ", nrow(old_tasks), " old tasks and ", nrow(new_tasks), " new tasks")
    }
    
    # Match tasks by name and update task_runs
    total_runs_updated <- 0
    tasks_migrated <- 0
    
    for (i in seq_len(nrow(old_tasks))) {
      old_task <- old_tasks[i, ]
      
      # Find matching new task by name
      new_task <- new_tasks[new_tasks$task_name == old_task$task_name, ]
      
      if (nrow(new_task) == 0) {
        if (!quiet) {
          warning("No matching new task found for '", old_task$task_name, "' - skipping")
        }
        next
      }
      
      if (nrow(new_task) > 1) {
        warning("Multiple new tasks found for '", old_task$task_name, "' - using first match")
        new_task <- new_task[1, ]
      }
      
      # Update task_runs to point to new task_id
      result <- DBI::dbExecute(
        conn,
        glue::glue_sql("UPDATE {task_runs_table} 
                        SET task_id = {new_task$task_id}
                        WHERE task_id = {old_task$task_id}",
                       .con = conn)
      )
      
      if (result > 0) {
        tasks_migrated <- tasks_migrated + 1
        total_runs_updated <- total_runs_updated + result
        if (!quiet) {
          message("  ✓ Migrated ", result, " run(s) for task: ", old_task$task_name)
        }
      }
    }
    
    if (!quiet) {
      message("Migration complete: ", tasks_migrated, " tasks migrated, ", 
              total_runs_updated, " task_runs updated")
    }
    
    # Delete old tasks if requested
    old_tasks_deleted <- 0
    if (delete_old_stage) {
      if (!quiet) {
        message("\nDeleting old tasks from '", old_stage_name, "' stage...")
      }
      
      # Delete tasks (will cascade to any remaining task_runs if foreign key allows)
      result <- DBI::dbExecute(
        conn,
        glue::glue_sql("DELETE FROM {tasks_table} 
                        WHERE task_id IN (
                          SELECT t.task_id 
                          FROM {tasks_table} t
                          JOIN {stages_table} s ON t.stage_id = s.stage_id
                          WHERE s.stage_name = {old_stage_name}
                        )",
                       .con = conn)
      )
      old_tasks_deleted <- result
      
      if (!quiet) {
        message("  ✓ Deleted ", result, " old task(s)")
      }
      
      # Delete stage
      result <- DBI::dbExecute(
        conn,
        glue::glue_sql("DELETE FROM {stages_table} WHERE stage_name = {old_stage_name}",
                       .con = conn)
      )
      
      if (!quiet) {
        message("  ✓ Deleted old stage '", old_stage_name, "'")
      }
    }
    
    if (!quiet) {
      message("\n✓ Stage migration completed successfully")
    }
    
    invisible(list(
      tasks_migrated = tasks_migrated,
      runs_updated = total_runs_updated,
      old_tasks_deleted = old_tasks_deleted
    ))
    
  }, error = function(e) {
    stop("Error during stage migration: ", e$message, call. = FALSE)
  })
}
