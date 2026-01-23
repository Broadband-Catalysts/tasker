# Agent Skill: Database Patterns

## Purpose
Provide comprehensive guidance on database operations, connection management, and SQL query patterns that work across PostgreSQL, SQLite, and MySQL/MariaDB.

## When to Use
- Writing SQL queries in tasker package code
- Managing database connections
- Implementing schema operations
- Handling database-specific syntax differences

## Critical Requirements

### Multi-Database Support

Tasker must support three database systems:
- **PostgreSQL** - Primary production database
- **SQLite** - Testing and lightweight deployments
- **MySQL/MariaDB** - Optional production alternative

**Always write database-agnostic SQL or handle each dialect appropriately.**

## Database-Agnostic SQL Patterns

### Case-Insensitive Matching

```r
# ✅ CORRECT - Works across PostgreSQL, SQLite, MySQL/MariaDB
WHERE UPPER(column_name) LIKE UPPER('%pattern%')

# ✅ ALSO CORRECT - Dialect-specific with proper handling
config <- getOption("tasker.config")
driver <- config$database$driver

if (driver == "postgresql") {
  query <- "WHERE column_name ILIKE '%pattern%'"
} else {
  # SQLite and MySQL fallback
  query <- "WHERE UPPER(column_name) LIKE UPPER('%pattern%')"
}

# ❌ INCORRECT - PostgreSQL-only (fails on SQLite/MySQL)
WHERE column_name ILIKE '%pattern%'
```

**Why:** `ILIKE` is PostgreSQL-specific. SQLite and MySQL will error with "near 'ILIKE': syntax error". The `UPPER(column) LIKE UPPER(pattern)` pattern works universally.

### Type Casting

```r
# ✅ CORRECT - SQLite compatible
dbGetQuery(con, "SELECT COUNT(*) as n FROM table")  # Returns integer in SQLite
n <- as.integer(result$n)  # Explicit conversion

# ✅ ALSO CORRECT - PostgreSQL explicit cast (works in PostgreSQL only)
dbGetQuery(con, "SELECT COUNT(*)::INTEGER as n FROM table")

# ❌ INCORRECT - Assumes PostgreSQL syntax everywhere
dbGetQuery(con, "SELECT COUNT(*)::INTEGER as n FROM table")  # Fails on SQLite
```

**For COUNT() specifically:** PostgreSQL returns `bigint` (int64) which can cause issues. Either cast to INTEGER in PostgreSQL or handle conversion in R.

### Connection Management

**Connection modes:**
- `dbConnectBBC(mode="rw")` - Read-write access
- `dbConnectBBC(mode="r")` - Read-only access (note: 'r', not 'ro')

**Usage guidelines:**
- Use read-write for task/subtask status updates and monitoring
- Use read-only for query-only operations
- Always close connections explicitly or use `on.exit()`

```r
# ✅ CORRECT - Explicit cleanup
con <- dbConnectBBC(mode="rw")
# ... use connection ...
dbDisconnect(con)

# ✅ ALSO CORRECT - Automatic cleanup with on.exit
update_data <- function() {
  con <- dbConnectBBC(mode="rw")
  on.exit(dbDisconnect(con), add = TRUE)
  # ... use connection ...
}

# ❌ INCORRECT - Never cleanup (connection leak)
con <- dbConnectBBC(mode="rw")
# ... use connection ...
# No disconnect!
```

### Schema Operations

**Fixed-length column types** (from fccData patterns):
```sql
statefp20 CHAR(2)
countyfp20 CHAR(3)
geoid20 CHAR(15)
h3_index CHAR(15)
```

**Creating tables:**
```r
# Include created_at/updated_at timestamps
CREATE TABLE my_table (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

### Query Patterns

**Parameterized queries with glue_sql:**
```r
# ✅ CORRECT - Safe from SQL injection
result <- dbGetQuery(
  conn,
  glue::glue_sql(
    "SELECT * FROM {table_name} WHERE id = {user_id}",
    .con = conn
  )
)

# ❌ INCORRECT - SQL injection risk
result <- dbGetQuery(
  conn,
  paste0("SELECT * FROM ", table_name, " WHERE id = ", user_id)
)
```

**Table name variables:**
```r
# Use get_table_name() helper
stages_table <- get_table_name("stages", conn)
tasks_table <- get_table_name("tasks", conn)

query <- glue::glue_sql(
  "SELECT * FROM {stages_table} s JOIN {tasks_table} t ON s.stage_id = t.stage_id",
  .con = conn
)
```

## Common Anti-Patterns

### COUNT() Without Casting

```r
# ❌ INCORRECT - Returns bigint in PostgreSQL
n <- dbGetQuery(con, "SELECT COUNT(*) as n FROM table")$n
# n is now int64, may cause issues

# ✅ CORRECT - Explicit R conversion
result <- dbGetQuery(con, "SELECT COUNT(*) as n FROM table")
n <- as.integer(result$n)
```

### PostgreSQL-Specific Syntax

```r
# ❌ INCORRECT - Only works in PostgreSQL
WHERE column ILIKE '%pattern%'
WHERE column::TEXT = 'value'
SELECT ARRAY_AGG(column)
RETURNING id  # Only PostgreSQL supports RETURNING

# ✅ CORRECT - Database-agnostic alternatives
WHERE UPPER(column) LIKE UPPER('%pattern%')
WHERE CAST(column AS TEXT) = 'value'  # Or handle in R
# Aggregation in R: aggregate(df)
# Get last insert ID: dbGetQuery(con, "SELECT last_insert_rowid()")  # SQLite
```

### Assuming Connection Context

```r
# ❌ INCORRECT - Assumes connection exists in scope
update_status <- function(run_id, status) {
  dbExecute(con, "UPDATE task_runs SET status = ? WHERE run_id = ?",
            params = list(status, run_id))
}

# ✅ CORRECT - Explicit connection parameter
update_status <- function(run_id, status, conn = NULL) {
  if (is.null(conn)) {
    conn <- get_db_connection()
    on.exit(dbDisconnect(conn), add = TRUE)
  }
  dbExecute(conn, "UPDATE task_runs SET status = ? WHERE run_id = ?",
            params = list(status, run_id))
}
```

## Related Patterns

- **Parallel processing with connections:** See copilot-instructions.md "Parallel Processing with Database Connections"
- **Connection serialization:** Never return connection objects from `clusterEvalQ()`
- **Atomic operations:** Use database-level atomicity for parallel worker updates

## Examples from Codebase

### update_task.R - Database-Agnostic Case-Insensitive Search

```r
# Filename matching (works on PostgreSQL, SQLite, MySQL)
filename_matches <- DBI::dbGetQuery(
  conn,
  glue::glue_sql(
    "SELECT t.task_id, t.stage_id, t.task_name, t.script_filename 
     FROM {tasks_table} t
     WHERE UPPER(t.script_filename) LIKE UPPER({paste0('%', as.character(filename), '%')})",
    .con = conn
  )
)
```

### Proper Connection Lifecycle

```r
# From update_task.R
close_on_exit <- FALSE
if (is.null(conn)) {
  run_id_context <- tasker_context()
  if (!is.null(run_id_context)) {
    conn <- get_connection(run_id_context)
  }
  if (is.null(conn)) {
    conn <- get_db_connection()
    close_on_exit <- TRUE
  }
}

on.exit({
  if (close_on_exit && !is.null(conn)) {
    DBI::dbDisconnect(conn)
  }
})
```

## Testing

When writing tests that use databases:

```r
test_that("my_function works with SQLite", {
  skip_on_cran()
  skip_if_not_installed("RSQLite")
  
  con <- setup_test_db()  # Creates SQLite test database
  on.exit(cleanup_test_db(con), add = TRUE)
  
  # ... test code using database-agnostic SQL ...
})
```

**Remember:** If your SQL uses PostgreSQL-specific syntax, it will fail in tests (which use SQLite by default).
