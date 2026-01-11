#' Load YAML configuration file
#'
#' @param config_file Path to YAML file
#' @return List with configuration
#' @keywords internal
load_yaml_config <- function(config_file) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' required for configuration files. Install with: install.packages('yaml')")
  }
  
  tryCatch({
    config <- yaml::read_yaml(config_file)
    config <- expand_env_vars(config)
    config
  }, error = function(e) {
    stop("Failed to parse configuration file '", config_file, "': ", e$message)
  })
}
