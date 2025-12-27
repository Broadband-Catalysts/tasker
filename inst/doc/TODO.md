# tasker TODO

## 1. Database Support

### 1.1 SQLite Support
- [x] 1.1.1 Create SQLite-specific schema file - COMPLETE (inst/sql/sqlite/create_schema.sql)
- [x] 1.1.2 Handle UUID generation (SQLite doesn't have native UUID) - COMPLETE (uses randomblob)
- [x] 1.1.3 Test all functions with SQLite backend - COMPLETE (tests use SQLite by default)
- [x] 1.1.4 Update documentation with SQLite examples - COMPLETE (README.md has SQLite config)

### 1.2 MySQL/MariaDB Support
- [ ] 1.2.1 Create MySQL-specific schema file
- [ ] 1.2.2 Handle UUID generation differences
- [ ] 1.2.3 Test timezone handling (TIMESTAMP vs TIMESTAMPTZ)
- [ ] 1.2.4 Test all functions with MySQL/MariaDB backend
- [ ] 1.2.5 Update documentation with MySQL examples

## 2. Features

### 2.1 Core Functionality
- [x] 2.1.1 Add resource monitoring (memory_mb, cpu_percent fields) - DESIGN COMPLETE
- [x] 2.1.2 Support for parallel task execution tracking - DESIGN COMPLETE (item tracking)
- [x] 2.1.3 Implement item-level progress tracking - COMPLETE
  - [x] 2.1.3.1 Database schema (items_total, items_complete columns) - EXISTS
  - [x] 2.1.3.2 `subtask_increment()` function - EXISTS
  - [x] 2.1.3.3 Update Shiny UI to display item progress ("X / Y items (Z%)") - COMPLETE
  - [x] 2.1.3.4 Add sparklines/mini-charts for resource trends - DEFERRED
- [ ] 2.1.4 Implement resource monitoring functions
  - [ ] 2.1.4.1 Add `resource_snapshots` table to database schema
  - [ ] 2.1.4.2 `get_process_tree_resources()` - aggregate metrics across process tree
  - [ ] 2.1.4.3 `snapshot_resources()` - record resource snapshot to database
  - [ ] 2.1.4.4 `get_resource_history()` - retrieve historical snapshots
  - [ ] 2.1.4.5 `cleanup_orphaned_workers()` - identify and terminate orphaned parallel workers
- [ ] 2.1.5 Implement resource watchdog
  - [ ] 2.1.5.1 `start_resource_watchdog()` - background monitoring process
  - [ ] 2.1.5.2 `stop_resource_watchdog()` - manual stop function
  - [ ] 2.1.5.3 Configurable thresholds (memory warning/kill, swap, orphan detection)
  - [ ] 2.1.5.4 Automatic task termination on memory exhaustion
  - [ ] 2.1.5.5 Thrashing detection (swap usage monitoring)
- [ ] 2.1.6 Implement automatic cleanup of old task runs
- [ ] 2.1.7 Add task dependencies tracking
- [ ] 2.1.8 Add task retry tracking

### 2.2 Configuration
- [x] 2.2.1 Resource watchdog configuration in .tasker.yml - DESIGN COMPLETE
- [ ] 2.2.2 Support for multiple database connections (e.g., read replicas)
- [ ] 2.2.3 Add configuration validation on startup
- [ ] 2.2.4 Support for encrypted passwords in config file

### 2.3 Query & Reporting
- [ ] 2.3.1 Add summary statistics functions
- [ ] 2.3.2 Task duration analysis
- [ ] 2.3.3 Failure rate tracking
- [ ] 2.3.4 Performance metrics over time
- [ ] 2.3.5 Export functions (CSV, JSON)

### 2.4 Shiny App
- [x] 2.4.1 Item-level progress indicators - COMPLETE
  - [x] 2.4.1.1 "X / Y items (Z%)" display for subtasks - COMPLETE
  - [x] 2.4.1.2 Nested progress bars showing item completion - COMPLETE
- [x] 2.4.2 Real-time log file viewer with tail functionality - COMPLETE
- [ ] 2.4.3 Resource monitoring dashboard
  - [ ] 2.4.3.1 Real-time resource metrics display (processes, CPU%, memory GB/%)
  - [ ] 2.4.3.2 Resource history sparklines/charts
  - [ ] 2.4.3.3 Color-coded warnings (yellow threshold, red kill limit)
  - [ ] 2.4.3.4 Swap usage indicator (thrashing detection)
  - [ ] 2.4.3.5 Orphaned worker alerts with cleanup buttons
  - [ ] 2.4.3.6 Peak/average/current statistics
- [ ] 2.4.4 Task dependency visualization
- [ ] 2.4.5 Performance dashboards
- [ ] 2.4.6 Alert/notification system
- [ ] 2.4.7 Task scheduling interface

## 3. Testing
- [ ] 3.1 Unit tests for configuration loading
- [ ] 3.2 Unit tests for database operations
- [ ] 3.3 Unit tests for resource monitoring functions
- [ ] 3.4 Unit tests for item-level progress tracking
- [ ] 3.5 Unit tests for watchdog process
- [ ] 3.6 Integration tests with PostgreSQL
- [ ] 3.7 Integration tests with SQLite
- [ ] 3.8 Integration tests with MySQL
- [ ] 3.9 Test parallel worker cleanup
- [ ] 3.10 Test memory threshold behavior
- [ ] 3.11 Test coverage > 80%

## 4. Documentation
- [x] 4.1 Design specification document - COMPLETE
- [ ] 4.2 Vignette: Getting started
- [ ] 4.3 Vignette: Advanced usage (parallel processing with item tracking)
- [ ] 4.4 Vignette: Resource monitoring and watchdog
- [ ] 4.5 Vignette: Shiny app guide
- [ ] 4.6 Function documentation with more examples
- [ ] 4.7 Database schema diagram (update with resource_snapshots table)

## 5. CRAN Preparation
- [ ] 5.1 Ensure all exported functions have \value documented
- [ ] 5.2 Fix any R CMD check warnings
- [ ] 5.3 Add \donttest{} examples that require database
- [ ] 5.4 Create inst/CITATION
- [ ] 5.5 Add NEWS.md
- [ ] 5.6 Ensure all dependencies are CRAN packages
- [ ] 5.7 Run R CMD check --as-cran
- [ ] 5.8 Submit to CRAN

## 6. Python Support
- [ ] 6.1 Design Python API matching R interface
- [ ] 6.2 Implement configuration loading
- [ ] 6.3 Implement task registration
- [ ] 6.4 Implement task tracking
- [ ] 6.5 Implement subtask tracking
- [ ] 6.6 Implement query functions
- [ ] 6.7 Add type hints
- [ ] 6.8 Unit tests for Python module
- [ ] 6.9 Python documentation (Sphinx)
- [ ] 6.10 Publish to PyPI
