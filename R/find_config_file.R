#' Find .tasker.yml configuration file
#'
#' @param start_dir Starting directory (default: current working directory)
#' @param filename Configuration filename (default: ".tasker.yml")
#' @param max_depth Maximum directory levels to search up (default: 10)
#' @return Path to config file, or NULL if not found
#' @export
find_config_file <- function(start_dir = getwd(), 
                             filename = ".tasker.yml",
                             max_depth = 10) {
  
  current_dir <- normalizePath(start_dir, mustWork = FALSE)
  
  for (i in 1:max_depth) {
    config_path <- file.path(current_dir, filename)
    
    if (file.exists(config_path)) {
      return(normalizePath(config_path))
    }
    
    parent_dir <- dirname(current_dir)
    
    if (parent_dir == current_dir) {
      break
    }
    
    current_dir <- parent_dir
  }
  
  return(NULL)
}
