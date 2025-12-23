#' Get all tasks (alias for get_task_status)
#'
#' @param ... Arguments passed to get_task_status
#' @return Data frame with task status
#' @export
#'
#' @examples
#' \dontrun{
#' get_tasks()
#' }
get_tasks <- function(...) {
  get_task_status(...)
}
