#' Get the filename of the currently executing script
#'
#' Uses the this.path package to detect the script filename, which handles
#' various execution contexts (Rscript, source, RStudio, R CMD BATCH, etc.).
#'
#' @return Character string with script filename (basename only), or NULL if
#'   script cannot be detected (e.g., interactive session)
#' @export
#'
#' @examples
#' \dontrun{
#' # When running 03_ANNUAL_SEPT_01_Road_Lengths.R:
#' get_script_filename()
#' # Returns: "03_ANNUAL_SEPT_01_Road_Lengths.R"
#' }
get_script_filename <- function() {
  
  # Method 1: Check command line arguments (most reliable for Rscript)
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    return(basename(script_path))
  }
  
  # Method 2: Try this.path package for other execution contexts (source, RStudio, etc.)
  tryCatch({
    script_path <- this.path::this.path()
    if (!is.null(script_path) && !is.na(script_path) && nchar(script_path) > 0) {
      filename <- basename(script_path)
      # Skip if we're detecting our own function file
      if (filename != "get_script_filename.R") {
        return(filename)
      }
    }
  }, error = function(e) {
    # Continue to fallback method
  })
  
  # Return NULL if script cannot be detected
  return(NULL)
}


#' Look up task information by script filename
#'
#' Queries the tasker database to find the stage and task name associated
#' with a given script filename.
#'
#' @param script_filename Script filename (basename only)
#' @param conn Database connection (optional)
#'
#' @return List with `stage`, `task`, and `task_id`, or NULL if not found
#' @export
#'
#' @examples
#' \dontrun{
#' lookup_task_by_script("03_ANNUAL_SEPT_01_Road_Lengths.R")
#' # Returns: list(stage = "ANNUAL_SEPT", task = "Road Lengths", task_id = 42)
#' }
lookup_task_by_script <- function(script_filename, conn = NULL) {
  
  if (is.null(script_filename) || nchar(script_filename) == 0) {
    return(NULL)
  }
  
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  on.exit({
    if (close_on_exit && !is.null(conn) && DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
  tasks_table <- get_table_name("tasks", conn)
  stages_table <- get_table_name("stages", conn)
  
  tryCatch({
    result <- DBI::dbGetQuery(
      conn,
      glue::glue_sql(
        "SELECT s.stage_name, t.task_name, t.task_id
         FROM {`tasks_table`} t 
         JOIN {`stages_table`} s ON t.stage_id = s.stage_id
         WHERE t.script_filename = {script_filename}",
        .con = conn,
        tasks_table = tasks_table,
        stages_table = stages_table
      )
    )
    
    if (nrow(result) == 0) {
      return(NULL)
    }
    
    if (nrow(result) > 1) {
      warning("Multiple tasks found for script '", script_filename, 
              "'. Using first match: ", result$stage_name[1], " / ", result$task_name[1])
    }
    
    return(list(
      stage = result$stage_name[1],
      task = result$task_name[1],
      task_id = result$task_id[1]
    ))
    
  }, error = function(e) {
    warning("Failed to lookup task by script filename: ", conditionMessage(e))
    return(NULL)
  })
}
