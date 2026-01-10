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
  
  # Ensure cleanup on exit
  on.exit({
    if (close_conn && !is.null(conn) && DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
  # Get driver type
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  tryCatch({
    if (driver == "postgresql") {
      # PostgreSQL-specific setup
      schema_exists <- DBI::dbGetQuery(
        conn,
        glue::glue_sql("SELECT EXISTS(SELECT 1 FROM information_schema.schemata 
                        WHERE schema_name = {schema_name})", .con = conn)
      )[[1]]
      
      if (schema_exists && !force) {
        message("Schema '", schema_name, "' already exists. Use force = TRUE to recreate.")
        return(FALSE)
      }
      
      if (schema_exists && force) {
        warning("Dropping existing schema '", schema_name, "' and all its data!")
        DBI::dbExecute(conn, paste0("DROP SCHEMA ", schema_name, " CASCADE"))
      }
      
      message("Creating schema '", schema_name, "'...")
      DBI::dbExecute(conn, paste0("CREATE SCHEMA IF NOT EXISTS ", schema_name))
      
      sql_file <- system.file("sql", "postgresql", "create_schema.sql", package = "tasker")
      
    } else if (driver == "sqlite") {
      # SQLite-specific setup
      if (force) {
        warning("Dropping existing SQLite tables and recreating!")
        tables <- c("subtask_progress", "task_runs", "tasks", "stages")
        for (tbl in tables) {
          DBI::dbExecute(conn, paste0("DROP TABLE IF EXISTS ", tbl))
        }
        views <- c("active_tasks", "current_task_status")
        for (v in views) {
          DBI::dbExecute(conn, paste0("DROP VIEW IF EXISTS ", v))
        }
      }
      
      message("Creating SQLite schema...")
      sql_file <- system.file("sql", "sqlite", "create_schema.sql", package = "tasker")
      
    } else {
      stop("Unsupported database driver: ", driver)
    }
    
    if (!file.exists(sql_file)) {
      stop("SQL schema file not found: ", sql_file)
    }
    
    message("Executing schema creation SQL...")
    
    # Use bbcDB::dbExecuteScript which handles dollar-quoted strings and BEGIN...END blocks
    # Use .open = "" to disable glue interpolation
    bbcDB::dbExecuteScript(conn, sql_file, .open = "", .close = "", .quiet = FALSE)
    
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
  
  # Ensure cleanup on exit
  on.exit({
    if (close_conn && !is.null(conn) && DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
  })
  
  on.exit({
    if (close_conn) {
      DBI::dbDisconnect(conn)
    }
  })
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  # Check for required tables
  required_tables <- c("stages", "tasks", "task_runs", "subtask_progress")
  
  for (table in required_tables) {
    if (driver == "postgresql") {
      exists <- DBI::dbExistsTable(conn, DBI::Id(schema = "tasker", table = table))
    } else {
      exists <- DBI::dbExistsTable(conn, table)
    }
    
    if (!exists) {
      message("\u2717 Table ", table, " does not exist")
      return(FALSE)
    }
  }
  
  message("\u2713 tasker database schema is properly initialized")
  return(TRUE)
}


#' Create tasker database schema (alias for setup_tasker_db)
#'
#' This function is an alias for setup_tasker_db() for backward compatibility.
#' 
#' @param conn Database connection (optional, will create if NULL)
#' @param schema Schema name (default: from config)
#' @return TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' create_schema()
#' }
create_schema <- function(conn = NULL, schema = NULL) {
  setup_tasker_db(conn = conn, schema_name = schema)
}
