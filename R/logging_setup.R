#' Setup logging for tasker package
#'
#' Configures logger package for task tracking contexts including
#' CLI scripts, Shiny monitoring app, and background processes.
#'
#' @param log_level Character string specifying minimum log level.
#'   One of: "TRACE", "DEBUG", "INFO", "SUCCESS", "WARN", "ERROR", "FATAL".
#'   Default: "INFO" for batch mode, "DEBUG" for interactive.
#' @param log_file Character string specifying log file path. If NULL (default),
#'   logs only to console.
#' @param context Character string identifying the execution context.
#'   One of: "cli", "shiny", "background". Default: auto-detected.
#' @param namespace Character string specifying logger namespace.
#'   Default: "tasker"
#'
#' @return Invisibly returns the configured log level threshold
#' @export
#'
#' @examples
#' \dontrun{
#' # CLI script logging
#' setup_logging(context = "cli", log_file = "task_execution.log")
#' log_info("Task started: {task_name}")
#'
#' # Shiny app logging
#' setup_logging(context = "shiny")
#' log_debug("User action: {input$button_id}")
#'
#' # Background process logging
#' setup_logging(
#'   context = "background",
#'   log_file = "background_process.log",
#'   log_level = "DEBUG"
#' )
#' }
setup_logging <- function(log_level = NULL,
                          log_file = NULL,
                          context = NULL,
                          namespace = "tasker") {
  
  # Auto-detect context if not specified
  if (is.null(context)) {
    context <- detect_execution_context()
  }
  
  # Auto-detect log level if not specified
  if (is.null(log_level)) {
    log_level <- switch(context,
      cli = "INFO",
      shiny = "DEBUG",
      background = "INFO",
      "INFO"  # default
    )
  }
  
  # Set log threshold
  logger::log_threshold(log_level, namespace = namespace)
  
  # Configure layout based on context
  layout <- switch(context,
    cli = logger::layout_glue_generator(
      format = '[{time}] [{level}] {msg}'
    ),
    shiny = logger::layout_glue_generator(
      format = '[{time}] [{level}] [Session: {sessionId}] {msg}'
    ),
    background = logger::layout_glue_generator(
      format = '[{time}] [{level}] [PID: {pid}] {msg}'
    ),
    logger::layout_glue_colors  # default with colors
  )
  
  logger::log_layout(layout, namespace = namespace)
  
  # Configure appenders
  if (!is.null(log_file)) {
    logger::log_appender(
      logger::appender_tee(log_file, append = TRUE),
      namespace = namespace
    )
    logger::log_info("Logging to console and file: {log_file}", namespace = namespace)
  } else {
    logger::log_appender(logger::appender_console, namespace = namespace)
  }
  
  logger::log_info("Logger initialized for {context} context at {log_level} level", 
                   namespace = namespace)
  
  invisible(log_level)
}


#' Setup Shiny session-specific logging
#'
#' Configures logger with session isolation for Shiny applications.
#' Each user session gets its own logger namespace.
#'
#' @param session Shiny session object
#' @param log_level Character string specifying minimum log level.
#'   Default: "DEBUG" (Shiny debugging typically needs detailed logs)
#' @param log_dir Character string specifying directory for session logs.
#'   If NULL, logs to console only. Default: NULL
#' @param base_namespace Character string for base namespace.
#'   Default: "tasker.shiny"
#'
#' @return Invisibly returns the session-specific namespace
#' @export
#'
#' @examples
#' \dontrun{
#' # In Shiny server function:
#' server <- function(input, output, session) {
#'   # Setup session-specific logging
#'   ns <- setup_shiny_logging(session)
#'   
#'   # Use logger with session namespace
#'   log_info("User connected", namespace = ns)
#'   
#'   observeEvent(input$button, {
#'     log_debug("Button clicked: {input$button}", namespace = ns)
#'   })
#'   
#'   session$onSessionEnded(function() {
#'     log_info("User disconnected", namespace = ns)
#'   })
#' }
#' }
setup_shiny_logging <- function(session,
                                log_level = "DEBUG",
                                log_dir = NULL,
                                base_namespace = "tasker.shiny") {
  
  # Create session-specific namespace
  session_id <- session$token
  session_namespace <- glue::glue("{base_namespace}.{substr(session_id, 1, 8)}")
  
  # Set threshold for this session's namespace
  logger::log_threshold(log_level, namespace = session_namespace)
  
  # Configure layout with session ID
  logger::log_layout(
    logger::layout_glue_generator(
      format = '[{time}] [{level}] [{session_id}] {msg}'
    ),
    namespace = session_namespace
  )
  
  # Configure appender
  if (!is.null(log_dir)) {
    if (!dir.exists(log_dir)) {
      dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
    }
    
    log_file <- file.path(log_dir, glue::glue("session_{substr(session_id, 1, 8)}.log"))
    logger::log_appender(
      logger::appender_file(log_file, append = TRUE),
      namespace = session_namespace
    )
  } else {
    logger::log_appender(logger::appender_console, namespace = session_namespace)
  }
  
  logger::log_info("Shiny session logger initialized", namespace = session_namespace)
  
  invisible(session_namespace)
}


#' Setup database logging for task execution
#'
#' Configures logger to write log entries to the tasker database
#' alongside task tracking data.
#'
#' @param con Database connection object (from dbConnectBBC)
#' @param table_name Character string specifying log table name.
#'   Default: "tasker_logs"
#' @param run_id Numeric run_id to associate logs with a specific task execution.
#'   If NULL, logs are not associated with a run. Default: NULL
#' @param also_console Logical. If TRUE, log to both database and console.
#'   Default: TRUE
#' @param namespace Character string specifying logger namespace.
#'   Default: "tasker"
#'
#' @return Invisibly returns TRUE on success
#' @export
#'
#' @examples
#' \dontrun{
#' # Setup database logging for a task
#' con <- dbConnectBBC(mode = "rw")
#' run_id <- task_start("STAGE", "Task Name")
#' setup_database_logging(con, run_id = run_id)
#' 
#' # Logs are now stored in database with run_id association
#' log_info("Task processing started")
#' log_debug("Processing item {i} of {total}")
#' }
setup_database_logging <- function(con,
                                   table_name = "tasker_logs",
                                   run_id = NULL,
                                   also_console = TRUE,
                                   namespace = "tasker") {
  
  # Create log table if it doesn't exist
  create_table_sql <- glue::glue("
    CREATE TABLE IF NOT EXISTS {table_name} (
      log_id SERIAL PRIMARY KEY,
      log_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      log_level VARCHAR(10),
      namespace VARCHAR(100),
      message TEXT,
      run_id INTEGER,
      session_id VARCHAR(255),
      pid INTEGER,
      FOREIGN KEY (run_id) REFERENCES tasker_runs(run_id) ON DELETE CASCADE
    )
  ")
  
  DBI::dbExecute(con, create_table_sql)
  
  # Create index for run_id lookups
  DBI::dbExecute(con, glue::glue("
    CREATE INDEX IF NOT EXISTS idx_{table_name}_run_id 
    ON {table_name}(run_id)
  "))
  
  # Create custom database appender
  db_appender <- function(lines) {
    tryCatch({
      for (line in lines) {
        insert_sql <- glue::glue("
          INSERT INTO {table_name} (log_level, namespace, message, run_id, pid)
          VALUES (
            'INFO',
            {DBI::dbQuoteLiteral(con, namespace)},
            {DBI::dbQuoteLiteral(con, line)},
            {if (!is.null(run_id)) run_id else 'NULL'},
            {Sys.getpid()}
          )
        ")
        DBI::dbExecute(con, insert_sql)
      }
    }, error = function(e) {
      warning("Failed to write log to database: ", e$message)
    })
  }
  
  # Setup appender
  if (also_console) {
    logger::log_appender(
      function(lines) {
        logger::appender_console(lines)
        db_appender(lines)
      },
      namespace = namespace
    )
  } else {
    logger::log_appender(db_appender, namespace = namespace)
  }
  
  logger::log_info("Database logging configured to table: {table_name}", namespace = namespace)
  
  invisible(TRUE)
}


#' Detect execution context
#'
#' Determines whether code is running in CLI, Shiny, or background context
#'
#' @return Character string: "cli", "shiny", "background", or "unknown"
#' @keywords internal
detect_execution_context <- function() {
  # Check for Shiny
  if (requireNamespace("shiny", quietly = TRUE)) {
    if (!is.null(shiny::getDefaultReactiveDomain())) {
      return("shiny")
    }
  }
  
  # Check for background process (no terminal)
  if (!interactive() && Sys.getenv("TERM") == "") {
    return("background")
  }
  
  # Check for CLI (non-interactive)
  if (!interactive()) {
    return("cli")
  }
  
  # Default to CLI for interactive sessions
  "cli"
}


#' Get logging configuration for current environment
#'
#' Returns recommended logging configuration based on execution context
#'
#' @return Named list with recommended configuration
#' @export
#'
#' @examples
#' \dontrun{
#' config <- get_logging_config()
#' setup_logging(
#'   log_level = config$log_level,
#'   context = config$context
#' )
#' }
get_logging_config <- function() {
  context <- detect_execution_context()
  
  config <- list(
    context = context,
    log_level = switch(context,
      cli = "INFO",
      shiny = "DEBUG",
      background = "INFO",
      "INFO"
    ),
    log_file = NULL,
    namespace = "tasker"
  )
  
  config
}
