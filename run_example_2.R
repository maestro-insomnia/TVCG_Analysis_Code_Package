# Run Example 2 using the single-factor synthetic dataset.

get_launcher_dir <- function() {
  command_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", command_args, value = TRUE)
  if (length(file_arg) > 0L) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)))
  }

  source_frames <- sys.frames()
  if (length(source_frames) > 0L) {
    for (frame_index in rev(seq_along(source_frames))) {
      source_file <- source_frames[[frame_index]]$ofile
      if (!is.null(source_file) && nzchar(source_file)) {
        return(dirname(normalizePath(source_file, winslash = "/", mustWork = TRUE)))
      }
    }
  }

  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    active_path <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
    if (nzchar(active_path)) {
      return(dirname(normalizePath(active_path, winslash = "/", mustWork = TRUE)))
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

script_dir <- get_launcher_dir()
source(file.path(script_dir, "TVCG_Factorial_ANOVA_ART_Analysis.R"))
run_analysis(file.path(script_dir, "configs", "Config_Example_2_Single_Factor.R"))
