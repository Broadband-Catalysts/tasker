#' Atomically increment subtask item counter
#'
#' This function atomically increments the items_complete counter for a subtask.
#' Unlike subtask_update() which sets the value, this function increments it,
#' making it safe for use by parallel workers.
#'
#' @param increment Number of items to add to counter (default: 1)
#' @param quiet Suppress console messages (default: TRUE for parallel workers)
#' @param conn Database connection (optional)
#' @param run_id Run ID from task_start(), or NULL to use active context
#' @param subtask_number Subtask number, or NULL to use current subtask
#' @return TRUE on success
#'
#' @seealso [subtask_update()] to set progress values (use increment for
#'   parallel workers), [subtask_start()] to start tracking a subtask,
#'   [export_tasker_context()] to share context with parallel workers,
#'   [tasker_cluster()] for simplified parallel setup
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Old style - explicit parameters
#' subtask_increment(increment = 1, run_id = run_id, subtask_number = subtask_num)
#'
#' # New style - use context
#' subtask_increment(increment = 1)  # Uses active context and current subtask
#' }
subtask_increment <- function(increment      = 1,
                             quiet          = TRUE,
                             conn           = NULL,
                             run_id         = NULL,
                             subtask_number = NULL) {
  
  # Input validation
  if (!is.numeric(increment) || length(increment) != 1 || increment <= 0) {
    stop("'increment' must be a positive number", call. = FALSE)
  }
  
  if (!is.logical(quiet) || length(quiet) != 1) {
    stop("'quiet' must be TRUE or FALSE", call. = FALSE)
  }
  
  if (!is.null(subtask_number)) {
    if (!is.numeric(subtask_number) || length(subtask_number) != 1 || subtask_number < 1) {
      stop("'subtask_number' must be a positive integer if provided", call. = FALSE)
    }
    subtask_number <- as.integer(subtask_number)
  }
  
  ensure_configured()
  
  # Resolve run_id from context if not provided
  if (is.null(run_id)) {
    run_id <- get_active_run_id()
  }
  
  # Resolve subtask_number from current subtask if not provided
  if (is.null(subtask_number)) {
    subtask_number <- get_current_subtask(run_id)
    if (is.null(subtask_number)) {
      stop("No subtask currently active. Either pass subtask_number explicitly or start a subtask first.",
           call. = FALSE)
    }
  }
  
  # Get connection from context if available, otherwise create one
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_connection(run_id)
    if (is.null(conn)) {
      conn <- get_db_connection()
      close_on_exit <- TRUE
    }
  }
  
  config <- getOption("tasker.config")
  subtask_progress_table <- get_table_name("subtask_progress", conn)
  db_driver <- config$database$driver
  time_func <- if (db_driver == "sqlite") "datetime('now')" else "NOW()"
  
  tryCatch({
    # Atomic increment using database-level operation
    # COALESCE handles NULL case (first increment)
    # Auto-transition from STARTED to RUNNING on first progress
    # Attempt the atomic increment with retries to handle transient SQLite locking
    max_attempts <- 6L
    attempt <- 1L
    repeat {
      tryCatch({
        DBI::dbExecute(
          conn,
          glue::glue_sql(
            "UPDATE {subtask_progress_table} 
             SET items_complete = COALESCE(items_complete, 0) + {increment},
                 last_update = {time_func*},
                 status = CASE 
                   WHEN status = 'STARTED' AND COALESCE(items_complete, 0) = 0 THEN 'RUNNING'
                   ELSE status 
                 END
             WHERE run_id = {run_id} AND subtask_number = {subtask_number}",
            .con = conn
          )
        )
        break
      }, error = function(e) {
        msg <- conditionMessage(e)
        # Retry on transient SQLite locking errors
        if (grepl("database is locked", msg, ignore.case = TRUE) && attempt < max_attempts) {
          backoff <- 0.01 * (2 ^ (attempt - 1)) + runif(1, 0, 0.01)
          Sys.sleep(backoff)
          attempt <<- attempt + 1L
          invisible(NULL)
        } else {
          stop(e)
        }
      })
    }
    
    if (!quiet) {
      # Get current count for display
      current <- DBI::dbGetQuery(
        conn,
        glue::glue_sql(
          "SELECT items_complete FROM {subtask_progress_table}
           WHERE run_id = {run_id} AND subtask_number = {subtask_number}",
          .con = conn
        )
      )$items_complete[1]
      
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      message(sprintf("[%s] Subtask %d: incremented by %d (now %d)", 
                     timestamp, subtask_number, increment, current))
    }
    
    TRUE
    
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
