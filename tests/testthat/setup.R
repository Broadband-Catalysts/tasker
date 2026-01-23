# Global test setup
# This file runs once before all tests

# Allow skip_backup=TRUE in all tests
options(tasker.confirm_skip_backup = TRUE)

# Disable auto-start of reporter in tests
options(tasker.process_reporter.auto_start = FALSE)
