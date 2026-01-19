#' Get the filename of the currently executing script
#'
#' Uses the this.path package to detect the script filename, which handles
#' various execution contexts (Rscript, source, RStudio, R CMD BATCH, etc.).
#'
#' @return Character string with script filename (basename only), or NULL if
#'   script cannot be detected (e.g., interactive session)
#' @export
#'
#' @examples
#' \dontrun{
#' # When running 03_ANNUAL_SEPT_01_Road_Lengths.R:
#' get_script_filename()
#' # Returns: "03_ANNUAL_SEPT_01_Road_Lengths.R"
#' }
get_script_filename <- function() {
  
  # Method 1: Check command line arguments (most reliable for Rscript)
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    return(basename(script_path))
  }
  
  # Method 2: Try this.path package for other execution contexts (source, RStudio, etc.)
  tryCatch({
    script_path <- this.path::this.path()
    if (!is.null(script_path) && !is.na(script_path) && nchar(script_path) > 0) {
      filename <- basename(script_path)
      # Skip if we're detecting our own function file
      if (filename != "get_script_filename.R") {
        return(filename)
      }
    }
  }, error = function(e) {
    # Continue to fallback method
  })
  
  # Return NULL if script cannot be detected
  return(NULL)
}
