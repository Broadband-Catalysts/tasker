# Enhanced UI for FCC Pipeline Monitor - Updated timestamp 2025-12-28
# Features: Single-page layout, dual progress bars, responsive design

library(shiny)
library(DT)
library(tasker)
library(dplyr)

# Configuration handling - load if not already loaded
if (is.null(getOption("tasker.config"))) {
  # Load configuration directly from the mounted location
  config_file <- "/home/warnes/src/fccData/.tasker.yml"
  
  if (file.exists(config_file)) {
    tryCatch({
      tasker::tasker_config(config_file = config_file)
    }, error = function(e) {
      stop("Failed to load tasker configuration: ", e$message)
    })
  } else {
    stop("Tasker configuration file not found at: ", config_file)
  }
}

# Add JavaScript for enhanced interactivity - must be before UI loading
addResourcePath("www", "www")

# Load the enhanced modular UI and Server
source("ui.R")
source("server.R")

# JavaScript for stage toggling and task interaction
js_code <- "
function toggleStage(header) {
  const tasks = header.nextElementSibling;
  const toggle = header.querySelector('.stage-toggle');
  
  if (tasks.style.display === 'none') {
    tasks.style.display = 'block';
    toggle.textContent = '▼';
  } else {
    tasks.style.display = 'none';
    toggle.textContent = '▶';
  }
}

// Enhanced task row click handler
$(document).on('click', '.task-row', function() {
  var taskName = $(this).find('.task-name').text();
  var taskId = $(this).data('task-id');
  var runId = $(this).data('run-id');
  
  // Show detailed view
  if (taskId) {
    $('#task-details-panel').addClass('open').show();
    $('#task-details-title').text('Details for: ' + taskName);
    
    // Trigger server to load task details
    Shiny.setInputValue('selected_task_id', taskId, {priority: 'event'});
    Shiny.setInputValue('selected_run_id', runId, {priority: 'event'});
  }
});

// Stage accordion handler  
$(document).on('click', '.stage-header', function() {
  const tasks = $(this).next('.stage-tasks');
  const toggle = $(this).find('.stage-toggle');
  
  tasks.slideToggle(300);
  toggle.text(function(i, text) {
    return text === '▼' ? '▶' : '▼';
  });
});

// Close task details panel
$(document).on('click', '.close-panel', function() {
  $('#task-details-panel').removeClass('open');
  setTimeout(function() {
    $('#task-details-panel').hide();
  }, 300);
});
"

# Enhanced UI with JavaScript
ui <- tagList(
  ui,
  tags$script(HTML(js_code))
)

SHINY_HOST <- Sys.getenv("SHINY_HOST", "0.0.0.0")
SHINY_PORT <- Sys.getenv("SHINY_PORT", "3838") |> as.numeric()


# Launch the enhanced Shiny app
shinyApp(ui = ui, server = server, options=list(host = SHINY_HOST, port = SHINY_PORT))