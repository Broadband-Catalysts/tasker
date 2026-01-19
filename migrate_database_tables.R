#!/usr/bin/env Rscript
# Database migration script to rename process_reporter tables to reporter tables
# This script handles both PostgreSQL and SQLite databases

library(tasker)
library(DBI)

# Function to rename tables safely
rename_table_safe <- function(con, old_name, new_name, schema = NULL) {
  if (!is.null(schema)) {
    full_old_name <- paste0(schema, ".", old_name)
    full_new_name <- paste0(schema, ".", new_name)
  } else {
    full_old_name <- old_name
    full_new_name <- new_name
  }
  
  # Check if old table exists
  db_class <- class(con)[1]
  if (db_class == "PqConnection") {
    # PostgreSQL
    exists_query <- "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = $2)"
    schema_name <- if (!is.null(schema)) schema else "tasker"
    old_exists <- DBI::dbGetQuery(con, exists_query, params = list(schema_name, old_name))[[1]]
    new_exists <- DBI::dbGetQuery(con, exists_query, params = list(schema_name, new_name))[[1]]
  } else {
    # SQLite
    old_exists <- DBI::dbExistsTable(con, old_name)
    new_exists <- DBI::dbExistsTable(con, new_name)
  }
  
  if (!old_exists) {
    message("Table ", full_old_name, " does not exist, skipping...")
    return(FALSE)
  }
  
  if (new_exists) {
    message("Table ", full_new_name, " already exists, skipping rename...")
    return(FALSE)
  }
  
  # Rename the table
  message("Renaming ", full_old_name, " to ", full_new_name)
  
  if (db_class == "PqConnection") {
    sql <- sprintf("ALTER TABLE %s RENAME TO %s", full_old_name, new_name)
  } else {
    sql <- sprintf("ALTER TABLE %s RENAME TO %s", full_old_name, full_new_name)
  }
  
  DBI::dbExecute(con, sql)
  return(TRUE)
}

# Function to rename indexes safely  
rename_index_safe <- function(con, old_name, new_name, schema = NULL) {
  db_class <- class(con)[1]
  
  if (db_class == "PqConnection") {
    # PostgreSQL
    if (!is.null(schema)) {
      full_old_name <- paste0(schema, ".", old_name)
      full_new_name <- paste0(schema, ".", new_name)
    } else {
      full_old_name <- old_name
      full_new_name <- new_name
    }
    
    # Check if index exists
    exists_query <- "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = $1 AND indexname = $2)"
    schema_name <- if (!is.null(schema)) schema else "tasker"
    old_exists <- DBI::dbGetQuery(con, exists_query, params = list(schema_name, old_name))[[1]]
    new_exists <- DBI::dbGetQuery(con, exists_query, params = list(schema_name, new_name))[[1]]
    
    if (!old_exists) {
      message("Index ", full_old_name, " does not exist, skipping...")
      return(FALSE)
    }
    
    if (new_exists) {
      message("Index ", full_new_name, " already exists, skipping rename...")
      return(FALSE)
    }
    
    message("Renaming index ", full_old_name, " to ", full_new_name)
    sql <- sprintf("ALTER INDEX %s RENAME TO %s", full_old_name, new_name)
    DBI::dbExecute(con, sql)
    
  } else {
    # SQLite doesn't support renaming indexes, need to drop and recreate
    # The indexes will be recreated when we apply the new schema
    message("SQLite: Indexes will be recreated with new schema")
  }
  
  return(TRUE)
}

# Main migration function
migrate_database <- function() {
  message("Starting database migration: process_reporter -> reporter")
  
  # Get database connection using tasker configuration
  con <- tryCatch(get_db_connection(), error = function(e) {
    stop("Failed to connect to database: ", e$message)
  })
  
  on.exit({
    if (!is.null(con) && DBI::dbIsValid(con)) {
      DBI::dbDisconnect(con)
    }
  })
  
  # Check database type
  db_class <- class(con)[1]
  is_postgres <- db_class == "PqConnection"
  schema_name <- if (is_postgres) "tasker" else NULL
  
  message("Connected to ", if (is_postgres) "PostgreSQL" else "SQLite", " database")
  
  # Rename process_reporter_status table to reporter_status
  rename_table_safe(con, "process_reporter_status", "reporter_status", schema_name)
  
  # For PostgreSQL, also rename indexes
  if (is_postgres) {
    # These indexes should exist on the process_reporter_status table
    # The new names will match the updated schema
    rename_index_safe(con, "idx_reporter_hostname", "idx_reporter_hostname_new", schema_name)
    rename_index_safe(con, "idx_reporter_heartbeat", "idx_reporter_heartbeat_new", schema_name)
  }
  
  message("Migration completed successfully!")
  return(TRUE)
}

# Run the migration
if (interactive()) {
  cat("This will rename database tables from process_reporter_* to reporter_*\n")
  cat("Do you want to continue? (y/N): ")
  response <- readline()
  if (tolower(response) != "y") {
    stop("Migration cancelled by user")
  }
}

migrate_database()