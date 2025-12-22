library(tasker)

# Initialize the database
result <- setup_tasker_db()
cat("Database initialization result:", result, "\n")

# Check if view exists
status <- get_task_status()
print(status)
