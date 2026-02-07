# Teardown: Clean up any orphaned reporter processes after all tests
#
# This runs after all test files complete to ensure no reporter processes
# are left running that could exhaust database connections.

message("\n=== Teardown: Cleaning up reporter processes ===")

result <- cleanup_test_reporters(timeout = 3, quiet = FALSE)

if (result$found > 0) {
  message(sprintf(
    "Cleaned up %d orphaned reporter process%s (%d stopped, %d failed)",
    result$found,
    if (result$found == 1) "" else "es",
    result$stopped,
    result$failed
  ))
  
  if (result$failed > 0) {
    warning(sprintf(
      "%d reporter process%s could not be stopped and may still be running",
      result$failed,
      if (result$failed == 1) "" else "es"
    ))
  }
} else {
  message("No orphaned reporter processes found")
}

message("=== Teardown complete ===\n")
