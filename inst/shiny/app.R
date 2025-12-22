library(shiny)
library(DT)
library(tasker)

# Configuration should already be loaded by run_monitor()
# Just verify it's available
if (is.null(getOption("tasker.config"))) {
  stop("Tasker configuration not loaded. Please run this app via tasker::run_monitor()")
}

ui <- fluidPage(
  titlePanel("Tasker Pipeline Monitor"),
  
  tags$head(
    tags$style(HTML("
      .status-NOT_STARTED { background-color: #f0f0f0; }
      .status-STARTED { background-color: #fff3cd; }
      .status-RUNNING { background-color: #cfe2ff; }
      .status-COMPLETED { background-color: #d1e7dd; }
      .status-FAILED { background-color: #f8d7da; }
      .status-SKIPPED { background-color: #e2e3e5; }
      .detail-box { 
        border: 1px solid #ddd; 
        padding: 10px; 
        margin: 10px 0; 
        background-color: #f9f9f9; 
      }
      .log-output {
        font-family: monospace;
        background-color: #000;
        color: #0f0;
        padding: 10px;
        max-height: 400px;
        overflow-y: auto;
        white-space: pre-wrap;
      }
    "))
  ),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("stage_filter", "Filter by Stage:", 
                  choices = c("All" = ""), multiple = FALSE),
      selectInput("status_filter", "Filter by Status:",
                  choices = c("All" = "", "NOT_STARTED", "STARTED", "RUNNING", 
                             "COMPLETED", "FAILED", "SKIPPED"),
                  multiple = FALSE),
      numericInput("refresh_interval", "Auto-refresh (seconds):", 
                   value = 5, min = 1, max = 60),
      checkboxInput("auto_refresh", "Auto-refresh", value = TRUE),
      hr(),
      actionButton("refresh", "Refresh Now", class = "btn-primary"),
      hr(),
      textOutput("last_update")
    ),
    
    mainPanel(
      width = 9,
      tabsetPanel(
        id = "main_tabs",
        tabPanel("Overview",
                 DTOutput("task_table"),
                 hr(),
                 uiOutput("detail_panel")
        ),
        tabPanel("Stage Summary",
                 plotOutput("stage_progress_plot"),
                 hr(),
                 DTOutput("stage_summary_table")
        ),
        tabPanel("Timeline",
                 plotOutput("timeline_plot", height = "600px")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  
  # Reactive values
  rv <- reactiveValues(
    selected_task_id = NULL,
    last_update = NULL
  )
  
  # Auto-refresh timer
  autoRefresh <- reactive({
    if (input$auto_refresh) {
      invalidateLater(input$refresh_interval * 1000)
    }
    input$refresh
  })
  
  # Fetch task data
  task_data <- reactive({
    autoRefresh()
    
    tryCatch({
      data <- tasker::get_task_status()
      rv$last_update <- Sys.time()
      
      # Apply filters
      if (!is.null(data) && nrow(data) > 0) {
        if (input$stage_filter != "") {
          data <- data[data$stage == input$stage_filter, ]
        }
        if (input$status_filter != "") {
          data <- data[data$status == input$status_filter, ]
        }
      }
      
      data
    }, error = function(e) {
      showNotification(paste("Error fetching data:", e$message), type = "error")
      NULL
    })
  })
  
  # Update stage filter choices
  observe({
    data <- task_data()
    if (!is.null(data) && nrow(data) > 0) {
      stages <- unique(data$stage)
      updateSelectInput(session, "stage_filter", 
                       choices = c("All" = "", stages))
    }
  })
  
  # Main task table
  output$task_table <- renderDT({
    data <- task_data()
    
    if (is.null(data) || nrow(data) == 0) {
      empty_df <- data.frame(
        Stage = character(0),
        Task = character(0),
        Status = character(0),
        Progress = character(0),
        `Overall Progress` = character(0),
        Started = character(0),
        Duration = character(0),
        Host = character(0),
        Details = character(0),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
      return(datatable(empty_df, options = list(
        language = list(emptyTable = "No tasks found")
      )))
    }
    
    # Prepare display columns
    display_data <- data.frame(
      Stage = data$stage_name,
      Task = data$task_name,
      Status = data$status,
      Progress = ifelse(is.na(data$current_subtask), "--", 
                       sprintf("%d/%d", data$current_subtask, data$total_subtasks)),
      "Overall Progress" = sprintf("%.1f%%", data$overall_percent_complete),
      Started = format(data$start_time, "%Y-%m-%d %H:%M:%S"),
      Duration = format_duration(data$start_time, data$last_update),
      Host = data$hostname,
      Details = sprintf('<button class="btn btn-sm btn-info detail-btn" data-id="%s">View</button>', 
                       data$run_id),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    
    datatable(display_data,
              escape = FALSE,
              selection = 'none',
              options = list(
                pageLength = 25,
                order = list(list(0, 'asc'), list(5, 'desc')),
                rowCallback = JS(
                  "function(row, data) {",
                  "  var status = data[2];",
                  "  $(row).addClass('status-' + status);",
                  "}"
                )
              )) %>%
      formatStyle('Status', fontWeight = 'bold')
  })
  
  # Handle detail button clicks
  observeEvent(input$task_table_cell_clicked, {
    info <- input$task_table_cell_clicked
    if (!is.null(info$value) && grepl("detail-btn", info$value)) {
      task_id <- gsub('.*data-id="([^"]+)".*', '\\1', info$value)
      rv$selected_task_id <- task_id
    }
  })
  
  # Detail panel
  output$detail_panel <- renderUI({
    if (is.null(rv$selected_task_id)) {
      return(NULL)
    }
    
    data <- task_data()
    task <- data[data$run_id == rv$selected_task_id, ]
    
    if (nrow(task) == 0) {
      return(NULL)
    }
    
    div(class = "detail-box",
        h3("Task Details"),
        actionButton("close_detail", "Close", class = "btn-sm btn-secondary pull-right"),
        hr(),
        fluidRow(
          column(6,
                 h4("Identification"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Run ID:"), tags$td(task$run_id)),
                           tags$tr(tags$th("Stage:"), tags$td(task$stage_name)),
                           tags$tr(tags$th("Task Name:"), tags$td(task$task_name)),
                           tags$tr(tags$th("Type:"), tags$td(task$task_type)),
                           tags$tr(tags$th("Status:"), tags$td(task$status))
                 )
          ),
          column(6,
                 h4("Execution Info"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Hostname:"), tags$td(task$hostname)),
                           tags$tr(tags$th("PID:"), tags$td(task$process_id)),
                           tags$tr(tags$th("Started:"), tags$td(format(task$start_time, "%Y-%m-%d %H:%M:%S"))),
                           tags$tr(tags$th("Last Update:"), tags$td(format(task$last_update, "%Y-%m-%d %H:%M:%S"))),
                           tags$tr(tags$th("Duration:"), tags$td(format_duration(task$start_time, task$last_update)))
                 )
          )
        ),
        fluidRow(
          column(12,
                 h4("Progress"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Overall:"), 
                                  tags$td(sprintf("%.1f%% - %s", 
                                                task$overall_percent_complete,
                                                ifelse(is.na(task$overall_progress_message), "", task$overall_progress_message)))),
                           tags$tr(tags$th("Subtasks:"), 
                                  tags$td(ifelse(is.na(task$total_subtasks), "N/A",
                                                sprintf("%s / %d", 
                                                       ifelse(is.na(task$current_subtask), "0", task$current_subtask),
                                                       task$total_subtasks))))
                 )
          )
        ),
        fluidRow(
          column(12,
                 h4("Files"),
                 tags$table(class = "table table-sm",
                           tags$tr(tags$th("Script Path:"), tags$td(ifelse(is.na(task$script_path), "N/A", task$script_path))),
                           tags$tr(tags$th("Script File:"), tags$td(task$script_filename)),
                           tags$tr(tags$th("Log Path:"), tags$td(task$log_path)),
                           tags$tr(tags$th("Script:"), tags$td(ifelse(is.na(task$script_filename), "N/A", task$script_filename))),
                           tags$tr(tags$th("Log Path:"), tags$td(ifelse(is.na(task$log_path), "N/A", task$log_path))),
                           tags$tr(tags$th("Log File:"), tags$td(ifelse(is.na(task$log_filename), "N/A", task$log_filename)))
                 )
          )
        ),
        fluidRow(
          column(12,
                 h4("Error Message"),
                 tags$div(ifelse(is.na(task$error_message) || task$error_message == "", 
                                "No errors", task$error_message))
          )
        )
    )
  })
  
  # Close detail panel
  observeEvent(input$close_detail, {
    rv$selected_task_id <- NULL
  })
  
  # Stage summary table
  output$stage_summary_table <- renderDT({
    data <- task_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(datatable(data.frame(Message = "No data")))
    }
    
    summary <- aggregate(cbind(Total = run_id) ~ stage_name + status, 
                        data = data, 
                        FUN = length)
    
    wide_summary <- reshape(summary, 
                           idvar = "stage_name", 
                           timevar = "status", 
                           direction = "wide")
    
    datatable(wide_summary, options = list(pageLength = 10))
  })
  
  # Stage progress plot
  output$stage_progress_plot <- renderPlot({
    data <- task_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(NULL)
    }
    
    library(ggplot2)
    
    stage_progress <- aggregate(overall_percent_complete ~ stage_name, 
                                data = data,
                                FUN = mean)
    
    ggplot(stage_progress, aes(x = stage_name, y = overall_percent_complete)) +
      geom_bar(stat = "identity", fill = "steelblue") +
      geom_text(aes(label = sprintf("%.1f%%", overall_percent_complete)), 
               vjust = -0.5) +
      ylim(0, 110) +
      labs(title = "Average Progress by Stage",
           x = "Stage",
           y = "Progress (%)") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })
  
  # Timeline plot
  output$timeline_plot <- renderPlot({
    data <- task_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(NULL)
    }
    
    library(ggplot2)
    
    # Prepare timeline data
    data$end_display <- ifelse(is.na(data$end_time), 
                           as.numeric(Sys.time()), 
                           as.numeric(data$end_time))
    data$start_display <- as.numeric(data$start_time)
    
    ggplot(data, aes(y = task_name, color = status)) +
      geom_segment(aes(x = as.POSIXct(start_display, origin = "1970-01-01"),
                      xend = as.POSIXct(end_display, origin = "1970-01-01"),
                      yend = task_name),
                  size = 8) +
      facet_grid(stage_name ~ ., scales = "free_y", space = "free_y") +
      labs(title = "Task Timeline",
           x = "Time",
           y = "Task",
           color = "Status") +
      theme_minimal() +
      theme(axis.text.y = element_text(size = 8))
  })
  
  # Last update time
  output$last_update <- renderText({
    if (!is.null(rv$last_update)) {
      paste("Last update:", format(rv$last_update, "%H:%M:%S"))
    } else {
      "No data loaded"
    }
  })
}

# Helper function
format_duration <- function(start, end) {
  if (is.null(start) || length(start) == 0 || is.na(start)) return("-")
  
  if (is.null(end) || length(end) == 0 || is.na(end)) {
    end <- Sys.time()
  }
  
  duration <- as.numeric(difftime(end, start, units = "secs"))
  
  hours <- floor(duration / 3600)
  minutes <- floor((duration %% 3600) / 60)
  seconds <- round(duration %% 60)
  
  if (hours > 0) {
    sprintf("%02d:%02d:%02d", hours, minutes, seconds)
  } else {
    sprintf("%02d:%02d", minutes, seconds)
  }
}

shinyApp(ui = ui, server = server)
