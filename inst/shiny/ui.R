library(shiny)
library(bslib)
library(DT)
library(tasker)
library(dplyr)
library(lubridate)
library(shinyWidgets)
library(shinyjs)


ui <- page_fluid(
  theme = bs_theme(version = 5),
  useShinyjs(),
  tags$head(
    tags$title("FCC Data Pipeline - Tasker Monitor"),
    tags$link(rel = "stylesheet", type = "text/css", href = "www/styles.css"),
    tags$script(HTML("
      $(document).on('click', '.kill-query-btn', function() {
        var pid = $(this).data('pid');
        var username = $(this).data('username');
        Shiny.setInputValue('kill_query_pid', pid, {priority: 'event'});
        Shiny.setInputValue('kill_query_username', username, {priority: 'event'});
      });
    "))
  ),

  titlePanel(
    "FCC Data Pipeline - Tasker Monitor"
  ),
  div(
    class="build-info",
    sprintf("Branch: %s", GIT_BRANCH), br(),
    sprintf("Build: %s", BUILD_TIME)
  ),
  layout_sidebar(
    sidebar = sidebar(
      title = "Filters & Controls",
      open = "desktop",
      width = 250,
      selectInput("stage_filter", "Filter by Stage:", 
                  choices = c("All" = ""), multiple = TRUE),
      selectInput("status_filter", "Filter by Status:",
                  choices = c("All" = "", "NOT_STARTED", "STARTED", "RUNNING", 
                             "COMPLETED", "FAILED", "SKIPPED"),
                  multiple = TRUE),
      numericInput("refresh_interval", "Auto-refresh (seconds):", 
                   value = 5, min = 1, max = 60),
      checkboxInput("auto_refresh", "Auto-refresh", value = TRUE),
      checkboxInput("show_script_name", "Show script names", value = FALSE),
      hr(),
      actionButton("refresh", "Refresh Now", class = "btn-primary"),
      actionButton("refresh_structure", "Refresh Structure", class = "btn-secondary btn-sm",
                   title = "Reload pipeline stages and registered tasks"),
      hr(),
      actionButton("start_debugger", "DEBUG", class = "btn-warning btn-sm", 
                   title = "Start R debugger (browser()) for troubleshooting"),
      hr(),
      textOutput("last_update")
    ),
    # Error/Info message banner
    conditionalPanel(
      condition = "output.has_error",
      uiOutput("error_banner")
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
                     column(12,
                            actionButton("sql_refresh_now", "Refresh Now", 
                                       class = "btn-primary")
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
