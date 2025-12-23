#!/usr/bin/env Rscript
#
# reorganize_tasker_r_files.R
#
# Reorganizes tasker R files so each exported function is in its own file
#

# This script has already been executed manually via the Copilot assistant.
# The following files have been reorganized:
#
# Created:
#   - utils.R (internal helper functions)
#   - get_active_tasks.R
#   - get_subtask_progress.R
#   - get_stages.R
#   - get_task_history.R
#
# Remaining files to be kept as-is (already single-function files):
#   - create_tasker_config.R (create_tasker_config)
#   - get_db_connection.R (get_db_connection, plus create_schema helper)
#   - run_monitor.R (run_monitor)
#   - setup_tasker_db.R (setup_tasker_db)
#   - tasker_config.R (tasker_config, find_config_file, get_tasker_config)
#
# Files that still need reorganization:
#   - get_task_status.R (contains get_task_status and get_tasks alias)
#   - register_task.R (contains register_task, register_tasks, and duplicate get_tasks)
#   - task_start.R (contains task_start, task_update, task_complete, task_fail, task_end)
#   - subtask_start.R (contains subtask_start, subtask_update, subtask_complete, subtask_fail)
#
# Next steps: Continue creating individual files for remaining exported functions

message("Reorganization plan documented.")
message("See file comments for status and remaining work.")
