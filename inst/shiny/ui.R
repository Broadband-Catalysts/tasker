library(shiny)
library(bslib)
library(DT)
library(tasker)
library(dplyr)
library(lubridate)
library(shinyWidgets)
library(shinyjs)
library(shinyTZ)


ui <- page_fluid(
  theme = bs_theme(version = 5),
  useShinyjs(),
  useShinyTZ(),  # Enable timezone detection
  tags$head(
    tags$title("FCC Data Pipeline - Tasker Monitor"),
    tags$link(rel = "stylesheet", type = "text/css", href = "www/styles.css"),
    tags$script(HTML("
      var reconnectTimer = null;
      var reconnectAttempts = 0;
      
      $(document).on('click', '.kill-query-btn', function() {
        var pid = $(this).data('pid');
        var username = $(this).data('username');
        Shiny.setInputValue('kill_query_pid', pid, {priority: 'event'});
        Shiny.setInputValue('kill_query_username', username, {priority: 'event'});
      });
      
      // Show prominent disconnection alert and start auto-reconnect
      $(document).on('shiny:disconnected', function() {
        $('#shiny-disconnection-alert').fadeIn(500);
        reconnectAttempts = 0;
        
        // Clear any existing timer
        if (reconnectTimer) {
          clearInterval(reconnectTimer);
        }
        
        // Attempt reconnection every 2 seconds indefinitely
        reconnectTimer = setInterval(function() {
          reconnectAttempts++;
          console.log('Attempting reconnection (attempt ' + reconnectAttempts + ')...');
          
          // Update alert message with attempt count
          $('#shiny-disconnection-alert .alert-submessage').text('Attempting to reconnect... (attempt ' + reconnectAttempts + ')');
          
          // Attempt to reconnect using Shiny's built-in method
          if (Shiny && Shiny.shinyapp && Shiny.shinyapp.reconnect) {
            Shiny.shinyapp.reconnect();
          }
        }, 2000);
      });
      
      // Hide alert on reconnection and clear timer
      $(document).on('shiny:connected', function() {
        console.log('Successfully reconnected to server.');
        $('#shiny-disconnection-alert').fadeOut(300);
        
        // Clear reconnection timer
        if (reconnectTimer) {
          clearInterval(reconnectTimer);
          reconnectTimer = null;
        }
        reconnectAttempts = 0;
      });
    "))
  ),
  
  # Disconnection Alert (hidden by default)
  div(
    id = "shiny-disconnection-alert",
    span(class = "alert-icon", "⚠️"),
    span(class = "alert-message", "CONNECTION LOST"),
    span(class = "alert-submessage", "Attempting to reconnect...")
  ),

  div(
    class = "page-header-fixed",
    h2(
      class = "page-title",
      "FCC Data Pipeline - Tasker Monitor",
      span(
        class = "build-info-inline",
        sprintf("Branch: %s  |  Build: %s", GIT_BRANCH, BUILD_TIME)
      )
    )
  ),
  layout_sidebar(
    sidebar = sidebar(
      title = "Filters & Controls",
      open = "desktop",
      width = 320,
      # FILTERS Section
      div(class = "filter-row",
        span(class = "filter-label", "Stage:"),
        div(class = "filter-input",
          selectInput("stage_filter", NULL, 
                      choices = c("All" = ""), multiple = TRUE)
        )
      ),
      div(class = "filter-row",
        span(class = "filter-label", "Status:"),
        div(class = "filter-input",
          selectInput("status_filter", NULL,
                      choices = c("All" = "", "NOT_STARTED", "STARTED", "RUNNING", 
                                 "COMPLETED", "FAILED", "SKIPPED"),
                      multiple = TRUE)
        )
      ),
      div(class = "filter-row-inline",
        checkboxInput("show_script_name", "Show Script Names", value = TRUE)
      ),
      hr(),
      # REFRESH Section
      div(class = "refresh-info",
        span(class = "refresh-label", "Last Refresh:"),
        datetimeOutput("last_update", inline = TRUE)
      ),
      div(class = "refresh-controls",
        div(class = "button-group",
          actionButton("refresh_structure", 
                       list(icon("rotate-right"), "Structure"), 
                       class = "btn-secondary btn-sm",
                       title = "Reload pipeline stages and registered tasks"),
          actionButton("refresh", 
                       list(icon("rotate-right"), "Tasks"), 
                       class = "btn-primary btn-sm",
                       title = "Refresh task status and progress")
        )
      ),
      div(class = "filter-row-inline",
        checkboxInput("auto_refresh", "Auto Refresh", value = TRUE),
        span(class = "inline-label", "Interval:"),
        numericInput("refresh_interval", NULL, 
                     value = 5, min = 1, max = 60, width = "70px"),
        span(class = "inline-label", "seconds")
      ),
      hr(),
      div(style = "margin-bottom: 10px;",
        div(style = "display: flex; justify-content: space-between; align-items: baseline;",
          h6(style = "margin: 0;", "Reporter Status:"),
          htmlOutput("monitor_active_count", inline = TRUE, style = "font-size: 11px; color: #777;")
        ),
        htmlOutput("monitor_status", style = "font-size: 12px; margin-top: 4px;")
      ),
      hr(),
      actionButton("start_debugger", "DEBUG", class = "btn-warning btn-sm", 
                   title = "Start R debugger (browser()) for troubleshooting")
    ),
    # Error/Info message banner
    conditionalPanel(
      condition = "output.has_error",
      htmlOutput("error_banner")
    ),
    tabsetPanel(
      id = "main_tabs",
      tabPanel("Pipeline Status",
               div(class = "pipeline-status-container",
                   # Accordion structure built dynamically with proper Shiny UI elements
                   uiOutput("pipeline_stages_accordion")
               )
      ),
      tabPanel("SQL Queries",
               div(class = "sql-queries-container", style = "padding: 8px;",
                   fluidRow(
                     column(6,
                            actionButton("sql_refresh_now", "Refresh Now", 
                                       class = "btn-primary")
                     ),
                     column(6,
                            div(style = "margin-top: 5px;",
                                checkboxInput("exclude_tasker_queries", 
                                            "Exclude tasker queries", 
                                            value = TRUE)
                            )
                     )
                   ),
                   hr(),
                   div(style = "overflow: auto;",
                       DTOutput("sql_queries_table")
                   )
               )
      )
    )
  )
)
