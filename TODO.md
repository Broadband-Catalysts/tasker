# tasker TODO

## Database Support

### SQLite Support
- [ ] Create SQLite-specific schema file
- [ ] Handle UUID generation (SQLite doesn't have native UUID)
- [ ] Test all functions with SQLite backend
- [ ] Update documentation with SQLite examples

### MySQL/MariaDB Support
- [ ] Create MySQL-specific schema file
- [ ] Handle UUID generation differences
- [ ] Test timezone handling (TIMESTAMP vs TIMESTAMPTZ)
- [ ] Test all functions with MySQL/MariaDB backend
- [ ] Update documentation with MySQL examples

## Features

### Core Functionality
- [ ] Add resource monitoring (memory_mb, cpu_percent fields)
- [ ] Implement automatic cleanup of old task runs
- [ ] Add task dependencies tracking
- [ ] Support for parallel task execution tracking
- [ ] Add task retry tracking

### Configuration
- [ ] Support for multiple database connections (e.g., read replicas)
- [ ] Add configuration validation on startup
- [ ] Support for encrypted passwords in config file

### Query & Reporting
- [ ] Add summary statistics functions
- [ ] Task duration analysis
- [ ] Failure rate tracking
- [ ] Performance metrics over time
- [ ] Export functions (CSV, JSON)

### Shiny App
- [ ] Real-time log file viewer with tail functionality
- [ ] Task dependency visualization
- [ ] Performance dashboards
- [ ] Alert/notification system
- [ ] Task scheduling interface

## Testing
- [ ] Unit tests for configuration loading
- [ ] Unit tests for database operations
- [ ] Integration tests with PostgreSQL
- [ ] Integration tests with SQLite
- [ ] Integration tests with MySQL
- [ ] Test coverage > 80%

## Documentation
- [ ] Vignette: Getting started
- [ ] Vignette: Advanced usage
- [ ] Vignette: Shiny app guide
- [ ] Function documentation with more examples
- [ ] Database schema diagram

## CRAN Preparation
- [ ] Ensure all exported functions have \value documented
- [ ] Fix any R CMD check warnings
- [ ] Add \donttest{} examples that require database
- [ ] Create inst/CITATION
- [ ] Add NEWS.md
- [ ] Ensure all dependencies are CRAN packages
- [ ] Run R CMD check --as-cran
- [ ] Submit to CRAN

## Python Support
- [ ] Design Python API matching R interface
- [ ] Implement configuration loading
- [ ] Implement task registration
- [ ] Implement task tracking
- [ ] Implement subtask tracking
- [ ] Implement query functions
- [ ] Add type hints
- [ ] Unit tests for Python module
- [ ] Python documentation (Sphinx)
- [ ] Publish to PyPI
