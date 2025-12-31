library(shiny)
library(DT)
library(tasker)
library(dplyr)

# Configuration should already be loaded by run_monitor()
# Just verify it's available
if (is.null(getOption("tasker.config"))) {
  stop("Tasker configuration not loaded. Please run this app via tasker::run_monitor()")
}

ui <- fluidPage(
  titlePanel({
    config <- getOption("tasker.config")
    pipeline_name <- if (!is.null(config$pipeline$name)) config$pipeline$name else "Pipeline"
    paste(pipeline_name, "- Tasker Monitor")
  }),
  
  tags$head(
    tags$style(HTML("
      /* Animations */
      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.7; }
      }
      @keyframes progress-stripes {
        0% { background-position: 0 0; }
        100% { background-position: 28.28px 0; }
      }
      
      .status-NOT_STARTED { background-color: #e0e0e0; }
      .status-STARTED { background-color: #fff3cd; }
      .status-RUNNING { background-color: #ffd54f; animation: pulse 2s infinite; }
      .status-COMPLETED { background-color: #81c784; }
      .status-FAILED { background-color: #e57373; }
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
      /* Pipeline Status Tab Styles */
      .pipeline-status-container {
        padding: 15px;
      }
      .stage-panel {
        margin-bottom: 15px;
        border: 1px solid #ddd;
        border-radius: 4px;
        background: #fff;
      }
      .stage-header {
        padding: 12px 15px;
        background: #f8f9fa;
        border-bottom: 1px solid #ddd;
        cursor: pointer;
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .stage-header:hover {
        background: #e9ecef;
      }
      .stage-name {
        font-weight: 600;
        font-size: 16px;
        flex: 0 0 auto;
        min-width: 120px;
      }
      .stage-badge {
        padding: 4px 10px;
        border-radius: 12px;
        font-size: 12px;
        font-weight: bold;
        text-transform: uppercase;
        flex: 0 0 auto;
        min-width: 90px;
        text-align: center;
      }
      .stage-badge.status-NOT_STARTED { background: #e0e0e0; color: #666; }
      .stage-badge.status-STARTED { background: #ffd54f; color: #f57f17; }
      .stage-badge.status-RUNNING { background: #ffd54f; color: #f57f17; animation: pulse 2s infinite; }
      .stage-badge.status-COMPLETED { background: #81c784; color: #2e7d32; }
      .stage-badge.status-FAILED { background: #e57373; color: #c62828; }
      .stage-progress {
        flex: 1;
        height: 20px;
        background: #e0e0e0;
        border-radius: 10px;
        overflow: hidden;
        position: relative;
      }
      .stage-progress-fill {
        height: 100%;
        transition: width 0.5s ease;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 11px;
        font-weight: bold;
        color: white;
      }
      .stage-progress-fill.status-NOT_STARTED { background: linear-gradient(90deg, #bdbdbd 0%, #9e9e9e 100%); }
      .stage-progress-fill.status-STARTED { background: linear-gradient(90deg, #ffd54f 0%, #ffb300 100%); }
      .stage-progress-fill.status-RUNNING { 
        background: repeating-linear-gradient(
          45deg,
          #ffd54f,
          #ffd54f 10px,
          #ffe082 10px,
          #ffe082 20px
        );
        background-size: 28.28px 28.28px;
        animation: progress-stripes 1s linear infinite;
      }
      .stage-progress-fill.status-COMPLETED { background: linear-gradient(90deg, #81c784 0%, #66bb6a 100%); }
      .stage-progress-fill.status-FAILED { background: linear-gradient(90deg, #e57373 0%, #ef5350 100%); }
      .stage-count {
        font-size: 13px;
        color: #666;
        flex: 0 0 auto;
        min-width: 60px;
        text-align: right;
      }
      .stage-body {
        padding: 10px 15px;
        display: none;
      }
      .stage-body.expanded {
        display: block;
      }
      .task-row {
        padding: 8px 10px;
        margin: 5px 0;
        background: #fafafa;
        border-radius: 5px;
        display: flex;
        align-items: center;
        gap: 10px;
        font-size: 14px;
      }
      .task-name {
        flex: 0 0 300px;
        font-weight: 500;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .task-status-badge {
        padding: 4px 12px;
        border-radius: 12px;
        font-size: 12px;
        font-weight: bold;
        text-transform: uppercase;
        flex: 0 0 auto;
        width: 100px;
        text-align: center;
      }
      .task-status-badge.status-NOT_STARTED { background: #e0e0e0; color: #666; }
      .task-status-badge.status-STARTED { background: #ffd54f; color: #f57f17; }
      .task-status-badge.status-RUNNING { background: #ffd54f; color: #f57f17; animation: pulse 2s infinite; }
      .task-status-badge.status-COMPLETED { background: #81c784; color: #2e7d32; }
      .task-status-badge.status-FAILED { background: #e57373; color: #c62828; }
      .task-progress {
        flex: 0 0 250px;
        height: 20px;
        background: #e0e0e0;
        border-radius: 10px;
        overflow: hidden;
        position: relative;
      }
      .task-progress-fill {
        height: 100%;
        transition: width 0.5s ease;
        font-size: 11px;
        font-weight: bold;
        color: white;
        text-align: center;
        line-height: 20px;
      }
      .task-progress-fill.status-STARTED { background: linear-gradient(90deg, #ffd54f 0%, #ffb300 100%); }
      .task-progress-fill.status-RUNNING { 
        background: repeating-linear-gradient(
          45deg,
          #ffd54f,
          #ffd54f 10px,
          #ffe082 10px,
          #ffe082 20px
        );
        background-size: 28.28px 28.28px;
        animation: progress-stripes 1s linear infinite;
      }
      .task-progress-fill.status-COMPLETED { background: linear-gradient(90deg, #81c784 0%, #66bb6a 100%); }
      .task-message {
        flex: 1;
        font-size: 12px;
        color: #666;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      /* Item progress indicators */
      .item-progress {
        display: inline-block;
        padding: 2px 8px;
        background: #e3f2fd;
        border-radius: 4px;
        font-family: monospace;
        font-size: 11px;
        color: #1976d2;
        font-weight: 600;
      }
      .item-progress-pct {
        color: #0d47a1;
        margin-left: 4px;
      }
      /* Log viewer styles */
      .log-viewer-container {
        padding: 15px;
      }
      .log-header {
        display: flex;
        gap: 10px;
        align-items: center;
        margin-bottom: 10px;
        padding: 10px;
        background: #f8f9fa;
        border-radius: 4px;
      }
      .log-output {
        font-family: 'Courier New', monospace;
        background-color: #1e1e1e;
        color: #d4d4d4;
        padding: 15px;
        max-height: 600px;
        min-height: 400px;
        overflow-y: auto;
        white-space: pre-wrap;
        word-wrap: break-word;
        border-radius: 4px;
        border: 1px solid #333;
      }
      .log-line {
        margin: 2px 0;
      }
      .log-line-error {
        color: #f48771;
      }
      .log-line-warning {
        color: #dcdcaa;
      }
      .log-line-info {
        color: #4ec9b0;
      }
    "))
  ),
  
  tags$script(HTML("
    $(document).on('click', '.stage-header', function() {
      var stageBody = $(this).next('.stage-body');
      stageBody.toggleClass('expanded');
      
      // Get all currently expanded stage names
      var expanded = [];
      $('.stage-body.expanded').each(function() {
        var stageName = $(this).prev('.stage-header').find('.stage-name').text();
        expanded.push(stageName);
      });
      
      // Send to Shiny
      Shiny.setInputValue('expanded_stages', expanded, {priority: 'event'});
    });
  ")),
  
  tags$script(HTML("
    // After UI updates, restore expanded state
    $(document).on('shiny:value', function(event) {
      if (event.name === 'pipeline_status_ui') {
        setTimeout(function() {
          if (typeof Shiny !== 'undefined' && Shiny.inputBindings) {
            var expanded = Shiny.shinyapp.$inputValues.expanded_stages;
            if (expanded) {
              expanded.forEach(function(stageName) {
                $('.stage-name').filter(function() {
                  return $(this).text() === stageName;
                }).parent('.stage-header').next('.stage-body').addClass('expanded');
              });
            }
          }
        }, 50);
      }
    });
  ")),
  
  sidebarLayout(
