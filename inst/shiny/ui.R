library(shiny)
library(bslib)
library(DT)
library(tasker)
library(dplyr)
library(lubridate)
library(shinyWidgets)


ui <- page_fluid(
  theme = bs_theme(version = 5),
  tags$head(
    title = "Tasker Monitor",
    tags$link(rel = "stylesheet", type = "text/css", href = "www/styles.css"),
  ),

  titlePanel(
    div(
      style = "display: flex; justify-content: space-between; align-items: center;",
      div({
        config <- getOption("tasker.config")
        pipeline_name <- if (!is.null(config$pipeline$name)) config$pipeline$name else "Pipeline"
        paste(pipeline_name, "- Tasker Monitor")
      }),
      div(
        style = "font-size: 12px; color: #666; text-align: right; font-weight: normal;",
        div(sprintf("Build: %s", BUILD_TIME)),
        div(sprintf("Commit: %s", GIT_COMMIT))
      )
    )
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
                     uiOutput("pipeline_status_ui")
                 )
        )
      )
    )
  )
)
