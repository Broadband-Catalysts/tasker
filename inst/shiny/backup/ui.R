# Enhanced UI for FCC Pipeline Monitor
# Features: Single-page layout, dual progress bars, responsive design

library(shiny)
library(DT)

# Get configuration for title
config <- getOption("tasker.config")
pipeline_name <- if (!is.null(config$pipeline$name)) config$pipeline$name else "Pipeline"

ui <- fluidPage(
  title = paste(pipeline_name, "- Tasker Monitor"),
  
  # External CSS
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
    tags$script(HTML("
      // Enhanced task row click handler
      $(document).on('click', '.task-row', function() {
        var taskName = $(this).find('.task-name').text();
        var taskId = $(this).data('task-id');
        var runId = $(this).data('run-id');
        
        // Show detailed view
        if (taskId) {
          $('#task-details-panel').show();
          $('#task-details-title').text('Details for: ' + taskName);
          
          // Trigger server to load task details
          Shiny.setInputValue('selected_task_id', taskId, {priority: 'event'});
          Shiny.setInputValue('selected_run_id', runId, {priority: 'event'});
        }
      });
      
      // Stage accordion handler
      $(document).on('click', '.stage-header', function() {
        $(this).next('.stage-tasks').slideToggle();
        $(this).find('.stage-toggle').text(function(i, text) {
          return text === '▼' ? '▶' : '▼';
        });
      });
      
      // Close task details panel
      $(document).on('click', '.close-panel', function() {
        $('#task-details-panel').hide();
      });
    "))
  ),
  
  # Main title
  titlePanel(paste(pipeline_name, "- Tasker Monitor")),
  
  # Main layout with sidebar and content
  sidebarLayout(
    # Sidebar with filters and controls
    sidebarPanel(
      width = 3,
      
      # Stage filter
      selectInput("stage_filter", "Filter by Stage:",
                  choices = c("All" = "all"), 
                  selected = "all"),
      
      # Status filter  
      selectInput("status_filter", "Filter by Status:",
                  choices = c("All" = "all", "RUNNING" = "RUNNING", 
                             "COMPLETED" = "COMPLETED", "FAILED" = "FAILED",
                             "NOT_STARTED" = "NOT_STARTED", "STARTED" = "STARTED"),
                  selected = "all"),
      
      # Auto-refresh controls
      h4("Auto-refresh"),
      numericInput("refresh_seconds", "Interval (seconds):", 
                   value = 5, min = 1, max = 60, step = 1),
      checkboxInput("auto_refresh", "Auto-refresh", value = TRUE),
      
      # Manual refresh button
      actionButton("refresh_now", "Refresh Now", 
                   class = "btn-primary", style = "width: 100%; margin-top: 10px;"),
      
      # Last update display
      hr(),
      h5("Last update:"),
      textOutput("last_update")
    ),
    
    # Main content area
    mainPanel(
      width = 9,
      
      # Error display area
      conditionalPanel(
        condition = "output.error_display != ''",
        div(class = "error-panel",
            icon("exclamation-triangle"),
            textOutput("error_display")
        )
      ),
      
      # Pipeline status content
      uiOutput("pipeline_status_ui"),
      
      # Task details panel (initially hidden)
      div(id = "task-details-panel", class = "task-details-panel", style = "display: none;",
        div(class = "panel-header",
          h4(id = "task-details-title", "Task Details"),
          tags$button(class = "close-panel btn btn-sm btn-default", "×")
        ),
        
        # Task info tabs
        tabsetPanel(
          tabPanel("Subtask Progress",
            br(),
            DT::dataTableOutput("subtask_table")
          ),
          
          tabPanel("Live Logs",
            br(),
            div(class = "log-controls",
              checkboxInput("auto_refresh_logs", "Auto-refresh logs", value = TRUE),
              actionButton("refresh_logs", "Refresh Now", class = "btn-sm")
            ),
            div(class = "log-viewer",
              verbatimTextOutput("task_logs")
            )
          ),
          
          tabPanel("Task Summary",
            br(),
            verbatimTextOutput("task_summary")
          )
        )
      )
    )
  )
)