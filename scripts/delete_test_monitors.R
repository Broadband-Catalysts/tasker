library(tasker)
library(DBI)
con <- get_db_connection()
sel <- dbGetQuery(con, "SELECT reporter_id, hostname, process_id, started_at, last_heartbeat, shutdown_requested FROM tasker.reporter_status WHERE hostname LIKE $1 OR hostname = $2 ORDER BY last_heartbeat DESC", params = list("test-%", "test-host"))
if(nrow(sel)==0) {
  cat("No matching test monitors found.\n")
} else {
  print(sel)
  cat("\nAttempting to stop each reporter, then delete its DB row...\n")

  deleted <- 0L
  for(i in seq_len(nrow(sel))) {
    row <- sel[i, , drop = FALSE]
    h <- as.character(row$hostname)
    id <- row$reporter_id
    pid <- row$process_id
    cat(sprintf("Stopping reporter id=%s hostname=%s pid=%s...\n", id, h, pid))
    tryCatch({
      # Use tasker stop_reporter helper; pass existing connection
      stop_reporter(h, timeout = 10, con = con)
      cat("Stopped (requested).\n")
    }, error = function(e) {
      cat(sprintf("stop_reporter error for %s: %s\n", h, e$message))
    })
    # Re-read the row to see if shutdown flag was set by stop_reporter
    current <- dbGetQuery(con, "SELECT reporter_id, shutdown_requested FROM tasker.reporter_status WHERE reporter_id = $1", params = list(id))
    if (nrow(current) == 0) {
      cat(sprintf("Row for reporter_id=%s no longer present (deleted by other actor).\n", id))
      next
    }

    if (identical(current$shutdown_requested[1], 0L) || identical(current$shutdown_requested[1], FALSE)) {
      cat(sprintf("Setting shutdown_requested=TRUE for reporter_id=%s (hostname=%s)\n", id, h))
      tryCatch({
        dbExecute(con, "UPDATE tasker.reporter_status SET shutdown_requested = 1 WHERE reporter_id = $1", params = list(id))
      }, error = function(e) {
        cat(sprintf("Failed to set shutdown_requested for %s: %s\n", id, e$message))
      })
    }

    # Attempt to delete the specific reporter row by id (may be zero if process runs elsewhere)
    tryCatch({
      del <- dbExecute(con, "DELETE FROM tasker.reporter_status WHERE reporter_id = $1", params = list(id))
      deleted <- deleted + as.integer(del)
      cat(sprintf("Deleted %d row(s) for reporter_id=%s\n", del, id))
      if (del == 0L) {
        cat(sprintf("Row for reporter_id=%s remains (process likely on different host).\n", id))
      }
    }, error = function(e) {
      cat(sprintf("Failed to delete reporter_id=%s: %s\n", id, e$message))
    })
  }

  cat(sprintf("Total deleted rows: %d\n", deleted))
}
DBI::dbDisconnect(con)
