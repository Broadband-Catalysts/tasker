#' Merge two configuration lists
#'
#' @param base Base configuration
#' @param overlay Configuration to overlay
#' @return Merged configuration
#' @keywords internal
merge_configs <- function(base, overlay) {
  if (!is.list(overlay) || length(overlay) == 0) {
    return(base)
  }
  
  for (name in names(overlay)) {
    if (is.list(overlay[[name]]) && is.list(base[[name]])) {
      base[[name]] <- merge_configs(base[[name]], overlay[[name]])
    } else if (!is.null(overlay[[name]])) {
      base[[name]] <- overlay[[name]]
    }
  }
  
  base
}
