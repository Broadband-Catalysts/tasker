# tasker - TODO List

**Last Updated:** 2025-12-21

---

## High Priority

### Configuration System (v0.1.0) ✅ COMPLETED

#### Configuration Loading
- [x] Create `R/config.R` with configuration functions
- [x] Implement `tasker_config()` function:
  - [x] Search up directory tree for `.tasker.yml`
  - [x] Parse YAML configuration file
  - [x] Support environment variable substitution (e.g., `${VAR}`)
  - [x] Merge with environment variables
  - [x] Apply explicit parameter overrides
  - [x] Cache in options (lazy loading)
  - [x] Validate configuration structure
- [x] Implement `find_config_file()`:
  - [x] Start from current directory
  - [x] Search up max_depth levels
  - [x] Return path or NULL
  - [x] Handle filesystem root gracefully
- [x] Implement `get_tasker_config()`:
  - [x] Return cached configuration
  - [x] Return NULL if not loaded
- [x] Implement internal configuration check:
  - [x] Check if configuration loaded
  - [x] Auto-load if not loaded
  - [x] No-op if already loaded
- [x] Add configuration validation:
  - [x] Required fields vary by driver
  - [x] Optional fields: schema, driver, password
  - [x] Validate driver: "postgresql", "sqlite" (mysql planned)
  - [x] Validate port: integer 1-65535

#### Configuration File Support ✅ COMPLETED
- [x] Add `yaml` package dependency
- [x] Create example `.tasker.yml.example` in project root
- [x] Create example `.tasker-sqlite.yml.example` for SQLite
- [x] Support environment variable expansion in YAML
- [x] Document `.tasker.yml` format
- [x] Add `.tasker.yml` to `.Rbuildignore`

#### Integration with Existing Functions ✅ COMPLETED
- [x] All functions check configuration automatically
- [x] Configuration loaded on first database operation
- [x] Functions: `task_start()`, `task_update()`, `register_task()`, etc.
- [x] Query functions: `get_task_status()`, `get_active_tasks()`, etc.

#### Configuration Storage ✅ COMPLETED
- [x] Store configuration in options:
  - `tasker.config` - Full configuration list
  - Additional metadata stored as needed
- [x] Lazy loading on first use

#### Documentation ✅ COMPLETED
- [x] Document configuration system in README
- [x] Add configuration examples to README
- [x] Document precedence rules
- [x] Document environment variable names
- [x] Create `.tasker.yml.example` template
- [x] Create `.tasker-sqlite.yml.example` template

#### Testing ✅ COMPLETED
- [x] Test auto-discovery from various depths
- [x] Test with SQLite (in-memory for unit tests)
- [x] Test environment variable substitution
- [x] Test with custom config file path
- [x] Test lazy loading

---

### Database Support

#### SQLite Support (v0.2.0) ✅ COMPLETED
- [x] Create SQLite schema file (`inst/sql/sqlite/create_schema.sql`)
- [x] Adapt data types for SQLite:
  - `BIGSERIAL` → `INTEGER PRIMARY KEY AUTOINCREMENT`
  - `TIMESTAMPTZ` → `TEXT` (ISO 8601 format)
  - `UUID` → `TEXT`
  - `JSONB` → `TEXT` (JSON as text)
  - `NUMERIC(5,2)` → `REAL`
- [x] Create SQLite connection functions in `R/connection.R`
- [x] Handle SQLite-specific features:
  - No schema support (all in main database)
  - No `DISTINCT ON` (rewrite queries using subqueries)
  - Use `datetime('now')` instead of `NOW()`
- [x] Update `setup_tasker_db()` to detect and handle SQLite
- [x] Add SQLite-specific views adapted for SQLite syntax
- [x] Test with in-memory database (`:memory:`)
- [x] Test with file-based database
- [x] Document SQLite-specific configuration
- [x] Use SQLite for unit testing (no external database required)

**Benefits:** 
- Single-file database
- No server required
- Excellent for development/testing
- Portable

**Challenges:**
- Limited concurrent write access
- No built-in UUID type
- Different SQL syntax for some operations
- No native TIMESTAMPTZ support

#### MySQL/MariaDB Support (v0.3.0)
- [ ] Create MySQL schema file (`inst/sql/mysql/create_schema.sql`)
- [ ] Adapt data types for MySQL:
  - `BIGSERIAL` → `BIGINT AUTO_INCREMENT`
  - `TIMESTAMPTZ` → `TIMESTAMP` (with timezone handling)
  - `UUID` → `CHAR(36)` or `BINARY(16)`
  - `JSONB` → `JSON`
  - Keep `NUMERIC(5,2)` as-is
- [ ] Create MySQL connection functions
- [ ] Handle MySQL-specific features:
  - Schema = database in MySQL
  - No `DISTINCT ON` (use subqueries)
  - Use `NOW()` but handle timezone carefully
  - Different index syntax
- [ ] Add MySQL-specific queries
- [ ] Test with MySQL 8.0+
- [ ] Test with MariaDB 10.5+
- [ ] Document MySQL-specific configuration
- [ ] Add MySQL examples to vignettes

**Benefits:**
- Widely used
- Good performance
- Strong ecosystem
- Better concurrency than SQLite

**Challenges:**
- Server required
- More complex setup
- Timezone handling
- Slight SQL syntax differences

---

## Medium Priority

### Performance Optimizations

#### Connection Pooling (v0.4.0)
- [ ] Integrate `pool` package for connection management
- [ ] Add `use_connection_pool` parameter to `configure_db()`
- [ ] Implement pool configuration options (max size, idle timeout)
- [ ] Update all database operations to use pool
- [ ] Add pool monitoring/statistics
- [ ] Document connection pooling best practices
- [ ] Test pool behavior under load
- [ ] Add pool performance benchmarks

#### Batch Updates (v0.4.0)
- [ ] Implement batch status update queue
- [ ] Add `track_status_batch()` function
- [ ] Configure batch size and flush interval
- [ ] Background worker for flushing batches
- [ ] Handle batch failures gracefully
- [ ] Add batch performance metrics
- [ ] Document batch vs immediate updates

### Monitoring Dashboard Enhancements

#### Advanced Dashboard Features (v0.5.0)
- [ ] Add filtering by stage/status
- [ ] Implement search functionality
- [ ] Add sortable tables
- [ ] Create performance trend charts
- [ ] Add resource usage graphs (if tracked)
- [ ] Implement alert thresholds
- [ ] Add export to CSV/Excel
- [ ] Dark mode support
- [ ] Mobile-responsive design
- [ ] Real-time updates via WebSocket

#### Dashboard Customization (v0.5.0)
- [ ] User preference storage
- [ ] Customizable refresh intervals
- [ ] Configurable columns
- [ ] Saved filter presets
- [ ] Custom dashboard layouts
- [ ] Theming support

---

## Low Priority

### Additional Database Support

#### Microsoft SQL Server Support (v0.6.0)
- [ ] Create MSSQL schema file
- [ ] Handle T-SQL syntax differences
- [ ] Test with SQL Server 2017+
- [ ] Document MSSQL configuration

#### Oracle Database Support (v0.7.0)
- [ ] Create Oracle schema file
- [ ] Handle PL/SQL syntax differences
- [ ] Test with Oracle 12c+
- [ ] Document Oracle configuration

### Advanced Features

#### Distributed Execution Tracking (v1.0.0)
- [ ] Design multi-host tracking
- [ ] Add cluster/node identification
- [ ] Cross-host execution linking
- [ ] Distributed dashboard
- [ ] Aggregate statistics

#### Resource Usage Tracking (v1.1.0)
- [ ] Enhanced memory tracking
- [ ] CPU usage per task
- [ ] Disk I/O monitoring
- [ ] Network I/O tracking
- [ ] Database connection usage
- [ ] Resource usage alerts

#### Alert System (v1.2.0)
- [ ] Email notifications
- [ ] Slack integration
- [ ] Webhook support
- [ ] Custom alert rules
- [ ] Alert escalation
- [ ] Alert history

#### Cost Tracking (v1.3.0)
- [ ] Cloud compute cost tracking
- [ ] Database cost tracking
- [ ] Storage cost tracking
- [ ] Cost optimization suggestions
- [ ] Budget alerts

---

## Code Quality & Maintenance

### Testing
- [ ] Increase test coverage to >95%
- [ ] Add database-specific test suites
- [ ] Performance regression tests
- [ ] Load testing
- [ ] Stress testing
- [ ] Security testing

### Documentation
- [ ] Complete API reference
- [ ] More usage examples
- [ ] Video tutorials
- [ ] Best practices guide
- [ ] Troubleshooting guide
- [ ] Performance tuning guide

### Code Organization
- [ ] Refactor database-specific code into separate files
- [ ] Abstract SQL generation
- [ ] Create database driver interface
- [ ] Improve error messages
- [ ] Add more input validation

---

## Community & Ecosystem

### Integration
- [ ] targets integration
- [ ] drake integration  
- [ ] future integration
- [ ] crew integration
- [ ] Shiny modules for easy embedding

### Examples & Use Cases
- [ ] Bioinformatics pipeline example
- [ ] Financial analysis pipeline
- [ ] Machine learning workflow
- [ ] ETL pipeline example
- [ ] Report generation pipeline

### Community Building
- [ ] Create demo video
- [ ] Write blog post
- [ ] Present at useR! conference
- [ ] Create cheat sheet
- [ ] Set up Slack/Discord channel

---

## Database Abstraction Design

### Generic SQL Patterns

For maximum portability, use these patterns:

#### Date/Time Functions
```r
# Instead of PostgreSQL-specific NOW()
get_current_timestamp <- function(driver) {
  switch(driver,
    postgresql = "NOW()",
    sqlite = "datetime('now')",
    mysql = "NOW()",
    mssql = "GETDATE()",
    oracle = "SYSDATE"
  )
}
```

#### Auto-Increment Primary Keys
```r
get_primary_key_def <- function(driver, column_name) {
  switch(driver,
    postgresql = sprintf("%s BIGSERIAL PRIMARY KEY", column_name),
    sqlite = sprintf("%s INTEGER PRIMARY KEY AUTOINCREMENT", column_name),
    mysql = sprintf("%s BIGINT AUTO_INCREMENT PRIMARY KEY", column_name),
    mssql = sprintf("%s BIGINT IDENTITY(1,1) PRIMARY KEY", column_name),
    oracle = sprintf("%s NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY", column_name)
  )
}
```

#### Schema Support
```r
get_schema_prefix <- function(driver, schema_name) {
  switch(driver,
    postgresql = sprintf("%s.", schema_name),
    sqlite = "",  # SQLite doesn't use schemas
    mysql = sprintf("%s.", schema_name),  # MySQL: schema = database
    mssql = sprintf("%s.dbo.", schema_name),
    oracle = sprintf("%s.", schema_name)
  )
}
```

### SQL Template System

Create SQL templates with placeholders:

```sql
-- inst/sql/templates/create_executions_table.sql
CREATE TABLE {{schema_prefix}}executions (
    {{pk_def}},
    run_id {{uuid_type}} NOT NULL UNIQUE,
    execution_name VARCHAR(255) NOT NULL,
    execution_start {{timestamp_type}},
    last_update {{timestamp_type}} DEFAULT {{current_timestamp}}
    -- ... rest of columns
);
```

Then substitute with driver-specific values.

---

## Implementation Notes

### Priority Order Rationale

1. **SQLite first** - Simplest to implement, great for testing, no server
2. **MySQL/MariaDB second** - Most widely used after PostgreSQL
3. **MSSQL/Oracle later** - Enterprise databases, smaller user base in R

### Compatibility Testing

For each new database:
- [ ] Test on fresh database
- [ ] Test with existing data
- [ ] Test concurrent access
- [ ] Test failover scenarios
- [ ] Benchmark performance
- [ ] Document limitations

### Breaking Changes

When adding database support:
- Maintain backward compatibility with PostgreSQL
- Use feature detection, not database detection
- Provide clear migration guides
- Version bump appropriately (MINOR for new DB support)

---

## Questions to Resolve

1. Should we abstract database operations into a class system (S3/R6)?
2. How to handle database-specific features users want (e.g., PostgreSQL partitioning)?
3. Should we provide a database-agnostic migration tool?
4. How to test multiple databases in CI/CD?
5. Should we support mixed-database environments (read from multiple DBs)?

---

**Note:** This TODO list is a living document. Items may be reprioritized based on:
- User feedback and feature requests
- Security vulnerabilities
- Performance issues
- Community contributions
- Competing package developments

**Contributing:** If you'd like to help with any of these items, please open an issue or PR on GitHub!
