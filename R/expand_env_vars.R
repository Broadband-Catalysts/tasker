#' Expand environment variables in configuration
#'
#' @param config Configuration list
#' @return Configuration list with expanded variables
#' @keywords internal
expand_env_vars <- function(config) {
  if (is.list(config)) {
    lapply(config, expand_env_vars)
  } else if (is.character(config)) {
    pattern <- "\\$\\{([^}]+)\\}"
    matches <- gregexpr(pattern, config, perl = TRUE)
    
    if (matches[[1]][1] != -1) {
      for (match_info in regmatches(config, matches)[[1]]) {
        var_name <- sub("\\$\\{([^}]+)\\}", "\\1", match_info, perl = TRUE)
        var_value <- Sys.getenv(var_name, "")
        config <- sub(match_info, var_value, config, fixed = TRUE)
      }
    }
    
    config
  } else {
    config
  }
}
