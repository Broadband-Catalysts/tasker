#' Update subtask progress by name or filename
#'
#' Updates the progress of a subtask in the most recent task run. Supports
#' multiple ways to specify the task: by filename alone, by stage and task
#' number, or by stage and task name.
#'
#' @param stage Stage name or number (e.g., "DAILY_FCC_SUMMARY", 8). Optional
#'   if `filename` is provided.
#' @param task Task name or number (e.g., "Provider Tables Block20", 3). Optional
#'   if `filename` is provided.
#' @param subtask Subtask number (1, 2, 3...) or subtask name. Required.
#' @param status Optional: Status to set (RUNNING, COMPLETED, FAILED, SKIPPED)
#' @param percent Optional: Percent complete 0-100
#' @param items_total Optional: Total items for this subtask
#' @param items_completed Optional: Items completed so far
#' @param message Optional: Progress message
#' @param error_message Optional: Error message if failed
#' @param quiet Suppress console messages (default: FALSE)
#' @param conn Database connection (optional)
#' @param filename Optional: Script filename to identify task. If provided,
#'   `stage` and `task` are ignored. Supports partial matching.
#'
#' @return TRUE on success, FALSE if task/subtask not found
#'
#' @details
#' Multiple ways to specify the task:
#' \itemize{
#'   \item **By filename alone** (no stage needed): `filename = "06_DAILY_FCC_SUMMARY_03_Provider_Tables_Block20.R"`
#'   \item **By stage number and task number**: `stage = 8, task = 3`
#'   \item **By stage name and task number**: `stage = "DAILY_FCC_SUMMARY", task = 3`
#'   \item **By stage and task name**: `stage = "DAILY_FCC_SUMMARY", task = "Provider Tables Block20"`
#' }
#'
#' Filename matching is case-insensitive and supports partial matching.
#' If multiple tasks match by filename, an error is raised.
#'
#' @seealso [subtask_update()] to update subtask with explicit run_id,
#'   [update_task()] for task updates
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # By filename alone (no stage needed)
#' update_subtask(
#'   filename = "06_DAILY_FCC_SUMMARY_03_Provider_Tables_Block20.R",
#'   subtask = 2,
#'   status = "COMPLETED",
#'   items_completed = 100
#' )
#'
#' # By stage number and task number
#' update_subtask(8, 3, subtask = 1, status = "COMPLETED")
#'
#' # By stage name and task name
#' update_subtask(
#'   stage = "STATIC",
#'   task = "TIGER_Census_Blocks",
#'   subtask = 1,
#'   items_total = 3235,
#'   percent = 50
#' )
#' }
update_subtask <- function(stage,
                           task,
                           subtask,
                           status = c("RUNNING", "COMPLETED", "FAILED", "SKIPPED"),
                           percent = NULL,
                           items_total = NULL,
                           items_completed = NULL,
                           message = NULL,
                           error_message = NULL,
                           quiet = FALSE,
                           conn = NULL,
                           filename) {
  ensure_configured()
  
  # Validate status parameter
  status <- match.arg(status)

  # If subtask is a character, we need to look it up by name
  subtask_number <- NULL
  if (is.character(subtask)) {
    # Will look up by name later
    subtask_name <- subtask
  } else {
    subtask_number <- as.integer(subtask)
    subtask_name <- NULL
  }

  # Get connection from context if available, otherwise create one
  close_on_exit <- FALSE
  if (is.null(conn)) {
    run_id_context <- tasker_context()
    if (!is.null(run_id_context)) {
      conn <- get_connection(run_id_context)
    }
    if (is.null(conn)) {
      conn <- get_db_connection()
      close_on_exit <- TRUE
    }
  }

  on.exit({
    if (close_on_exit && !is.null(conn)) {
      DBI::dbDisconnect(conn)
    }
  })

  stages_table <- get_table_name("stages", conn)
  tasks_table <- get_table_name("tasks", conn)
  task_runs_table <- get_table_name("task_runs", conn)
  subtask_progress_table <- get_table_name("subtask_progress", conn)

  # Priority 1: If filename is provided, use it to find the task (no stage needed)
  task_id <- NULL
  stage_id <- NULL
  
  if (!missing(filename)) {
    filename_matches <- DBI::dbGetQuery(
      conn,
      glue::glue_sql(
        "SELECT t.task_id, t.stage_id, t.task_name, t.script_filename FROM {tasks_table} t
         WHERE UPPER(t.script_filename) LIKE UPPER({paste0('%', as.character(filename), '%')})
         ORDER BY t.task_id",
        .con = conn
      )
    )
    
    if (nrow(filename_matches) == 0) {
      stop("Script filename '", filename, "' not found in any task.", call. = FALSE)
    }
    
    if (nrow(filename_matches) > 1) {
      match_display <- sapply(1:nrow(filename_matches), function(i) {
        name <- filename_matches$task_name[i]
        file <- filename_matches$script_filename[i]
        if (is.na(file) || file == "") {
          name
        } else {
          paste0(name, " (", file, ")")
        }
      })
      stop("Script filename '", filename, "' is ambiguous. Matches:\n  ",
           paste(match_display, collapse = "\n  "),
           "\nPlease be more specific.",
           call. = FALSE)
    }
    
    task_id <- filename_matches$task_id[1]
    stage_id <- filename_matches$stage_id[1]
  } else {
    # Priority 2: Use stage and task to find the task
    if (missing(stage) || missing(task)) {
      stop("Either provide 'filename' or both 'stage' and 'task' parameters.", call. = FALSE)
    }
    
    # Resolve stage by number or name
    if (is.numeric(stage)) {
      stage_order <- as.integer(stage)
      stage_result <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT stage_id, stage_name FROM {stages_table} WHERE stage_order = {stage_order}", .con = conn)
      )
      if (nrow(stage_result) == 0) {
        stop("Stage number ", stage_order, " not found.", call. = FALSE)
      }
      stage_id <- stage_result$stage_id[1]
    } else {
      stage_matches <- DBI::dbGetQuery(
        conn,
        glue::glue_sql(
          "SELECT stage_id, stage_name FROM {stages_table}
           WHERE UPPER(stage_name) LIKE UPPER({paste0('%', stage, '%')})
           ORDER BY stage_order",
          .con = conn
        )
      )
      
      if (nrow(stage_matches) == 0) {
        all_stages <- DBI::dbGetQuery(conn, glue::glue_sql("SELECT stage_name FROM {stages_table} ORDER BY stage_order", .con = conn))
        stop("Stage '", stage, "' not found.\n",
             "Available stages:\n  ",
             paste(all_stages$stage_name, collapse = "\n  "),
             call. = FALSE)
      }
      
      if (nrow(stage_matches) > 1) {
        stop("Stage '", stage, "' is ambiguous. Matches:\n  ",
             paste(stage_matches$stage_name, collapse = "\n  "),
             "\nPlease be more specific.",
             call. = FALSE)
      }
      
      stage_id <- stage_matches$stage_id[1]
    }
    
    # Resolve task by number or name
    if (is.numeric(task)) {
      task_order <- as.integer(task)
      task_result <- DBI::dbGetQuery(
        conn,
        glue::glue_sql(
          "SELECT t.task_id, t.task_name FROM {tasks_table} t
           WHERE t.stage_id = {stage_id} AND t.task_order = {task_order}",
          .con = conn
        )
      )
      if (nrow(task_result) == 0) {
        stop("Task number ", task_order, " not found in this stage.", call. = FALSE)
      }
      task_id <- task_result$task_id[1]
    } else {
      task_matches <- DBI::dbGetQuery(
        conn,
        glue::glue_sql(
          "SELECT t.task_id, t.task_name, t.script_filename FROM {tasks_table} t
           JOIN {stages_table} s ON t.stage_id = s.stage_id
           WHERE s.stage_id = {stage_id}
           AND (UPPER(t.task_name) LIKE UPPER({paste0('%', task, '%')}) 
                OR UPPER(t.script_filename) LIKE UPPER({paste0('%', task, '%')}))
           ORDER BY t.task_order",
          .con = conn
        )
      )
      
      if (nrow(task_matches) == 0) {
        available_tasks <- DBI::dbGetQuery(
          conn,
          glue::glue_sql(
            "SELECT t.task_name FROM {tasks_table} t
             JOIN {stages_table} s ON t.stage_id = s.stage_id
             WHERE s.stage_id = {stage_id}
             ORDER BY t.task_order",
            .con = conn
          )
        )
        
        if (nrow(available_tasks) == 0) {
          stop("No tasks found in this stage", call. = FALSE)
        }
        
        stop("Task '", task, "' not found.\n",
             "Available tasks:\n  ",
             paste(available_tasks$task_name, collapse = "\n  "),
             call. = FALSE)
      }
      
      if (nrow(task_matches) > 1) {
        match_display <- sapply(1:nrow(task_matches), function(i) {
          name <- task_matches$task_name[i]
          file <- task_matches$script_filename[i]
          if (is.na(file) || file == "") {
            name
          } else {
            paste0(name, " (", file, ")")
          }
        })
        stop("Task '", task, "' is ambiguous. Matches:\n  ",
             paste(match_display, collapse = "\n  "),
             "\nPlease be more specific.",
             call. = FALSE)
      }
      
      task_id <- task_matches$task_id[1]
    }
  }

  # Look up the most recent run_id
  tryCatch({
    result <- DBI::dbGetQuery(
      conn,
      glue::glue_sql(
        "SELECT tr.run_id
         FROM {task_runs_table} tr
         JOIN {tasks_table} t ON tr.task_id = t.task_id
         JOIN {stages_table} s ON t.stage_id = s.stage_id
         WHERE s.stage_id = {stage_id}
         AND t.task_id = {task_id}
         ORDER BY tr.start_time DESC
         LIMIT 1",
        .con = conn
      )
    )

    if (nrow(result) == 0) {
      stop("No task runs found for this stage/task combination", call. = FALSE)
    }

    run_id <- result$run_id[1]

    # If subtask name provided, look it up
    if (!is.null(subtask_name)) {
      subtask_result <- DBI::dbGetQuery(
        conn,
        glue::glue_sql(
          "SELECT subtask_number
           FROM {subtask_progress_table}
           WHERE run_id = {run_id}
           AND subtask_name = {subtask_name}",
          .con = conn
        )
      )

      if (nrow(subtask_result) == 0) {
        # Subtask name not found - show available subtasks
        available_subtasks <- DBI::dbGetQuery(
          conn,
          glue::glue_sql(
            "SELECT subtask_number, subtask_name
             FROM {subtask_progress_table}
             WHERE run_id = {run_id}
             ORDER BY subtask_number",
            .con = conn
          )
        )
        
        if (nrow(available_subtasks) == 0) {
          stop("No subtasks found for task '", task, "'", call. = FALSE)
        }
        
        subtask_list <- paste(sprintf("%d: %s", available_subtasks$subtask_number,
                                     available_subtasks$subtask_name),
                             collapse = "\n  ")
        stop("Subtask '", subtask_name, "' not found.\n",
             "Available subtasks:\n  ",
             subtask_list,
             call. = FALSE)
      }
      subtask_number <- subtask_result$subtask_number[1]
    } else {
      # Validate subtask number exists
      check_subtask <- DBI::dbGetQuery(
        conn,
        glue::glue_sql(
          "SELECT subtask_number, subtask_name
           FROM {subtask_progress_table}
           WHERE run_id = {run_id}
           AND subtask_number = {subtask_number}",
          .con = conn
        )
      )
      
      if (nrow(check_subtask) == 0) {
        # Subtask number not found - show available subtasks
        available_subtasks <- DBI::dbGetQuery(
          conn,
          glue::glue_sql(
            "SELECT subtask_number, subtask_name
             FROM {subtask_progress_table}
             WHERE run_id = {run_id}
             ORDER BY subtask_number",
            .con = conn
          )
        )
        
        if (nrow(available_subtasks) == 0) {
          stop("No subtasks found for task '", task, "'", call. = FALSE)
        }
        
        subtask_list <- paste(sprintf("%d: %s", available_subtasks$subtask_number,
                                     available_subtasks$subtask_name),
                             collapse = "\n  ")
        stop("Subtask ", subtask_number, " not found.\n",
             "Available subtasks:\n  ",
             subtask_list,
             call. = FALSE)
      }
    }

    # Update items_total if provided (this requires direct SQL update)
    if (!is.null(items_total)) {
      DBI::dbExecute(
        conn,
        glue::glue_sql(
          "UPDATE {subtask_progress_table}
           SET items_total = {as.integer(items_total)}
           WHERE run_id = {run_id}
           AND subtask_number = {subtask_number}",
          .con = conn
        )
      )
    }

    # Update the subtask progress using subtask_update
    subtask_update(
      status = if (is.null(status)) "RUNNING" else status,
      percent = percent,
      items_complete = items_completed,
      message = message,
      error_message = error_message,
      quiet = quiet,
      conn = conn,
      run_id = run_id,
      subtask_number = subtask_number
    )

    TRUE

  }, error = function(e) {
    stop("Failed to update subtask progress: ", conditionMessage(e), call. = FALSE)
  })
}
