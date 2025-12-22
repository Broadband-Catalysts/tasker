#' Initialize tasker Database Schema
#'
#' Creates the necessary PostgreSQL schema and tables for tasker.
#' This function should be run once to set up the database.
#'
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param schema_name Name of the schema to create (default: "tasker")
#' @param force If TRUE, drops existing schema and recreates it (WARNING: destroys data)
#'
#' @return TRUE if successful
#' @export
#'
#' @examples
#' \dontrun{
#' # Initialize with default config
#' setup_tasker_db()
#'
#' # Initialize with specific connection
#' conn <- DBI::dbConnect(RPostgres::Postgres(), ...)
#' setup_tasker_db(conn)
#'
#' # Force recreate (destroys existing data!)
#' setup_tasker_db(force = TRUE)
#' }
setup_tasker_db <- function(conn = NULL, schema_name = "tasker", force = FALSE) {
  close_conn <- FALSE
  
  if (is.null(conn)) {
    ensure_configured()
    conn <- get_db_connection()
    close_conn <- TRUE
  }
  
  on.exit({
    if (close_conn) {
      DBI::dbDisconnect(conn)
    }
  })
  
  tryCatch({
    # Check if schema exists
    schema_exists <- DBI::dbGetQuery(
      conn,
      "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = $1)",
      params = list(schema_name)
    )[[1]]
    
    if (schema_exists && !force) {
      message("Schema '", schema_name, "' already exists. Use force = TRUE to recreate.")
      return(FALSE)
    }
    
    if (schema_exists && force) {
      warning("Dropping existing schema '", schema_name, "' and all its data!")
      DBI::dbExecute(conn, paste0("DROP SCHEMA ", schema_name, " CASCADE"))
    }
    
    # Create schema
    message("Creating schema '", schema_name, "'...")
    DBI::dbExecute(conn, paste0("CREATE SCHEMA IF NOT EXISTS ", schema_name))
    
    # Read and execute SQL file
    sql_file <- system.file("sql", "postgresql", "create_schema.sql", package = "tasker")
    
    if (!file.exists(sql_file)) {
      stop("SQL schema file not found: ", sql_file)
    }
    
    sql <- readLines(sql_file)
    sql <- paste(sql, collapse = "\n")
    
    message("Executing schema creation SQL...")
    DBI::dbExecute(conn, sql)
    
    message("\u2713 tasker database schema created successfully")
    return(TRUE)
    
  }, error = function(e) {
    stop("Failed to create tasker schema: ", e$message)
  })
}


#' Check if tasker Database is Initialized
#'
#' Checks whether the tasker schema and tables exist in the database.
#'
#' @param conn Optional database connection. If NULL, uses connection from config.
#'
#' @return TRUE if schema is properly initialized, FALSE otherwise
#' @export
check_tasker_db <- function(conn = NULL) {
  close_conn <- FALSE
  
  if (is.null(conn)) {
    ensure_configured()
    conn <- get_db_connection()
    close_conn <- TRUE
  }
  
  on.exit({
    if (close_conn) {
      DBI::dbDisconnect(conn)
    }
  })
  
  # Check for required tables
  required_tables <- c("stages", "tasks", "task_runs", "subtask_progress")
  
  for (table in required_tables) {
    exists <- DBI::dbExistsTable(conn, DBI::Id(schema = "tasker", table = table))
    if (!exists) {
      message("\u2717 Table tasker.", table, " does not exist")
      return(FALSE)
    }
  }
  
  message("\u2713 tasker database schema is properly initialized")
  return(TRUE)
}
