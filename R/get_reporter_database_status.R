#' Get reporter database status
#'
#' Checks if a reporter is running on a specific host.
#'
#' @param hostname Check specific host (NULL = current host)
#' @param con Database connection (NULL = get default)
#'
#' @return Data frame with reporter status or NULL if not running
#' @export
get_reporter_database_status <- function(hostname = NULL, con = NULL) {
  if (is.null(hostname)) hostname <- Sys.info()["nodename"]
  close_con <- FALSE
  if (is.null(con)) {
    con <- tryCatch(get_db_connection(), error = function(e) NULL)
    if (is.null(con)) return(NULL)
    close_con <- TRUE
  }
  on.exit({ if (close_con && !is.null(con)) tryCatch(DBI::dbDisconnect(con), error = function(e) NULL) })

  res <- tryCatch({
    table_name <- get_table_name("reporter_status", con, char = TRUE)
    db_class <- class(con)[1]
    placeholder <- if (db_class == "PqConnection") "$1" else "?"
    sql <- sprintf("SELECT hostname, process_id, started_at, last_heartbeat, version, shutdown_requested FROM %s WHERE hostname = %s", table_name, placeholder)
    DBI::dbGetQuery(con, sql, params = list(hostname))
  }, error = function(e) { warning("Failed to query reporter status: ", e$message); NULL })

  if (is.null(res) || nrow(res) == 0) return(NULL)
  res
}
