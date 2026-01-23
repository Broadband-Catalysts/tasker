# TODO: Full MySQL/MariaDB Support Implementation

## Overview
The tasker-dev codebase currently supports PostgreSQL (primary) and SQLite (testing), but MySQL/MariaDB support is incomplete. While RMariaDB is listed in DESCRIPTION as "Suggests" and some connection infrastructure exists, the database-specific SQL patterns need comprehensive updates.

## Current Status
- ✅ Basic connection support exists in `get_db_connection.R` and `get_monitor_connection.R`
- ✅ Parameter placeholder handling in `get_placeholder.R` and `build_sql.R` 
- ✅ Driver validation in `validate_config.R` includes "mysql"
- ❌ **Timestamp functions incomplete**: Binary if/else patterns assume SQLite vs PostgreSQL only
- ❌ **No Docker testing infrastructure** for MySQL/PostgreSQL databases
- ❌ **Test coverage incomplete** for MySQL-specific code paths

## Required Implementation Tasks

### 1. Fix Database-Specific SQL Patterns
**Problem**: Current code uses binary detection (SQLite vs PostgreSQL) instead of three-way (SQLite/MySQL/PostgreSQL).

**Files requiring updates**:
- `R/check_reporter.R` (lines 59-85): Timestamp age calculation
  - SQLite: `julianday('now') - julianday(last_heartbeat)`
  - PostgreSQL: `EXTRACT(EPOCH FROM (NOW() - last_heartbeat))`
  - **Need MySQL**: `TIMESTAMPDIFF(SECOND, last_heartbeat, NOW())`

- `R/update_reporter_heartbeat.R`: Heartbeat timestamp updates
  - SQLite: `datetime('now')`
  - PostgreSQL: `NOW()`
  - **Need MySQL**: `NOW()` (same as PostgreSQL)

- `R/task_fail.R` (line 44): Time function selection
  - Current: `time_func <- if (db_driver == "sqlite") "datetime('now')" else "NOW()"`
  - **Need MySQL**: Three-way detection

- `R/reporter_main_loop.R`: Multiple timestamp operations
  - Lines 141, 166, 177, 206, 251, 299: Binary driver checks
  - Parameter markers: $1, $2, $3 (PostgreSQL) vs ? (SQLite/MySQL)

**Solution Pattern**:
```r
# Replace binary if/else with three-way detection
if (db_driver == "sqlite") {
  # SQLite-specific SQL
} else if (db_driver == "mysql") {
  # MySQL-specific SQL  
} else {
  # PostgreSQL (default)
}
```

### 2. Docker Testing Infrastructure
**Need**: Containerized test databases for CI/CD and local development.

**Required files**:
- `docker-compose.test.yml`: MariaDB and PostgreSQL services
- `tests/docker/`: Helper scripts for container management
- `tests/testthat/helper-docker.R`: Docker availability detection
- Environment variable configuration for test database connections

**Features**:
- Graceful skip when Docker unavailable (with warning)
- Automatic container startup/shutdown in test suite
- Isolated test databases with predictable schemas
- Connection string generation for test environments

### 3. Test Suite Enhancement
**Current**: Tests primarily use SQLite with some PostgreSQL integration tests.

**Need**: Comprehensive coverage across all three database types.

**Files requiring updates**:
- `tests/testthat/test-database-monitoring.R`: Add MySQL test cases
- `tests/testthat/test-database_monitoring.R`: Extend driver coverage
- `tests/testthat/test-*.R`: Add MySQL-specific test scenarios
- Test helpers: Docker container management functions

**Test scenarios**:
- Reporter heartbeat updates (MySQL timestamp handling)
- Timestamp age calculations (TIMESTAMPDIFF vs EXTRACT vs julianday)
- Parameter marker handling (? vs $1)
- Connection establishment and error handling
- Schema operations across database types

### 4. Documentation Updates
**Files needing updates**:
- `README.md`: Add MySQL configuration examples
- `.github/copilot-instructions.md`: Update database patterns section
- Function documentation: Add MySQL-specific examples
- `DESCRIPTION`: Verify RMariaDB dependency specification

## Technical Details

### Timestamp Differences by Database
| Operation | SQLite | PostgreSQL | MySQL |
|-----------|---------|------------|-------|
| Current time | `datetime('now')` | `NOW()` | `NOW()` |
| Age calculation | `julianday('now') - julianday(col)` * 86400 | `EXTRACT(EPOCH FROM (NOW() - col))` | `TIMESTAMPDIFF(SECOND, col, NOW())` |
| Parameter markers | `?` | `$1, $2, $3` | `?` |

### Connection Configuration Examples
```yaml
# MySQL configuration
database:
  driver: mysql
  host: localhost
  port: 3306
  dbname: tasker_test
  user: test_user
  password: test_password
```

## Implementation Priority
1. **High**: Fix timestamp SQL patterns (enables basic MySQL functionality)
2. **High**: Add Docker testing infrastructure (enables reliable CI/CD)
3. **Medium**: Comprehensive test coverage (ensures quality)
4. **Low**: Documentation updates (improves usability)

## Estimated Effort
- **SQL pattern fixes**: 4-6 hours
- **Docker infrastructure**: 6-8 hours  
- **Test coverage**: 8-10 hours
- **Documentation**: 2-3 hours
- **Total**: ~20-27 hours

## Dependencies
- RMariaDB package (already in DESCRIPTION)
- Docker (for testing infrastructure)
- Access to MySQL/MariaDB test database
- CI/CD environment updates (if applicable)

---

*Created: January 20, 2026*  
*Context: Issue identified during investigation of reporter "Very stale" status bug*