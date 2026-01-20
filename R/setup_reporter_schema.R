#' Setup Reporter Database Schema
#'
#' Creates database tables, indexes, and views for the Reporter system.
#' This function sets up all required database objects to support process metrics
#' collection and retention management.
#'
#' @param conn Database connection. If NULL, uses default tasker connection
#' @param force Recreate tables if they already exist (default: FALSE)
#' @param quiet Suppress progress messages (default: FALSE)
#'
#' @return TRUE if setup successful, FALSE otherwise
#' @export
#'
#' @examples
#' \dontrun{
#' # Setup reporter schema
#' setup_reporter_schema()
#' 
#' # Force recreation of existing tables
#' setup_reporter_schema(force = TRUE)
#' }
setup_reporter_schema <- function(conn = NULL, force = FALSE, quiet = FALSE) {
  
  if (is.null(conn)) {
    conn <- get_tasker_db_connection()
    close_conn <- TRUE
    on.exit({
      if (close_conn && !is.null(conn) && DBI::dbIsValid(conn)) {
        DBI::dbDisconnect(conn)
      }
    })
  } else {
    close_conn <- FALSE
  }
  
  config <- get_tasker_config()
  driver <- config$database$driver
  
  if (!quiet) {
    message("[Reporter] Setting up database schema for ", driver)
  }
  
  # Determine schema file based on database driver
  if (driver == "sqlite") {
    # Use consolidated create_schema for SQLite to ensure view/table ordering
    schema_file <- system.file("sql/sqlite/create_schema.sql", package = "tasker")
  } else {
    schema_file <- system.file("sql/postgresql/reporter_schema.sql", package = "tasker")
  }
  
  if (!file.exists(schema_file)) {
    stop("Schema file not found: ", schema_file)
  }
  
  tryCatch({
    # Check if tables already exist
    tables_exist <- check_reporter_tables_exist(conn, driver)
    
    if (tables_exist && !force) {
      if (!quiet) {
        message("[Reporter] Tables already exist, skipping setup (use force = TRUE to recreate)")
      }
      return(TRUE)
    }
    
    if (force && tables_exist) {
      if (!quiet) {
        message("[Reporter] Dropping existing tables")
      }
      drop_reporter_tables(conn, driver)
    }
    
    # Execute schema file
    if (!quiet) {
      message("[Reporter] Creating tables and indexes")
    }
    
    bbcDB::dbExecuteScript(conn, schema_file, .open = "", .close = "", .quiet = quiet)

    # Verify tables were created
    if (!check_reporter_tables_exist(conn, driver)) {
      stop("Reporter tables were not created successfully")
    }

    if (!quiet) {
      message("[Reporter] Schema setup complete")
    }

    return(TRUE)

  }, error = function(e) {
    if (!quiet) {
      warning("[Reporter] Schema setup failed: ", e$message)
    }
    stop(e)
  })
}

#' Check if Reporter Tables Exist
#'
#' @param conn Database connection
#' @param driver Database driver type
#' @return TRUE if all required tables exist
#' @keywords internal
drop_reporter_tables <- function(conn, driver) {
  if (driver == "sqlite") {
    tables_to_drop <- c("process_metrics_retention", "process_metrics", "reporter_status")
  } else {
    schema_name <- get_tasker_config()$schema %||% "tasker"
    tables_to_drop <- paste0(schema_name, ".", c("process_metrics_retention", "process_metrics", "reporter_status"))
  }
  
  for (table in tables_to_drop) {
    tryCatch({
      if (driver == "sqlite") {
        DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", table))
      } else {
        DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", table, "CASCADE"))
      }
    }, error = function(e) {
      # Continue if table doesn't exist
    })
  }
  
  # Drop views if they exist
  if (driver == "sqlite") {
    DBI::dbExecute(conn, "DROP VIEW IF EXISTS task_runs_with_latest_metrics")
  } else {
    schema_name <- get_tasker_config()$schema %||% "tasker"
    DBI::dbExecute(conn, paste("DROP VIEW IF EXISTS", schema_name, ".task_runs_with_latest_metrics CASCADE"))
  }
}