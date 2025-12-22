# Testing tasker

## Running Tests

Tests require a PostgreSQL database. Configure the connection by creating `.env.test`:

```bash
TASKER_TEST_DB_HOST=your-host
TASKER_TEST_DB_PORT=5432
TASKER_TEST_DB_NAME=your-database
TASKER_TEST_DB_USER=your-user
TASKER_TEST_DB_PASSWORD=your-password
```

Then run:

```r
devtools::test()
```

## Test Coverage

### Database Setup Tests (`test-setup.R`)
- Schema and table creation
- Views and functions creation  
- Triggers creation
- Force recreate existing schema
- Constraint enforcement
- **Catches SQL parsing errors** like unterminated dollar-quotes

### Configuration Tests (`test-config.R`)
- Config file loading
- Option storage and retrieval
- Environment variable override
- Config file search in parent directories

### Registration Tests (`test-register.R`)
- Task registration (single and batch)
- Retrieving registered tasks
- Filtering by stage and type

### Tracking Tests (`test-tracking.R`)
- Task start creates execution record with UUID
- Task update modifies state
- Task end finalizes execution
- Failure tracking with error details
- Progress calculation

### Subtask Tests (`test-subtask.R`)
- Subtask start within task
- Subtask progress tracking
- Subtask completion
- Multiple subtasks per task

### Query Tests (`test-query.R`)
- Fetching current task status
- Filtering by stage, status, hostname
- View functionality

## Test Database Requirements

Tests will be skipped if the test database is not available. This ensures the package can still be checked on CRAN without database access.
