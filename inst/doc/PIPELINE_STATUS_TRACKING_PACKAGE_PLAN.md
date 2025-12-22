# tasker: R Package for Pipeline Status Tracking

**Date:** 2025-12-20  
**Status:** ✅ Initial Implementation Complete

**Repository:** https://github.com/Broadband-Catalysts/tasker

---

## Package Overview

### Name: `tasker`

**Tagline:** Database-backed task and pipeline execution tracking for R

**Description:** 
`tasker` provides a simple, database-backed system for tracking the execution status, progress, and performance of R scripts and pipelines. It enables real-time monitoring, historical analysis, and performance optimization of complex data processing workflows.

**Key Features:**
- 📊 **Three-level tracking** - Stage/Task/Subtask hierarchy for complete visibility
- 💾 **Database-backed** - PostgreSQL storage for persistence and querying
- 🔄 **Real-time updates** - Monitor running tasks with second-level granularity
- 📈 **Historical analytics** - Track performance trends over time
- 🎯 **Drop-in integration** - Minimal code changes required
- 🐍 **Multi-language** - R and Python support
- 🛡️ **Fail-safe** - Tracking failures don't halt execution
- 🚀 **Production-ready** - Designed for enterprise data pipelines
- 📝 **Task registration** - Pre-register tasks for proactive monitoring

---

## Repository Structure

```
tasker/
├── README.md
├── DESCRIPTION
├── NAMESPACE
├── LICENSE (GPL-3)
├── NEWS.md
├── TODO.md
├── .Rbuildignore
├── .gitignore
├── .github/
│   └── workflows/
│       ├── R-CMD-check.yaml
│       └── pkgdown.yaml
├── R/
│   ├── track_init.R
│   ├── track_status.R
│   ├── track_finish.R
│   ├── track_error.R
│   ├── track_subtask_progress.R
│   ├── register_task.R
│   ├── register_tasks.R
│   ├── get_tasks.R
│   ├── connection.R
│   ├── schema.R
│   ├── helpers.R
│   └── zzz.R (package hooks)
├── inst/
│   ├── sql/
│   │   ├── postgresql/
│   │   │   ├── create_schema.sql
│   │   │   └── queries.sql
│   │   └── generic/
│   │       └── common_queries.sql
│   ├── python/
│   │   └── tasker.py
│   ├── shiny/
│   │   ├── app.R
│   │   ├── ui.R
│   │   ├── server.R
│   │   └── www/
│   │       └── custom.css
│   └── examples/
│       ├── simple_script.R
│       ├── parallel_processing.R
│       └── monitor_usage.R
├── man/
│   └── (auto-generated roxygen docs)
├── tests/
│   └── testthat/
│       ├── test-tracking.R
│       ├── test-connection.R
│       └── test-progress.R
├── vignettes/
│   ├── getting-started.Rmd
│   ├── advanced-usage.Rmd
│   ├── monitoring-dashboard.Rmd
│   └── python-integration.Rmd
└── pkgdown/
    └── _pkgdown.yml
```

---

## Package API Design

### Core Functions

#### 1. Task Registration

```r
#' Register a single task for monitoring
#'
#' @param stage Stage name (e.g., "PREREQ", "DAILY", "MONTHLY")
#' @param name Task name
#' @param type Task type: "R", "python", "sh", etc. (default: "R")
#' @param description Optional task description
#' @param total_subtasks Expected number of subtasks
#' @param expected_duration_minutes Expected runtime in minutes
#' @param schedule Optional cron schedule string
#' @export
register_task(stage, name, type = "R", description = NULL, 
              total_subtasks = NULL, expected_duration_minutes = NULL,
              schedule = NULL)

#' Register multiple tasks from data frame
#'
#' @param tasks_df Data frame with columns: stage, name, type, description, 
#'   total_subtasks, expected_duration_minutes, schedule
#' @export
register_tasks(tasks_df)

#' Get registered tasks
#'
#' @param stage Filter by stage (optional)
#' @param enabled Show only enabled tasks (default: TRUE)
#' @param conn Database connection (optional)
#' @return Data frame of registered tasks
#' @export
get_tasks(stage = NULL, enabled = TRUE, conn = NULL)
```

#### 2. Initialization

```r
#' Initialize task tracking
#'
#' @param task_name Name of the task being tracked
#' @param total_subtasks Expected number of subtasks (optional)
#' @param stage Stage (auto-detected if NULL)
#' @param db_conn Database connection (optional, uses default if NULL)
#' @return Tracking ID (UUID)
#' @export
track_init(task_name, total_subtasks = NULL, stage = NULL, db_conn = NULL)
```

#### 3. Status Updates

```r
#' Update task status
#'
#' @param status Execution status: "STARTED", "RUNNING", "FINISHED", "FAILED"
#' @param current_subtask Current subtask number (optional)
#' @param subtask_name Subtask description (optional)
#' @param subtask_status Status of current subtask (optional)
#' @param overall_percent Overall progress 0-100 (optional)
#' @param overall_message Overall progress message (optional)
#' @param subtask_percent Subtask progress 0-100 (optional)
#' @param subtask_message Subtask progress message (optional)
#' @param subtask_items_complete Items completed in current subtask (optional)
#' @param subtask_items_total Total items in current subtask (optional)
#' @export
track_status(status = "RUNNING", ...)
```

#### 4. Subtask Progress

```r
#' Update progress within current subtask
#'
#' @param items_complete Number of items completed
#' @param items_total Total items (optional)
#' @param message Progress message (optional)
#' @export
track_subtask_progress(items_complete, items_total = NULL, message = NULL)
```

#### 5. Completion

```r
#' Mark task as successfully completed
#'
#' @param message Completion message (optional)
#' @export
track_finish(message = "Task completed successfully")

#' Record task failure
#'
#' @param error_msg Error message
#' @param error_detail Detailed error info (optional)
#' @export
track_error(error_msg, error_detail = NULL)
```

### Configuration Functions

```r
#' Load or set tasker configuration
#'
#' @param config_file Path to .tasker.yml config file (optional)
#' @param host Database host (overrides config file)
#' @param port Database port (overrides config file)
#' @param dbname Database name (overrides config file)
#' @param user Username (overrides config file)
#' @param password Password (overrides config file)
#' @param schema Schema name (overrides config file, default: "tasker")
#' @param driver Database driver (overrides config file, default: "postgresql")
#' @param reload Force reload configuration (default: FALSE)
#' @export
tasker_config(config_file = NULL, host = NULL, port = NULL, dbname = NULL,
              user = NULL, password = NULL, schema = NULL, driver = NULL,
              reload = FALSE)

#' Get current configuration
#'
#' @return List with configuration settings
#' @export
get_tasker_config()

#' Find .tasker.yml configuration file
#'
#' @param start_dir Starting directory (default: current working directory)
#' @param filename Configuration filename (default: ".tasker.yml")
#' @param max_depth Maximum directory levels to search up (default: 10)
#' @return Path to config file, or NULL if not found
#' @export
find_config_file(start_dir = getwd(), filename = ".tasker.yml", max_depth = 10)

#' Get current database connection
#'
#' @return DBI connection object
#' @export
get_db_connection()

#' Create tasker database schema
#'
#' @param conn Database connection
#' @param schema Schema name (default: "tasker")
#' @export
create_schema(conn, schema = "tasker")
```

### Query Functions

```r
#' Get current status of all tracked tasks
#'
#' @param conn Database connection (optional)
#' @return Data frame with current status
#' @export
get_current_status(conn = NULL)

#' Get execution history
#'
#' @param task_name Filter by task name (optional)
#' @param stage Filter by stage (optional)
#' @param start_date Filter by start date (optional)
#' @param end_date Filter by end date (optional)
#' @param conn Database connection (optional)
#' @return Data frame with execution history
#' @export
get_execution_history(task_name = NULL, stage = NULL,
                      start_date = NULL, end_date = NULL, conn = NULL)

#' Get performance statistics
#'
#' @param task_name Task name
#' @param conn Database connection (optional)
#' @return List with performance metrics
#' @export
get_performance_stats(task_name, conn = NULL)
```

---

## Database Schema

The package will create and manage its own schema in PostgreSQL:

```sql
-- Schema: tasker
CREATE SCHEMA IF NOT EXISTS tasker;

-- Table: tasker.tasks
-- Registry of expected/known tasks for monitoring dashboard
CREATE TABLE tasker.tasks (
    task_id SERIAL PRIMARY KEY,
    task_name VARCHAR(255) NOT NULL UNIQUE,
    task_stage VARCHAR(50),
    task_type VARCHAR(10) DEFAULT 'R',
    description TEXT,
    total_subtasks INTEGER,
    expected_duration_minutes NUMERIC(10,2),
    schedule VARCHAR(100),
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_tasks_stage ON tasker.tasks(task_stage);
CREATE INDEX idx_tasks_enabled ON tasker.tasks(enabled) WHERE enabled = TRUE;

-- Table: tasker.executions
-- Main table tracking individual task executions
CREATE TABLE tasker.executions (
    execution_id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL UNIQUE,
    task_name VARCHAR(255) NOT NULL,
    task_stage VARCHAR(50),
    task_type VARCHAR(10) DEFAULT 'R',
    
    hostname VARCHAR(255) NOT NULL,
    process_id INTEGER NOT NULL,
    user_name VARCHAR(100),
    
    script_path VARCHAR(500),
    script_file VARCHAR(255),
    log_path VARCHAR(500),
    log_file VARCHAR(255),
    
    execution_start TIMESTAMPTZ NOT NULL,
    execution_end TIMESTAMPTZ,
    last_update TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    execution_status VARCHAR(20) NOT NULL,
    
    total_subtasks INTEGER,
    current_subtask INTEGER,
    subtask_name VARCHAR(500),
    subtask_status VARCHAR(20),
    
    overall_percent_complete NUMERIC(5,2),
    overall_progress_message TEXT,
    
    subtask_percent_complete NUMERIC(5,2),
    subtask_progress_message TEXT,
    subtask_items_total BIGINT,
    subtask_items_complete BIGINT,
    
    memory_mb INTEGER,
    cpu_percent NUMERIC(5,2),
    
    error_message TEXT,
    error_detail TEXT,
    
    git_commit VARCHAR(40),
    environment JSONB,
    
    CONSTRAINT chk_status CHECK (execution_status IN 
        ('STARTED', 'RUNNING', 'FINISHED', 'FAILED', 'CANCELLED'))
);

-- Indexes
CREATE INDEX idx_executions_run_id ON tasker.executions(run_id);
CREATE INDEX idx_executions_task_name ON tasker.executions(task_name);
CREATE INDEX idx_executions_task_stage ON tasker.executions(task_stage);
CREATE INDEX idx_executions_status ON tasker.executions(execution_status);
CREATE INDEX idx_executions_start_time ON tasker.executions(execution_start);
CREATE INDEX idx_executions_latest ON tasker.executions(task_name, execution_start DESC);

-- Views
CREATE VIEW tasker.current_status AS
SELECT DISTINCT ON (task_name)
    execution_id,
    run_id,
    task_name,
    task_stage,
    task_type,
    execution_status,
    execution_start,
    last_update,
    current_subtask,
    total_subtasks,
    overall_percent_complete,
    subtask_percent_complete,
    overall_progress_message,
    subtask_progress_message
FROM tasker.executions
ORDER BY task_name, execution_start DESC;

-- View: Monitoring dashboard view with registered tasks
CREATE VIEW tasker.monitoring_view AS
SELECT 
    t.task_name,
    t.task_stage,
    t.task_type,
    t.description,
    t.schedule,
    t.expected_duration_minutes,
    c.execution_status,
    c.execution_start,
    c.last_update,
    c.overall_percent_complete,
    c.subtask_percent_complete,
    c.overall_progress_message,
    c.subtask_progress_message,
    CASE 
        WHEN c.execution_status IS NULL THEN 'NOT_STARTED'
        ELSE c.execution_status
    END as display_status
FROM tasker.tasks t
LEFT JOIN tasker.current_status c ON t.task_name = c.task_name
WHERE t.enabled = TRUE
ORDER BY t.task_stage, t.task_name;
```

---

## Configuration

### Configuration File (Recommended)

**`.tasker.yml`** in project root:

```yaml
database:
  host: db.example.com
  port: 5432
  dbname: geodb
  user: tasker_user
  password: ${TASKER_DB_PASSWORD}  # From environment
  schema: tasker
  driver: postgresql

pool:
  min_size: 1
  max_size: 5
  idle_timeout: 300
```

**Usage:**

```r
library(tasker)

# Auto-discovers .tasker.yml in project root
# Configuration loaded automatically on first function call
track_init("my_script.R")

# Or load explicitly
tasker_config()

# Override specific settings
tasker_config(host = "localhost", port = 5433)
```

### Configuration Precedence

1. **Explicit parameters** to `tasker_config()`
2. **Environment variables** (`TASKER_DB_HOST`, etc.)
3. **Configuration file** (`.tasker.yml`)
4. **Built-in defaults**

### Environment Variables

```bash
# ~/.Renviron or .env
TASKER_DB_HOST=localhost
TASKER_DB_PORT=5432
TASKER_DB_NAME=geodb
TASKER_DB_USER=tasker_user
TASKER_DB_PASSWORD=<secure>
TASKER_DB_SCHEMA=tasker
TASKER_DB_DRIVER=postgresql
```

### Programmatic Configuration

```r
# Option 1: Configuration file (recommended)
tasker_config()  # Auto-discovers .tasker.yml

# Option 2: Environment variables
# Set in ~/.Renviron, then:
library(tasker)
# Configuration loaded automatically

# Option 3: Explicit configuration
tasker_config(
  host = "db.example.com",
  port = 5432,
  dbname = "geodb",
  user = "tasker_user",
  password = keyring::key_get("tasker_db"),
  schema = "tasker",
  driver = "postgresql"
)

# Option 4: Specific config file
tasker_config(config_file = "/path/to/custom.yml")

# Option 5: Custom connection per call
conn <- DBI::dbConnect(RPostgres::Postgres(), ...)
track_init("my_script.R", db_conn = conn)
```

### Configuration Discovery

`tasker` searches up the directory tree for `.tasker.yml`:

```
/home/user/project/
├── .tasker.yml          ← Found here!
├── scripts/
│   └── daily/
│       └── script.R     ← Running from here
└── data/
```

```r
# Find configuration file
config_path <- find_config_file()
# Returns: "/home/user/project/.tasker.yml"

# Search from specific directory
find_config_file("/home/user/project/scripts/daily")
# Searches: ./,  ../, ../../, etc.
```

---

## Usage Examples

### Basic Usage

```r
library(tasker)

# Initialize tracking
track_init("data_processing.R", total_subtasks = 3, stage = "DAILY")

# Subtask 1
track_status(current_subtask = 1, subtask_name = "Loading data")
data <- read.csv("input.csv")
track_status(subtask_status = "COMPLETED")

# Subtask 2
track_status(current_subtask = 2, subtask_name = "Processing data")
for (i in seq_len(nrow(data))) {
  process_row(data[i, ])
  if (i %% 100 == 0) {
    track_subtask_progress(i, nrow(data), "Processing row {i}")
  }
}
track_status(subtask_status = "COMPLETED")

# Subtask 3
track_status(current_subtask = 3, subtask_name = "Saving results")
write.csv(results, "output.csv")
track_status(subtask_status = "COMPLETED")

# Finish
track_finish("Successfully processed {nrow(data)} rows")
```

### With Error Handling

```r
library(tasker)

tryCatch({
  track_init("risky_script.R", stage = "PROCESSING")
  
  # Do work
  track_status(task_name = "Dangerous operation")
  risky_function()
  
  track_finish()
  
}, error = function(e) {
  track_error(
    error_msg = conditionMessage(e),
    error_detail = as.character(traceback())
  )
  stop(e)
})
```

### Parallel Processing

```r
library(tasker)
library(parallel)

track_init("parallel_script.R", total_tasks = 56, stage = "PARALLEL")

cl <- makeCluster(8)
clusterEvalQ(cl, library(tasker))

results <- parLapply(cl, states, function(state) {
  # Each worker gets its own tracking
  run_id <- track_init(paste0("process_", state), stage = "WORKER")
  
  track_status(task_name = "Processing state")
  result <- process_state(state)
  
  track_finish()
  result
})

stopCluster(cl)
track_finish("All states processed")
```

### Registering Tasks for Monitoring

```r
# Register individual tasks
register_task(stage = "PREREQ", name = "Install System Dependencies", type = "sh")
register_task(stage = "PREREQ", name = "Install R", type = "sh")

# Or register with full details
register_task(
  stage = "DAILY",
  name = "DAILY_01_BDC_Locations.R",
  type = "R",
  description = "Load BDC location data",
  total_subtasks = 56,
  expected_duration_minutes = 120,
  schedule = "0 2 * * *"
)

# Or register multiple tasks from data frame
tasks_df <- data.frame(
  stage = c("DAILY", "DAILY"),
  name = c("DAILY_01_BDC_Locations.R", "DAILY_02_Provider_Tables.R"),
  type = c("R", "R"),
  description = c("Load BDC location data", "Update provider tables"),
  total_subtasks = c(56, 10),
  expected_duration_minutes = c(120, 30),
  schedule = c("0 2 * * *", "0 4 * * *")
)

register_tasks(tasks_df)
```

### Querying Status

```r
# Get current running tasks
status <- get_current_status()
print(status)

# Get execution history
history <- get_execution_history(
  task_name = "data_processing.R",
  stage = "DAILY",
  start_date = Sys.Date() - 30
)

# Get performance stats
stats <- get_performance_stats("data_processing.R")
cat(sprintf("Average runtime: %.1f minutes\n", stats$avg_duration_min))
cat(sprintf("Success rate: %.1f%%\n", stats$success_rate))

# Get registered tasks for monitoring
registered <- get_tasks()
daily_tasks <- get_tasks(stage = "DAILY")
```

---

## Integration with fccData

Once the `tasker` package is created, integrate it into `fccData`:

### 1. Add Dependency

In `fccData/DESCRIPTION`:
```
Imports:
    tasker (>= 0.1.0),
    ...
```

### 2. Create Wrapper Functions (Optional)

In `fccData/R/track_status.R`:
```r
#' @export
genter <- function(message) {
  message_text <- glue::glue(message, .envir = parent.frame())
  
  if (is.null(getOption("fcc_pipeline_run_id"))) {
    script_name <- get_script_name()
    stage <- detect_pipeline_stage(script_name)  # DAILY, ANNUAL_DEC, etc.
    run_id <- tasker::track_init(script_name, stage = stage)
    options(fcc_pipeline_run_id = run_id)
  }
  
  current_task <- getOption("fcc_pipeline_current_task", 0) + 1
  options(fcc_pipeline_current_task = current_task)
  
  tasker::track_status(
    current_task = current_task,
    task_name = as.character(message_text)
  )
}

#' @export
gexit <- function() {
  tasker::track_status(subtask_status = "COMPLETED")
}

#' @export
gmessage <- function(message) {
  message_text <- glue::glue(message, .envir = parent.frame())
  tasker::track_status(subtask_message = as.character(message_text))
}
```

### 3. Configure Database

In `fccData/inst/scripts/` or startup:
```r
# Use same database as fccData (geodb)
tasker::configure_db(
  host = Sys.getenv("DB_HOST", "db.example.com"),
  port = 5432,
  dbname = "geodb",  # fccData monitoring database
  user = Sys.getenv("MONITOR_DB_USER"),
  password = Sys.getenv("MONITOR_DB_PASSWORD"),
  schema = "tasker",
  driver = "postgresql"
)

# Register fccData pipeline tasks
fcc_pipeline_tasks <- read.csv(system.file("config/pipeline_tasks.csv", 
                                            package = "fccData"))
tasker::register_tasks(fcc_pipeline_tasks)
```

---

## Development Plan

### Phase 1: Core Package (Week 1)
- [ ] Create GitHub repository: `warnes/tasker`
- [ ] Set up package structure with GPL-3 license
- [ ] Implement core tracking functions
- [ ] Create PostgreSQL database schema
- [ ] Write generic SQL where possible
- [ ] Create TODO.md for future database support
- [ ] Write unit tests
- [ ] Basic documentation

### Phase 2: Features (Week 2)
- [ ] Add query functions (`get_current_status()`, `get_execution_history()`, etc.)
- [ ] Implement connection management
- [ ] Add configuration system
- [ ] Create `tasker.tasks` table for task registration
- [ ] Implement `register_task()` and `register_tasks()` functions
- [ ] Implement `get_tasks()` function
- [ ] Error handling and validation
- [ ] Performance optimization

### Phase 3: Documentation (Week 3)
- [ ] Write comprehensive README
- [ ] Create vignettes
- [ ] Add usage examples
- [ ] Set up pkgdown website
- [ ] API reference documentation

### Phase 4: Monitoring Dashboard & Python (Week 4)
- [ ] Create Shiny monitoring app with:
  - [ ] Real-time status display with auto-refresh
  - [ ] Stage grouping and filtering
  - [ ] Details modal for each task showing:
    - [ ] Full task metadata (hostname, PID, user, times)
    - [ ] Script path and file location
    - [ ] Log path and file location
    - [ ] Live log tail for running tasks (auto-updating)
    - [ ] Static log view for completed/failed tasks
    - [ ] Error details for failed tasks
    - [ ] Progress visualization (progress bars)
    - [ ] Subtask timeline/history
  - [ ] Historical view with filtering
  - [ ] Performance charts
- [ ] Integrate with registered_tasks table
- [ ] Create Python module (tasker.py)
- [ ] Test R/Python interoperability
- [ ] Python examples
- [ ] Python documentation

### Phase 5: Polish & CRAN Prep (Week 5)
- [ ] CI/CD setup (GitHub Actions)
- [ ] Code coverage (aim for >90%)
- [ ] CRAN submission checks (`R CMD check --as-cran`)
- [ ] Address all NOTEs and WARNINGs
- [ ] Polish documentation
- [ ] Community feedback
- [ ] Version 0.1.0 release to GitHub
- [ ] CRAN submission

### Phase 6: Integration (Week 6)
- [ ] Integrate into fccData
- [ ] Create fccData-specific wrappers
- [ ] Update fccData scripts
- [ ] Test full pipeline

---

## Dependencies

### Required
- **R (>= 4.0.0)**
- **DBI** - Database interface
- **RPostgres** - PostgreSQL driver
- **uuid** - UUID generation
- **jsonlite** - JSON handling

### Suggested
- **glue** - String interpolation
- **cli** - Pretty console output
- **keyring** - Secure password storage
- **pool** - Connection pooling

### Development
- **testthat** - Testing
- **roxygen2** - Documentation
- **pkgdown** - Website
- **covr** - Code coverage

---

## Testing Strategy

### Unit Tests
- Connection management
- Status updates
- Query functions
- Error handling
- Schema creation

### Integration Tests
- Full workflow tests
- Database transactions
- Parallel execution
- Python integration

### Performance Tests
- Update frequency
- Query performance
- Connection pooling
- Memory usage

---

## Documentation Requirements

### README.md
- Package overview
- Quick start example
- Installation instructions
- Basic usage
- Links to detailed docs

### Vignettes
1. **Getting Started** - Basic tracking workflow
2. **Advanced Usage** - Complex scenarios, parallel processing
3. **Monitoring Dashboard** - Building custom monitors
4. **Python Integration** - Using from Python

### Function Documentation
- All exported functions fully documented
- Parameter descriptions
- Return value documentation
- Usage examples
- See also references

---

## Licensing

**Selected: GPL-3 License**

Rationale:
- **Copyleft** - ensures derivative works remain open source
- **Strong community** - aligns with R ecosystem standards
- **Protection** - prevents proprietary forks
- **Compatible** - works with most R packages
- **Standard** - widely used in R community (base R is GPL)

---

## GitHub Repository Setup

### Repository Name
`tasker`

### Repository Description
"Database-backed execution tracking for R and Python pipelines with dual-level progress monitoring"

### Topics/Tags
- r
- r-package
- pipeline
- monitoring
- postgresql
- task-tracking
- data-pipeline
- progress-tracking
- execution-monitoring

### Badges (in README)
```markdown
[![R-CMD-check](https://github.com/warnes/tasker/workflows/R-CMD-check/badge.svg)](https://github.com/warnes/tasker/actions)
[![Codecov](https://codecov.io/gh/warnes/tasker/branch/main/graph/badge.svg)](https://codecov.io/gh/warnes/tasker)
[![CRAN status](https://www.r-pkg.org/badges/version/tasker)](https://CRAN.R-project.org/package=tasker)
[![License: GPL-3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Downloads](https://cranlogs.r-pkg.org/badges/tasker)](https://cran.r-project.org/package=tasker)
```

### Branch Strategy
- `main` - stable releases
- `develop` - active development
- `feature/*` - feature branches
- `hotfix/*` - urgent fixes

---

## Release Strategy

### Version Numbering
Follow semantic versioning: `MAJOR.MINOR.PATCH`

### Initial Releases
- **0.1.0** - Initial release with core functionality
- **0.2.0** - Add Python support
- **0.3.0** - Add query/analysis functions
- **1.0.0** - Production-ready, stable API

### Release Checklist
- [ ] All tests passing
- [ ] Documentation complete
- [ ] NEWS.md updated
- [ ] Version bumped
- [ ] CRAN checks pass
- [ ] Git tag created
- [ ] GitHub release created

---

## Community & Support

### Communication Channels
- **GitHub Issues** - Bug reports, feature requests
- **GitHub Discussions** - Questions, ideas
- **Stack Overflow** - Tag: `r-tasktracker`

### Contributing Guidelines
- Code of conduct
- How to report issues
- How to submit PRs
- Coding standards
- Testing requirements

### Roadmap (Future Features)
- **v0.2.0**: Support for SQLite (see TODO.md)
- **v0.3.0**: Support for MySQL/MariaDB (see TODO.md)
- **v0.4.0**: Alerting/notification system
- **v0.5.0**: Integration with logging frameworks
- **v1.1.0**: Distributed execution tracking
- **v1.2.0**: Enhanced resource usage monitoring
- **Future**: Cost tracking for cloud workloads

---

## Success Metrics

### Technical
- [ ] All functions tested (>90% coverage)
- [ ] No critical bugs
- [ ] Performance acceptable (<50ms overhead per update)
- [ ] Works on R 4.0+
- [ ] CRAN submission ready

### Adoption
- [ ] Used in fccData production pipeline
- [ ] 50+ GitHub stars
- [ ] 10+ users reported
- [ ] 3+ external use cases

### Quality
- [ ] Documentation complete
- [ ] Examples working
- [ ] Vignettes comprehensive
- [ ] Community feedback positive

---

## Next Steps

1. **Review this plan** - Gather feedback
2. **Create repository** - Set up GitHub project with GPL-3 license
3. **Initialize package** - Use `usethis::create_package("tasker")`
4. **Create TODO.md** - Document future database support tasks
4. **Implement core** - Start with tracking functions
5. **Test thoroughly** - Unit and integration tests
6. **Document well** - README and vignettes
7. **Release v0.1.0** - Initial version
8. **Integrate** - Add to fccData

---

## Design Decisions Summary

1. ✅ **Package name**: `tasker` (task + tracker)
2. ✅ **License**: GPL-3 (copyleft protection)
3. ✅ **Database support**: PostgreSQL initially, generic SQL for future extensibility (TODO.md)
4. ✅ **Python packaging**: Bundled with R package in `inst/python/`
5. ✅ **Monitoring dashboard**: Include basic Shiny app in `inst/shiny/`
6. ✅ **CRAN submission**: Plan for CRAN from start
7. ✅ **Terminology**: 
   - **Stage** = Pipeline phase (e.g., PREREQ, DAILY, MONTHLY)
   - **Task** = Work unit (e.g., "Install R", "DAILY_01_BDC_Locations.R")
   - **Subtask** = Items within task (e.g., states, files, rows)
8. ✅ **Registration system**: 
   - `tasker.tasks` table for registered tasks
   - Simple API: `register_task(stage, name, type)`
   - Batch API: `register_tasks(data_frame)`
   - Query API: `get_tasks(stage)`

---

## Quick Reference: Terminology

```
Stage (PREREQ, DAILY, MONTHLY...)
  ├─ Task (Install R, DAILY_01_BDC_Locations.R...)
  │   ├─ Subtask (State 1, State 2...)
  │   └─ Subtask
  └─ Task
```

**Hierarchy:**
- **Stage** groups related **Tasks**
- **Task** is a single executable unit
- **Subtask** tracks progress within a **Task**

**Function Naming:**
- `register_task()` / `register_tasks()` - Register tasks for monitoring
- `get_tasks()` - Query registered tasks
- `track_init(task_name, total_subtasks)` - Start tracking a task
- `track_status(current_subtask, subtask_name)` - Update subtask
- `track_subtask_progress(items_complete, items_total)` - Item-level progress
- `track_finish()` - Complete the task

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-20  
**Author:** System Design  
**Status:** Ready for Review
