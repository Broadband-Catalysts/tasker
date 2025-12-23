#' Get parent process ID
#'
#' @return Parent PID or NULL
#' @keywords internal
get_parent_pid <- function() {
    tryCatch(
        {
            if (.Platform$OS.type == "unix") {
                ppid <- system2("ps", c("-o", "ppid=", "-p", Sys.getpid()),
                    stdout = TRUE, stderr = FALSE
                )
                as.integer(trimws(ppid))
            } else {
                NULL
            }
        },
        error = function(e) NULL
    )
}
