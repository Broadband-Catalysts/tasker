#' Validate and clean run_id parameter
#' @param run_id Run ID to validate
#' @return Cleaned run_id or error
#' @keywords internal
validate_run_id <- function(run_id) {
  if (is.null(run_id)) {
    return(NULL)
  }
  
  if (!is.character(run_id) || length(run_id) != 1 || nchar(trimws(run_id)) == 0) {
    tasker_error("'run_id' must be a non-empty character string")
  }
  
  # Basic UUID format validation
  uuid_pattern <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  if (!grepl(uuid_pattern, run_id, ignore.case = TRUE)) {
    warning("'run_id' does not appear to be a valid UUID format", call. = FALSE)
  }
  
  trimws(run_id)
}
