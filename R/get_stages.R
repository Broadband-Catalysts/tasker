#' Get all stages
#'
#' @param conn Database connection (optional)
#' @return Data frame with stages
#' @export
get_stages <- function(conn = NULL) {
  ensure_configured()
  
  close_on_exit <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  schema <- if (driver == "postgresql") config$database$schema else ""
  
  table_ref <- if (nchar(schema) > 0) {
    paste0(schema, ".stages")
  } else {
    "stages"
  }
  
  tryCatch({
    DBI::dbGetQuery(
      conn,
      sprintf("SELECT * FROM %s 
               ORDER BY stage_order, stage_name", table_ref)
    )
  }, finally = {
    if (close_on_exit) {
      DBI::dbDisconnect(conn)
    }
  })
}
