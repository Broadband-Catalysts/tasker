#' Format duration from seconds to human readable format
#' @param seconds Number of seconds
#' @return Character string with formatted duration
#' @export
format_duration_seconds <- function(seconds) {
  if (is.na(seconds) || is.null(seconds) || seconds <= 0) {
    return("0s")
  }
  
  days <- floor(seconds / 86400)
  hours <- floor((seconds %% 86400) / 3600)
  minutes <- floor((seconds %% 3600) / 60)
  secs <- floor(seconds %% 60)
  
  if (days > 0) {
    if (hours > 0) {
      return(paste0(days, "d ", hours, "h"))
    } else {
      return(paste0(days, "d"))
    }
  } else if (hours > 0) {
    if (minutes > 0) {
      return(paste0(hours, "h ", minutes, "m"))
    } else {
      return(paste0(hours, "h"))
    }
  } else if (minutes > 0) {
    return(paste0(minutes, "m"))
  } else {
    return(paste0(secs, "s"))
  }
}
