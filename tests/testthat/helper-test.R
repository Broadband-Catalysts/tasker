# Test helpers

# Use SQLite for testing by default
get_test_db_path <- function() {
  file.path(tempdir(), "tasker_test.db")
}

#' Setup test database with SQLite
setup_test_db <- function() {
  db_path <- get_test_db_path()
  
  # Remove existing test database
  if (file.exists(db_path)) {
    unlink(db_path)
  }
  
  # Configure tasker to use SQLite
  tasker::tasker_config(
    driver = "sqlite",
    dbname = db_path,
    schema = "",  # SQLite doesn't use schemas
    reload = TRUE
  )
  
  # Create main schema
  tasker::setup_tasker_db(force = TRUE)
  
  # Create process reporter schema manually (simpler than parsing the full schema)
  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = db_path)
  
  # Create process_reporter_status table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_reporter_status (
        reporter_id INTEGER PRIMARY KEY AUTOINCREMENT,
        hostname TEXT NOT NULL UNIQUE,
        process_id INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        last_heartbeat TEXT NOT NULL,
        version TEXT,
        config TEXT DEFAULT '{}',
        shutdown_requested INTEGER DEFAULT 0
    )")
  
  # Create process_metrics table  
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics (
        metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT NOT NULL REFERENCES task_runs(run_id) ON DELETE CASCADE,
        timestamp TEXT NOT NULL,
        process_id INTEGER NOT NULL,
        hostname TEXT NOT NULL,
        is_alive INTEGER NOT NULL DEFAULT 1,
        process_start_time TEXT,
        cpu_percent REAL,
        memory_mb REAL,
        memory_percent REAL,
        memory_vms_mb REAL,
        swap_mb REAL,
        read_bytes INTEGER,
        write_bytes INTEGER,
        read_count INTEGER,
        write_count INTEGER,
        io_wait_percent REAL,
        open_files INTEGER,
        num_fds INTEGER,
        num_threads INTEGER,
        page_faults_minor INTEGER,
        page_faults_major INTEGER,
        num_ctx_switches_voluntary INTEGER,
        num_ctx_switches_involuntary INTEGER,
        child_count INTEGER DEFAULT 0,
        child_total_cpu_percent REAL,
        child_total_memory_mb REAL,
        collection_error INTEGER DEFAULT 0,
        error_message TEXT,
        error_type TEXT,
        reporter_version TEXT,
        collection_duration_ms INTEGER
    )")
  
  # Create process_metrics_retention table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS process_metrics_retention (
        retention_id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT NOT NULL REFERENCES task_runs(run_id) ON DELETE CASCADE,
        task_completed_at TEXT NOT NULL,
        metrics_delete_after TEXT NOT NULL,
        metrics_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        metrics_count INTEGER,
        UNIQUE (run_id)
    )")
  
  con
}

#' Clean up test database
cleanup_test_db <- function(con = NULL) {
  if (!is.null(con) && DBI::dbIsValid(con)) {
    DBI::dbDisconnect(con)
  }
  
  db_path <- get_test_db_path()
  if (file.exists(db_path)) {
    unlink(db_path)
  }
  
  # Clear config
  options(tasker.config = NULL)
  
  invisible(NULL)
}

#' Get test database connection
get_test_db_connection <- function() {
  tasker:::ensure_configured()
  tasker::get_db_connection()
}
