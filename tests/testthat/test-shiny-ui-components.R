# Tests for Shiny UI components and JavaScript integration
# Tests disconnection alert, reconnection logic, and UI enhancements

library(testthat)
library(shiny)
library(htmltools)

# Helper function to get source file paths (not installed package paths)
get_source_file <- function(rel_path) {
  # Get the package root directory
  pkg_root <- rprojroot::find_package_root_file()
  file.path(pkg_root, "inst", rel_path)
}

# shinyTZ is a required package - fail if not available
if (!requireNamespace("shinyTZ", quietly = TRUE)) {
  stop("shinyTZ package is required for tests. Install it with: remotes::install_github('Warnes-Innovations/shinyTZ')")
}

test_that("UI includes disconnection alert elements", {
  # Source the UI file in a clean environment
  ui_env <- new.env()
  ui_env$GIT_BRANCH <- "test"
  ui_env$BUILD_TIME <- "2026-01-01 00:00:00"
  
  # Load required libraries in the environment
  eval(quote({
    library(shiny)
    library(bslib)
    library(DT)
    library(dplyr)
    library(lubridate)
    library(shinyWidgets)
    library(shinyjs)
    library(shinyTZ)
  }), envir = ui_env)
  
  # Source the UI file from inst/ directory (development version)
  ui_file <- get_source_file("shiny/ui.R")
  source(ui_file, local = ui_env)
  
  # Get the UI object from the environment
  ui <- ui_env$ui
  
  # Convert UI to HTML
  ui_html <- as.character(ui)
  
  # Check for disconnection alert div
  expect_true(
    grepl('id="shiny-disconnection-alert"', ui_html, fixed = TRUE),
    "UI should contain disconnection alert div"
  )
  
  # Check for alert icon
  expect_true(
    grepl('class="alert-icon"', ui_html, fixed = TRUE),
    "UI should contain alert icon element"
  )
  
  # Check for alert message
  expect_true(
    grepl('class="alert-message"', ui_html, fixed = TRUE),
    "UI should contain alert message element"
  )
  
  # Check for alert submessage
  expect_true(
    grepl('class="alert-submessage"', ui_html, fixed = TRUE),
    "UI should contain alert submessage element"
  )
  
  # Check for "CONNECTION LOST" text
  expect_true(
    grepl("CONNECTION LOST", ui_html, fixed = TRUE),
    "UI should contain 'CONNECTION LOST' text"
  )
})

test_that("UI includes reconnection JavaScript", {
  # Source the UI file in a clean environment
  ui_env <- new.env()
  ui_env$GIT_BRANCH <- "test"
  ui_env$BUILD_TIME <- "2026-01-01 00:00:00"
  
  # Load required libraries
  eval(quote({
    library(shiny)
    library(bslib)
    library(DT)
    library(dplyr)
    library(lubridate)
    library(shinyWidgets)
    library(shinyjs)
    library(shinyTZ)
  }), envir = ui_env)
  
  # Source the UI file from inst/ directory (development version)
  ui_file <- get_source_file("shiny/ui.R")
  source(ui_file, local = ui_env)
  
  # Get the UI object
  ui <- ui_env$ui
  
  # Use renderTags to get ALL content including head
  rendered <- htmltools::renderTags(ui)
  ui_html <- paste(rendered$head, rendered$html, collapse = "\n")
  
  # Check for reconnection timer variable
  expect_true(
    grepl("var reconnectTimer", ui_html, fixed = TRUE),
    "UI should include reconnectTimer variable"
  )
  
  # Check for reconnection attempts variable
  expect_true(
    grepl("var reconnectAttempts", ui_html, fixed = TRUE),
    "UI should include reconnectAttempts variable"
  )
  
  # Check for shiny:disconnected event handler
  expect_true(
    grepl("shiny:disconnected", ui_html, fixed = TRUE),
    "UI should handle shiny:disconnected event"
  )
  
  # Check for shiny:connected event handler
  expect_true(
    grepl("shiny:connected", ui_html, fixed = TRUE),
    "UI should handle shiny:connected event"
  )
  
  # Check for reconnect() call
  expect_true(
    grepl("Shiny.shinyapp.reconnect", ui_html, fixed = TRUE),
    "UI should call Shiny.shinyapp.reconnect()"
  )
  
  # Check for setInterval for automatic reconnection
  expect_true(
    grepl("setInterval", ui_html, fixed = TRUE),
    "UI should use setInterval for reconnection attempts"
  )
})

test_that("UI includes CSS for disconnection alert", {
  # Read the CSS file from inst/ directory (development version)
  css_file <- get_source_file("shiny/www/styles.css")
  
  # Skip if file doesn't exist
  skip_if_not(file.exists(css_file), "CSS file not found")
  
  css_content <- paste(readLines(css_file, warn = FALSE), collapse = "\n")
  
  # Check for disconnection alert styles
  expect_true(
    grepl("#shiny-disconnection-alert", css_content, fixed = TRUE),
    "CSS should include disconnection alert styles"
  )
  
  # Check for alert-pulse animation
  expect_true(
    grepl("@keyframes alert-pulse", css_content, fixed = TRUE),
    "CSS should include alert-pulse animation"
  )
  
  # Check for alert components
  expect_true(
    grepl(".alert-icon", css_content, fixed = TRUE),
    "CSS should style alert icon"
  )
  
  expect_true(
    grepl(".alert-message", css_content, fixed = TRUE),
    "CSS should style alert message"
  )
  
  expect_true(
    grepl(".alert-submessage", css_content, fixed = TRUE),
    "CSS should style alert submessage"
  )
})

test_that("Refresh buttons include icons", {
  # Source the UI file in a clean environment
  ui_env <- new.env()
  ui_env$GIT_BRANCH <- "test"
  ui_env$BUILD_TIME <- "2026-01-01 00:00:00"
  
  # Load required libraries
  eval(quote({
    library(shiny)
    library(bslib)
    library(DT)
    library(dplyr)
    library(lubridate)
    library(shinyWidgets)
    library(shinyjs)
    library(shinyTZ)
  }), envir = ui_env)
  
  # Source the UI file from inst/ directory (development version)
  ui_file <- get_source_file("shiny/ui.R")
  source(ui_file, local = ui_env)
  
  # Get the UI object
  ui <- ui_env$ui
  
  # Convert UI to HTML
  ui_html <- as.character(ui)
  
  # Check for refresh_structure button with icon
  expect_true(
    grepl('id="refresh_structure"', ui_html, fixed = TRUE),
    "UI should contain refresh_structure button"
  )
  
  # Check for refresh button with icon
  expect_true(
    grepl('id="refresh"', ui_html, fixed = TRUE),
    "UI should contain refresh button"
  )
  
  # Check for rotate-right icon (Font Awesome)
  expect_true(
    grepl("rotate-right", ui_html, fixed = TRUE),
    "UI should include rotate-right icon"
  )
})

test_that("Disconnection alert has proper structure", {
  # Source the UI file in a clean environment
  ui_env <- new.env()
  ui_env$GIT_BRANCH <- "test"
  ui_env$BUILD_TIME <- "2026-01-01 00:00:00"
  
  # Load required libraries
  eval(quote({
    library(shiny)
    library(bslib)
    library(DT)
    library(dplyr)
    library(lubridate)
    library(shinyWidgets)
    library(shinyjs)
    library(shinyTZ)
  }), envir = ui_env)
  
  # Source the UI file from inst/ directory (development version)
  ui_file <- get_source_file("shiny/ui.R")
  source(ui_file, local = ui_env)
  
  # Get the UI object
  ui <- ui_env$ui
  
  # Find the disconnection alert in the UI tree
  ui_list <- as.list(ui)
  
  # Function to recursively search for element by id
  find_element_by_id <- function(ui_obj, target_id) {
    if (is.list(ui_obj)) {
      # Check if this element has the target id
      if (!is.null(ui_obj$attribs) && !is.null(ui_obj$attribs$id) && 
          ui_obj$attribs$id == target_id) {
        return(ui_obj)
      }
      # Recursively search children
      for (child in ui_obj) {
        result <- find_element_by_id(child, target_id)
        if (!is.null(result)) return(result)
      }
    }
    return(NULL)
  }
  
  # Find the alert element
  alert_element <- find_element_by_id(ui, "shiny-disconnection-alert")
  
  # This test might not work if the UI structure is different than expected
  # So we'll make it informational rather than failing
  if (!is.null(alert_element)) {
    expect_true(TRUE, "Disconnection alert element found in UI tree")
  } else {
    # Alternative: check that the HTML string contains the structure
    ui_html <- as.character(ui)
    expect_true(
      grepl('<div id="shiny-disconnection-alert"', ui_html, fixed = TRUE),
      "Disconnection alert should be present in rendered HTML"
    )
  }
})

test_that("Reconnection JavaScript has proper error handling", {
  # Source the UI file in a clean environment
  ui_env <- new.env()
  ui_env$GIT_BRANCH <- "test"
  ui_env$BUILD_TIME <- "2026-01-01 00:00:00"
  
  # Load required libraries
  eval(quote({
    library(shiny)
    library(bslib)
    library(DT)
    library(dplyr)
    library(lubridate)
    library(shinyWidgets)
    library(shinyjs)
    library(shinyTZ)
  }), envir = ui_env)
  
  # Source the UI file from inst/ directory (development version)
  ui_file <- get_source_file("shiny/ui.R")
  source(ui_file, local = ui_env)
  
  # Get the UI object
  ui <- ui_env$ui
  
  # Use renderTags to get ALL content including head
  rendered <- htmltools::renderTags(ui)
  ui_html <- paste(rendered$head, rendered$html, collapse = "\n")
  
  # Check for clearInterval to prevent multiple timers
  expect_true(
    grepl("clearInterval(reconnectTimer)", ui_html, fixed = TRUE),
    "JavaScript should clear existing reconnection timer"
  )
  
  # Check for existence check before calling reconnect
  expect_true(
    grepl("if (Shiny && Shiny.shinyapp && Shiny.shinyapp.reconnect)", ui_html, fixed = TRUE),
    "JavaScript should check if Shiny.shinyapp.reconnect exists before calling"
  )
  
  # Check for console logging
  expect_true(
    grepl("console.log", ui_html, fixed = TRUE),
    "JavaScript should include console logging for debugging"
  )
})

test_that("CSS has proper z-index for alert visibility", {
  # Read the CSS file from inst/ directory (development version)
  css_file <- get_source_file("shiny/www/styles.css")
  
  # Skip if file doesn't exist
  skip_if_not(file.exists(css_file), "CSS file not found in installed package")
  
  css_content <- paste(readLines(css_file, warn = FALSE), collapse = "\n")
  
  # Check for high z-index
  expect_true(
    grepl("z-index:\\s*99999", css_content),
    "Disconnection alert should have high z-index to appear above other content"
  )
  
  # Check for fixed positioning
  expect_true(
    grepl("position:\\s*fixed", css_content),
    "Disconnection alert should use fixed positioning"
  )
  
  # Check for centered positioning
  expect_true(
    grepl("top:\\s*50%", css_content) && grepl("left:\\s*50%", css_content),
    "Disconnection alert should be centered"
  )
  
  # Check for transform centering
  expect_true(
    grepl("transform:\\s*translate\\(-50%,\\s*-50%\\)", css_content),
    "Disconnection alert should use transform for perfect centering"
  )
})
