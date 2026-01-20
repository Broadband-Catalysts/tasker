#!/usr/bin/env Rscript
#
# auto_detect_demo.R
# Demonstrates automatic script detection and task lookup
#

# Load tasker package
suppressPackageStartupMessages(library(tasker))

# Make sure tasker is configured
if (!file.exists("~/.tasker.yml")) {
  stop("tasker not configured. Run create_tasker_config() first.")
}

# Load configuration
load_tasker_config()

# Get database connection
con <- get_db_connection()

# Register this demo script if not already registered
register_task(
  stage = "DEMO",
  name = "Auto Detect Demo",
  type = "R",
  description = "Demonstrates automatic script detection",
  script_filename = "auto_detect_demo.R",
  stage_order = 1,
  task_order = 1,
  conn = con
)

cat("\n=================================================================\n")
cat("Auto-Detection Demo\n")
cat("=================================================================\n\n")

# Demo 1: Auto-detection (NEW WAY - zero configuration!)
cat("Demo 1: Auto-detection\n")
cat("----------------------\n")
cat("Calling task_start() with no parameters...\n\n")

# This will:
# 1. Detect script filename: "auto_detect_demo.R"
# 2. Look up stage and task from database
# 3. Start tracking automatically
task_start()

subtask_start("Processing items", items_total = 5)

for (i in 1:5) {
  cat(sprintf("  Processing item %d...\n", i))
  Sys.sleep(0.5)
  subtask_increment(increment = 1)
}

subtask_complete()

task_complete()

cat("\n✓ Auto-detection completed successfully!\n")
cat("  Script detected: auto_detect_demo.R\n")
cat("  Stage: DEMO\n")
cat("  Task: Auto Detect Demo\n")

# Demo 2: Explicit parameters (OLD WAY - still works!)
cat("\n\nDemo 2: Explicit parameters (backward compatible)\n")
cat("--------------------------------------------------\n")
cat("Calling task_start('DEMO', 'Auto Detect Demo')...\n\n")

task_start("DEMO", "Auto Detect Demo")

subtask_start("Processing items", items_total = 3)

for (i in 1:3) {
  cat(sprintf("  Processing item %d...\n", i))
  Sys.sleep(0.5)
  subtask_increment(increment = 1)
}

subtask_complete()

task_complete()

cat("\n✓ Explicit parameters completed successfully!\n")

# Cleanup
dbDisconnect(con)

cat("\n=================================================================\n")
cat("Both methods work! Use auto-detection for simpler scripts.\n")
cat("=================================================================\n")
