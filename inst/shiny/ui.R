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
    tags$link(rel = "stylesheet", type = "text/css", href = "www/styles.css")
  ),

  titlePanel(
    "FCC Data Pipeline - Tasker Monitor"
  ),
  div(
    class="build-info",
    sprintf("Branch: %s", GIT_BRANCH), br(),
    sprintf("Build: %s", BUILD_TIME)
  ),
  sidebarLayout(
    sidebarPanel(
      width = 2,
      selectInput("stage_filter", "Filter by Stage:", 
                  choices = c("All" = ""), multiple = TRUE),
      selectInput("status_filter", "Filter by Status:",
                  choices = c("All" = "", "NOT_STARTED", "STARTED", "RUNNING", 
                             "COMPLETED", "FAILED", "SKIPPED"),
                  multiple = TRUE),
      numericInput("refresh_interval", "Auto-refresh (seconds):", 
                   value = 5, min = 1, max = 60),
      checkboxInput("auto_refresh", "Auto-refresh", value = TRUE),
      hr(),
      actionButton("refresh", "Refresh Now", class = "btn-primary"),
      hr(),
      textOutput("last_update")
    ),
    
    mainPanel(
      width = 10,
      # Error message banner
      conditionalPanel(
        condition = "output.has_error",
        div(class = "alert alert-danger", style = "margin: 10px;",
            tags$strong("Error: "),
            tags$pre(style = "white-space: pre-wrap; margin-top: 10px; background: #fff; padding: 10px; border: 1px solid #ddd;",
                    textOutput("error_display", inline = FALSE))
        )
      ),
      tabsetPanel(
        id = "main_tabs",
        tabPanel("Pipeline Status",
                 div(class = "pipeline-status-container",
                     # Accordion structure built dynamically with proper Shiny UI elements
                     uiOutput("pipeline_stages_accordion")
                 )
        )
      )
    )
  )
)
