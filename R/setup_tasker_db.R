#' Initialize tasker Database Schema
#'
#' Creates the necessary PostgreSQL schema and tables for tasker.
#' This function should be run once to set up the database.
#' 
#' SAFETY FEATURES:
#' - Uses transactions to rollback on failure
#' - Preserves existing data by backing up to {schema}_backup
#' - Only drops backup after successful migration
#'
#' @param conn Optional database connection. If NULL, uses connection from config.
#' @param schema_name Name of the schema to create (default: "tasker")
#' @param force If TRUE, recreates schema while preserving existing data via backup
#' @param skip_backup If TRUE, skips data backup (USE WITH CAUTION)
#' @param keep_backup If TRUE, keeps backup schema after successful migration
#' @param schema_sql_file Optional path to a schema SQL script (used mainly for testing)
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
#' # Force recreate (backs up existing data first!)
#' setup_tasker_db(force = TRUE)
#' 
#' # Force recreate and keep backup for manual inspection
#' setup_tasker_db(force = TRUE, keep_backup = TRUE)
#' }
setup_tasker_db <- function(conn = NULL, schema_name = "tasker", force = FALSE, skip_backup = FALSE, keep_backup = FALSE, schema_sql_file = NULL, quiet = FALSE) {
  close_conn <- FALSE
  
  # Warn about dangerous skip_backup option
  if (skip_backup && force) {
    warning("=== DANGER: skip_backup=TRUE ===", immediate. = TRUE)
    warning("This will PERMANENTLY DELETE existing schema data without backup!", immediate. = TRUE)
    warning("Only do this if you are absolutely sure you want to lose all existing data.", immediate. = TRUE)
    
    if (interactive()) {
      response <- readline(prompt = "Type 'DELETE' to confirm permanent deletion: ")
      if (response != "DELETE") {
        message("Operation cancelled by user.")
        return(FALSE)
      }
    } else {
      # In non-interactive mode, require explicit confirmation via option
      if (!isTRUE(getOption("tasker.confirm_skip_backup"))) {
        stop("Non-interactive skip_backup=TRUE requires: options(tasker.confirm_skip_backup = TRUE)")
      }
    }
  }
  
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
  
  # Get driver type and schema from config
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  # Use schema from config if schema_name not explicitly provided
  # The parameter default is "tasker", but if config has a different schema, use that
  if (schema_name == "tasker" && !is.null(config$database$schema) && config$database$schema != "") {
    schema_name <- config$database$schema
  }
  
  backup_schema <- paste0(schema_name, "_backup")
  
  tryCatch({
    if (driver == "postgresql") {
      # PostgreSQL-specific setup with transaction safety
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
        if (!skip_backup) {
          message("=== BACKUP PHASE ===")
          message("Preserving existing data in backup schema: ", backup_schema)
          
          # Drop any existing backup schema
          backup_exists <- DBI::dbGetQuery(
            conn,
            glue::glue_sql("SELECT EXISTS(SELECT 1 FROM information_schema.schemata 
                            WHERE schema_name = {backup_schema})", .con = conn)
          )[[1]]
          
          if (backup_exists) {
            message("Removing old backup schema...")
            DBI::dbExecute(conn, paste0("DROP SCHEMA ", backup_schema, " CASCADE"))
          }
          
          # Rename existing schema to backup
          message("Renaming existing schema to backup...")
          DBI::dbExecute(conn, glue::glue_sql("ALTER SCHEMA {`schema_name`} RENAME TO {`backup_schema`}", .con = conn))
        } else {
          warning("SKIPPING BACKUP - Dropping existing schema '", schema_name, "' and all its data!")
          DBI::dbExecute(conn, paste0("DROP SCHEMA ", schema_name, " CASCADE"))
        }
      }
      
      # Start transaction for schema creation
      message("=== SCHEMA CREATION PHASE ===")
      DBI::dbBegin(conn)
      
      tryCatch({
        message("Creating new schema '", schema_name, "'...")
        DBI::dbExecute(conn, paste0("CREATE SCHEMA ", schema_name))

        # Execute combined schema (includes reporter tables and all views)
        sql_file <- if (!is.null(schema_sql_file)) {
          schema_sql_file
        } else {
          system.file("sql", "postgresql", "create_schema.sql", package = "tasker")
        }
        if (!file.exists(sql_file)) {
          stop("SQL schema file not found: ", sql_file)
        }

        message("Executing schema creation SQL...")

        # For PostgreSQL we need to ensure process-reporter tables exist before
        # views that reference them. The canonical create_schema.sql contains
        # table definitions and views; to guarantee ordering we split the file
        # at the "-- Views for easier querying" marker (if present), execute
        # the pre-view portion, then execute the reporter_schema (if
        # present), and finally execute the remaining views portion.
        if (driver == "postgresql") {
          sql_text <- paste(readLines(sql_file, warn = FALSE), collapse = "\n")
          
          # Replace hardcoded 'tasker' schema with actual schema name
          if (schema_name != "tasker") {
            sql_text <- gsub("\\btasker\\.", paste0(schema_name, "."), sql_text)
            sql_text <- gsub("schema_name = 'tasker'", paste0("schema_name = '", schema_name, "'"), sql_text)
            sql_text <- gsub('schema_name = "tasker"', paste0('schema_name = "', schema_name, '"'), sql_text)
          }
          
          split_marker <- "-- Views for easier querying"
          if (grepl(split_marker, sql_text, fixed = TRUE)) {
            parts <- strsplit(sql_text, split_marker, fixed = TRUE)[[1]]
            pre_views <- parts[1]
            post_views <- paste0(split_marker, parts[2])

            tmp_pre <- tempfile(fileext = ".sql")
            tmp_post <- tempfile(fileext = ".sql")
            writeLines(pre_views, tmp_pre)
            writeLines(post_views, tmp_post)

            # Execute pre-views (creates task_runs, etc.)
            bbcDB::dbExecuteScript(conn, tmp_pre, .open = "", .close = "", .quiet = FALSE)

            # Execute reporter schema if present
            proc_file <- system.file("sql", "postgresql", "reporter_schema.sql", package = "tasker")
            if (file.exists(proc_file) && nzchar(proc_file)) {
              # Also replace schema name in reporter schema
              reporter_sql <- paste(readLines(proc_file, warn = FALSE), collapse = "\n")
              if (schema_name != "tasker") {
                reporter_sql <- gsub("\\btasker\\.", paste0(schema_name, "."), reporter_sql)
                reporter_sql <- gsub("schema_name = 'tasker'", paste0("schema_name = '", schema_name, "'"), reporter_sql)
                reporter_sql <- gsub('schema_name = "tasker"', paste0('schema_name = "', schema_name, '"'), reporter_sql)
              }
              tmp_reporter <- tempfile(fileext = ".sql")
              writeLines(reporter_sql, tmp_reporter)
              bbcDB::dbExecuteScript(conn, tmp_reporter, .open = "", .close = "", .quiet = FALSE)
              try(file.remove(tmp_reporter), silent = TRUE)
            }

            # Execute remaining views
            bbcDB::dbExecuteScript(conn, tmp_post, .open = "", .close = "", .quiet = FALSE)

            # Clean up temp files
            try(file.remove(tmp_pre, tmp_post), silent = TRUE)
          } else {
            # Fallback: execute the file as-is
            bbcDB::dbExecuteScript(conn, sql_file, .open = "", .close = "", .quiet = FALSE)
          }
        } else {
          bbcDB::dbExecuteScript(conn, sql_file, .open = "", .close = "", .quiet = FALSE)
        }
        
        # If backup exists, migrate data
        if (!skip_backup && DBI::dbGetQuery(
          conn, 
          glue::glue_sql("SELECT EXISTS(SELECT 1 FROM information_schema.schemata 
                          WHERE schema_name = {backup_schema})", .con = conn)
        )[[1]]) {
          message("=== DATA MIGRATION PHASE ===")
          
          # List of tables to migrate in dependency order
          tables_to_migrate <- c("stages", "tasks", "task_runs", "subtask_progress")
          
          for (table in tables_to_migrate) {
            backup_table_exists <- DBI::dbGetQuery(
              conn,
              glue::glue_sql("SELECT EXISTS(SELECT 1 FROM information_schema.tables 
                              WHERE table_schema = {backup_schema} AND table_name = {table})", .con = conn)
            )[[1]]
            
            if (backup_table_exists) {
              message("Migrating data from ", backup_schema, ".", table, " to ", schema_name, ".", table)
              
              # Get column names that exist in both schemas
              backup_cols <- DBI::dbGetQuery(
                conn,
                glue::glue_sql("SELECT column_name FROM information_schema.columns 
                                WHERE table_schema = {backup_schema} AND table_name = {table} 
                                ORDER BY ordinal_position", .con = conn)
              )$column_name
              
              new_cols <- DBI::dbGetQuery(
                conn,
                glue::glue_sql("SELECT column_name FROM information_schema.columns 
                                WHERE table_schema = {schema_name} AND table_name = {table} 
                                ORDER BY ordinal_position", .con = conn)
              )$column_name
              
              # Find common columns
              common_cols <- intersect(backup_cols, new_cols)
              
              if (length(common_cols) > 0) {
                cols_str <- paste(common_cols, collapse = ", ")
                insert_sql <- glue::glue_sql("INSERT INTO {`schema_name`}.{`table`} ({`cols_str`*}) 
                                            SELECT {`cols_str`*} FROM {`backup_schema`}.{`table`}",
                                           .con = conn, cols_str = common_cols)
                
                count_before <- DBI::dbGetQuery(conn, glue::glue_sql("SELECT COUNT(*) as n FROM {`backup_schema`}.{`table`}", .con = conn))$n
                
                DBI::dbExecute(conn, insert_sql)
                
                count_after <- DBI::dbGetQuery(conn, glue::glue_sql("SELECT COUNT(*) as n FROM {`schema_name`}.{`table`}", .con = conn))$n
                
                message("  Migrated ", count_after, " rows (", count_before, " in backup)")
                
                if (count_after != count_before) {
                  warning("Row count mismatch for table ", table, ": ", count_before, " -> ", count_after)
                }
              } else {
                warning("No common columns found for table ", table, " - skipping data migration")
              }
            } else {
              message("Table ", table, " does not exist in backup - skipping")
            }
          }
        }
        
        # Commit transaction
        DBI::dbCommit(conn)
        message("=== SUCCESS ===")
        message("✓ Schema creation completed successfully")
        
        # Clean up backup schema on success
        if (!skip_backup && DBI::dbGetQuery(
          conn, 
          glue::glue_sql("SELECT EXISTS(SELECT 1 FROM information_schema.schemata 
                          WHERE schema_name = {backup_schema})", .con = conn)
        )[[1]]) {
          
          if (!keep_backup) {
            message("Cleaning up backup schema...")
            DBI::dbExecute(conn, paste0("DROP SCHEMA ", backup_schema, " CASCADE"))
            message("✓ Backup schema removed")
            message("✓ Schema migration completed successfully")
          } else {
            message("✓ Backup schema preserved for manual management")
            
            # Print backup management information
            message("\n=== BACKUP SCHEMA MANAGEMENT ===")
            message("Backup schema '", backup_schema, "' has been preserved.")
            message("You can manage it with these SQL commands:")
            message("")
            message("📋 To restore from backup (replace current schema):")
            message("   DROP SCHEMA ", schema_name, " CASCADE;")
            message("   ALTER SCHEMA ", backup_schema, " RENAME TO ", schema_name, ";")
            message("")
            message("🔍 To inspect backup schema:")
            message("   SELECT * FROM ", backup_schema, ".stages;")
            message("   SELECT * FROM ", backup_schema, ".tasks;") 
            message("   SELECT * FROM ", backup_schema, ".task_runs;")
            message("")
            message("🗑️ To delete backup schema (when no longer needed):")
            message("   DROP SCHEMA ", backup_schema, " CASCADE;")
          }
        } else if (!skip_backup) {
          # No backup was created or found
          message("\n=== BACKUP SCHEMA MANAGEMENT ===")
          message("No backup schema was created (schema may have been empty).")
        } else {
          # Backup was skipped
          message("\n=== BACKUP SCHEMA MANAGEMENT ===") 
          message("⚠️ Backup was skipped - original data was destroyed!")
          message("No backup available for restoration.")
        }
        
      }, error = function(e) {
        # Rollback transaction on error
        message("=== ROLLBACK ===")
        DBI::dbRollback(conn)
        
        # If backup exists, restore it
        if (!skip_backup && DBI::dbGetQuery(
          conn, 
          glue::glue_sql("SELECT EXISTS(SELECT 1 FROM information_schema.schemata 
                          WHERE schema_name = {backup_schema})", .con = conn)
        )[[1]]) {
          message("Restoring from backup...")
          
          # Drop failed new schema
          schema_exists_new <- DBI::dbGetQuery(
            conn,
            glue::glue_sql("SELECT EXISTS(SELECT 1 FROM information_schema.schemata 
                            WHERE schema_name = {schema_name})", .con = conn)
          )[[1]]
          
          if (schema_exists_new) {
            DBI::dbExecute(conn, paste0("DROP SCHEMA ", schema_name, " CASCADE"))
          }
          
          # Restore backup
          DBI::dbExecute(conn, glue::glue_sql("ALTER SCHEMA {`backup_schema`} RENAME TO {`schema_name`}", .con = conn))
          message("✓ Original schema restored from backup")
          
          message("\n=== BACKUP SCHEMA MANAGEMENT ===")
          message("Schema creation failed but original data was preserved and restored.")
          message("Your original schema is intact and functional.")
        }
        
        stop("Schema creation failed: ", e$message)
      })
      
    } else if (driver == "sqlite") {
      # SQLite-specific setup
      if (!quiet) message("Creating SQLite schema...")
      DBI::dbBegin(conn)

      tryCatch({
        # If a custom schema SQL file is supplied, validate it in an isolated in-memory DB
        # and explicitly verify that any created views are selectable. This prevents
        # applying broken view definitions to the real DB (which could otherwise
        # succeed at CREATE VIEW time but fail later when used).
        if (!is.null(schema_sql_file)) {
          if (!quiet) message("Validating provided schema SQL before applying to database...")
          tmp_con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          on.exit({
            try(DBI::dbDisconnect(tmp_con), silent = TRUE)
          }, add = TRUE)

          # Run SQL in-memory to ensure it parses/executes
          bbcDB::dbExecuteScript(tmp_con, schema_sql_file, .open = "", .close = "", .quiet = TRUE)

          # Find any CREATE VIEW statements in the file and verify they are usable
          sql_text <- paste(readLines(schema_sql_file, warn = FALSE), collapse = "\n")
          # Regex to capture view names after CREATE VIEW [IF NOT EXISTS]
          view_matches <- gregexpr("CREATE\\s+VIEW\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?([A-Za-z0-9_]+)", sql_text, perl = TRUE, ignore.case = TRUE)
          view_names <- character()
          if (length(view_matches) && view_matches[[1]][1] != -1) {
            m <- view_matches[[1]]
            for (i in seq_along(m)) {
              start <- m[i]
              len <- attr(m, "match.length")[i]
              matched <- substr(sql_text, start, start + len - 1)
              # Extract the view name from the capture group
              nm <- sub("(?i)CREATE\\s+VIEW\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?", "", matched, perl = TRUE)
              nm <- gsub("\\s", "", nm)
              nm <- gsub("\r|\n", "", nm)
              if (nzchar(nm)) view_names <- c(view_names, nm)
            }
          }

          # Try selecting from each view to ensure referenced tables exist.
          for (vw in unique(view_names)) {
            tryCatch({
              DBI::dbGetQuery(tmp_con, paste0("SELECT 1 FROM ", vw, " LIMIT 1"))
            }, error = function(e) {
              stop("Validation failed for view '", vw, "': ", e$message)
            })
          }

          if (!quiet) message("Validation passed")
        }

        if (force) {
          if (!quiet) warning("Dropping existing SQLite tables and recreating!")
          tables <- c(
            "process_metrics_retention",
            "reporter_status",
            "process_metrics",
            "subtask_progress",
            "task_runs",
            "tasks",
            "stages"
          )
          for (tbl in tables) {
            DBI::dbExecute(conn, paste0("DROP TABLE IF EXISTS ", tbl))
          }
          views <- c(
            "task_runs_with_latest_metrics",
            "current_task_status_with_metrics",
            "active_tasks",
            "current_task_status"
          )
          for (v in views) {
            DBI::dbExecute(conn, paste0("DROP VIEW IF EXISTS ", v))
          }
        }

        sql_file <- if (!is.null(schema_sql_file)) {
          schema_sql_file
        } else {
          system.file("sql", "sqlite", "create_schema.sql", package = "tasker")
        }
        if (!file.exists(sql_file)) {
          stop("SQL schema file not found: ", sql_file)
        }

        if (!quiet) message("Executing schema creation SQL...")
        bbcDB::dbExecuteScript(conn, sql_file, .open = "", .close = "", .quiet = quiet)

        DBI::dbCommit(conn)
      }, error = function(e) {
        # Only rollback if a transaction is active
        if (DBI::dbIsValid(conn)) {
          # RSQLite doesn't have dbIsTransaction(), so use tryCatch
          tryCatch(DBI::dbRollback(conn), error = function(rollback_err) {
            # Transaction may already be rolled back or not started
            NULL
          })
        }
        stop(e)
      })
      
    } else {
      stop("Unsupported database driver: ", driver)
    }
    
    if (!quiet) message("✓ tasker database schema created successfully")
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
  
  config <- getOption("tasker.config")
  driver <- config$database$driver
  
  # Check for required tables
  required_tables <- c("stages", "tasks", "task_runs", "subtask_progress", "process_metrics")
  
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

#' Check if all tasker tables exist
#'
#' Verifies that all required database tables exist (both main tasker tables
#' and reporter tables).
#'
#' @param conn Database connection. If NULL, uses default tasker connection
#' @param driver Database driver type ("sqlite" or "postgresql"). If NULL, uses config
#'
#' @return TRUE if all tables exist, FALSE otherwise
#' @export
#'
#' @examples
#' \dontrun{
#' con <- get_tasker_db_connection()
#' if (!check_tasker_tables_exist(con)) {
#'   setup_tasker_db()
#' }
#' }
check_tasker_tables_exist <- function(conn = NULL, driver = NULL) {
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
  
  if (is.null(driver)) {
    config <- get_tasker_config()
    driver <- config$database$driver
  }
  
  # All required tables (main tasker + reporter)
  required_tables <- c(
    "stages", "tasks", "task_runs", "subtask_progress",
    "process_metrics", "reporter_status", "process_metrics_retention"
  )
  
  if (driver == "sqlite") {
    # SQLite: check sqlite_master table
    existing_tables <- DBI::dbGetQuery(conn, "
      SELECT name FROM sqlite_master 
      WHERE type = 'table' AND name IN ('stages', 'tasks', 'task_runs', 'subtask_progress', 
                                         'process_metrics', 'reporter_status', 'process_metrics_retention')
    ")$name
  } else {
    # PostgreSQL: check information_schema
    schema_name <- get_tasker_config()$schema %||% "tasker"
    existing_tables <- DBI::dbGetQuery(conn, "
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = $1 AND table_name IN ('stages', 'tasks', 'task_runs', 'subtask_progress',
                                                  'process_metrics', 'reporter_status', 'process_metrics_retention')
    ", params = list(schema_name))$table_name
  }
  
  return(length(intersect(required_tables, existing_tables)) == length(required_tables))
}
