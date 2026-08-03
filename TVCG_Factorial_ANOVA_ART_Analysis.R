# ============================================================================
# Reusable Factorial ANOVA / ART-ANOVA Analysis Engine
# ============================================================================
#
# This file is the analysis engine. Do not replace sections inside this file.
# All user-editable settings are stored in a separate configuration file.
#
# Run from a terminal:
#   Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
#
# Run from RStudio:
#   source("TVCG_Factorial_ANOVA_ART_Analysis.R")
#   run_analysis("configs/Config_Example_1_Default_TVCG.R")
#
# Expected wide-format data:
#   - One row = one independent experimental unit or participant.
#   - One ID column.
#   - One column for each between-subject factor.
#   - One numeric column for each dependent variable.
#
# Example:
#   ID | FactorA | FactorB | FactorC | Outcome1 | Outcome2
#    1 | Low     | Text    | C1      | 4.2      | 75
#    2 | High    | Audio   | C2      | 5.1      | 82
#
# Expected long-format data:
#   - One row = one outcome observation.
#   - ID and factor columns are repeated across outcomes.
#   - One column stores outcome names and one column stores outcome values.
#
# Example:
#   ID | FactorA | FactorB | OutcomeName | OutcomeValue
#    1 | Low     | Text    | Outcome1   | 4.2
#    1 | Low     | Text    | Outcome2   | 75
#
# The current implementation is designed for factorial between-subjects data
# with two or three enabled factors. Both ANOVA and ART-ANOVA always fit the
# complete factorial model containing every main effect and interaction among
# all enabled factors. Factor names, levels, dependent variables, categories,
# file names, and sheet names are supplied by the configuration. An optional
# correlation module automatically selects one common Pearson or Spearman
# method for all enabled variables and appends a correlation heatmap to the
# figures PDF.
# ============================================================================

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x
}

get_engine_path <- function() {
  source_frames <- sys.frames()
  if (length(source_frames) > 0L) {
    for (frame_index in rev(seq_along(source_frames))) {
      source_file <- source_frames[[frame_index]]$ofile
      if (!is.null(source_file) && nzchar(source_file)) {
        return(normalizePath(source_file, winslash = "/", mustWork = FALSE))
      }
    }
  }

  command_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", command_args, value = TRUE)
  if (length(file_arg) > 0L) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE))
  }

  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    active_path <- tryCatch(
      rstudioapi::getActiveDocumentContext()$path,
      error = function(e) ""
    )
    if (nzchar(active_path)) {
      return(normalizePath(active_path, winslash = "/", mustWork = FALSE))
    }
  }

  normalizePath(file.path(getwd(), "TVCG_Factorial_ANOVA_ART_Analysis.R"), winslash = "/", mustWork = FALSE)
}

ENGINE_PATH <- get_engine_path()
ENGINE_DIR <- dirname(ENGINE_PATH)

safe_path_component <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]+", "_", as.character(x))
  x <- gsub("_+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) "analysis" else x
}

resolve_relative_path <- function(path, base_dir) {
  if (is.null(path) || !nzchar(path)) return(path)
  if (grepl("^[A-Za-z]:[/\\\\]", path) || startsWith(path, "/") || startsWith(path, "~")) {
    return(normalizePath(path.expand(path), winslash = "/", mustWork = FALSE))
  }
  normalizePath(file.path(base_dir, path), winslash = "/", mustWork = FALSE)
}

load_configuration <- function(config_file) {
  config_path <- resolve_relative_path(config_file, getwd())
  if (!file.exists(config_path)) {
    alternative <- resolve_relative_path(config_file, ENGINE_DIR)
    if (file.exists(alternative)) config_path <- alternative
  }
  if (!file.exists(config_path)) {
    stop("Configuration file not found: ", config_file, call. = FALSE)
  }

  config_environment <- new.env(parent = baseenv())
  sys.source(config_path, envir = config_environment, keep.source = TRUE)
  if (!exists("CONFIG", envir = config_environment, inherits = FALSE)) {
    stop("The configuration file must create an object named CONFIG.", call. = FALSE)
  }

  config <- get("CONFIG", envir = config_environment, inherits = FALSE)
  if (!is.list(config)) stop("CONFIG must be a list.", call. = FALSE)
  attr(config, "config_path") <- normalizePath(config_path, winslash = "/", mustWork = TRUE)
  attr(config, "config_dir") <- dirname(attr(config, "config_path"))
  config
}


validate_configuration <- function(config) {
  required_sections <- c("input", "factors", "factor_levels", "outcomes", "analysis", "plots", "output", "packages")
  missing_sections <- setdiff(required_sections, names(config))
  if (length(missing_sections) > 0L) {
    stop("CONFIG is missing sections: ", paste(missing_sections, collapse = ", "), call. = FALSE)
  }

  if (is.null(config$input$file) || length(config$input$file) != 1L || !nzchar(config$input$file)) {
    stop("CONFIG$input$file must be a non-empty file path.", call. = FALSE)
  }
  if (is.null(config$input$id_column) || length(config$input$id_column) != 1L || !nzchar(config$input$id_column)) {
    stop("CONFIG$input$id_column must be a non-empty column name.", call. = FALSE)
  }

  factor_spec <- config$factors
  if (!is.data.frame(factor_spec)) stop("CONFIG$factors must be a data.frame.", call. = FALSE)
  required_factor_columns <- c("code", "column", "label", "short_label", "enabled")
  missing_factor_columns <- setdiff(required_factor_columns, names(factor_spec))
  if (length(missing_factor_columns) > 0L) {
    stop("CONFIG$factors is missing columns: ", paste(missing_factor_columns, collapse = ", "), call. = FALSE)
  }

  if (!is.logical(factor_spec$enabled) || any(is.na(factor_spec$enabled))) {
    stop("CONFIG$factors$enabled must contain only TRUE or FALSE values.", call. = FALSE)
  }
  enabled_factors <- factor_spec[factor_spec$enabled %in% TRUE, , drop = FALSE]
  if (nrow(enabled_factors) < 2L || nrow(enabled_factors) > 3L) {
    stop("Enable exactly two or three factors.", call. = FALSE)
  }

  required_text_fields <- c("code", "column", "label", "short_label")
  for (field in required_text_fields) {
    values <- as.character(enabled_factors[[field]])
    if (any(is.na(values) | !nzchar(trimws(values)))) {
      stop("Enabled factors contain an empty or missing ", field, " value.", call. = FALSE)
    }
  }

  if (anyDuplicated(enabled_factors$code)) stop("Factor codes must be unique.", call. = FALSE)
  if (anyDuplicated(enabled_factors$column)) stop("Factor source-column names must be unique.", call. = FALSE)
  if (any(enabled_factors$code %in% c("ID", "Y"))) {
    stop("Factor codes cannot be ID or Y because those names are reserved internally.", call. = FALSE)
  }
  if (config$input$id_column %in% enabled_factors$column) {
    stop("The ID column cannot also be used as a factor source column.", call. = FALSE)
  }
  if (!all(make.names(enabled_factors$code) == enabled_factors$code)) {
    stop("Factor codes must be valid R names, such as X1, X2, and X3.", call. = FALSE)
  }

  for (code in enabled_factors$code) {
    configured_levels <- config$factor_levels[[code]]
    if (is.null(configured_levels) || length(configured_levels) < 2L) {
      stop("CONFIG$factor_levels must define at least two levels for factor code ", code, ".", call. = FALSE)
    }
    configured_levels <- as.character(configured_levels)
    if (any(is.na(configured_levels) | !nzchar(trimws(configured_levels)))) {
      stop("factor_levels$", code, " contains an empty or missing level.", call. = FALSE)
    }
    if (anyDuplicated(configured_levels)) {
      stop("factor_levels$", code, " contains duplicated levels.", call. = FALSE)
    }
  }

  if (!is.null(config$outcomes)) {
    if (!is.data.frame(config$outcomes)) stop("CONFIG$outcomes must be NULL or a data.frame.", call. = FALSE)
    required_outcome_columns <- c("column", "label", "category", "enabled")
    missing_outcome_columns <- setdiff(required_outcome_columns, names(config$outcomes))
    if (length(missing_outcome_columns) > 0L) {
      stop("CONFIG$outcomes is missing columns: ", paste(missing_outcome_columns, collapse = ", "), call. = FALSE)
    }

    if (!is.logical(config$outcomes$enabled) || any(is.na(config$outcomes$enabled))) {
      stop("CONFIG$outcomes$enabled must contain only TRUE or FALSE values.", call. = FALSE)
    }
    if ("include_in_correlation" %in% names(config$outcomes)) {
      if (!is.logical(config$outcomes$include_in_correlation) ||
          any(is.na(config$outcomes$include_in_correlation))) {
        stop(
          "CONFIG$outcomes$include_in_correlation must contain only TRUE or FALSE values.",
          call. = FALSE
        )
      }
    }
    enabled_outcomes <- config$outcomes[config$outcomes$enabled %in% TRUE, , drop = FALSE]
    if (nrow(enabled_outcomes) == 0L) stop("Enable at least one dependent variable.", call. = FALSE)
    for (field in c("column", "label", "category")) {
      values <- as.character(enabled_outcomes[[field]])
      if (any(is.na(values) | !nzchar(trimws(values)))) {
        stop("Enabled outcomes contain an empty or missing ", field, " value.", call. = FALSE)
      }
    }
    if (anyDuplicated(enabled_outcomes$column)) {
      stop("Enabled outcome source-column names must be unique.", call. = FALSE)
    }
    conflicting_outcomes <- intersect(
      enabled_outcomes$column,
      c(config$input$id_column, enabled_factors$column)
    )
    if (length(conflicting_outcomes) > 0L) {
      stop(
        "Outcome source columns cannot also be ID or factor columns: ",
        paste(conflicting_outcomes, collapse = ", "),
        call. = FALSE
      )
    }
    if (anyDuplicated(enabled_outcomes$label)) {
      stop(
        "Enabled outcome display labels must be unique because labels are used as result-list keys.",
        call. = FALSE
      )
    }
  }

  data_format <- tolower(config$input$data_format %||% "wide")
  if (!data_format %in% c("wide", "long")) stop("input$data_format must be 'wide' or 'long'.", call. = FALSE)
  if (data_format == "long") {
    if (is.null(config$input$long$outcome_name_column) || !nzchar(config$input$long$outcome_name_column)) {
      stop("Long-format input requires input$long$outcome_name_column.", call. = FALSE)
    }
    if (is.null(config$input$long$outcome_value_column) || !nzchar(config$input$long$outcome_value_column)) {
      stop("Long-format input requires input$long$outcome_value_column.", call. = FALSE)
    }
  }

  alpha <- config$analysis$alpha
  if (length(alpha) != 1L || !is.numeric(alpha) || !is.finite(alpha) || alpha <= 0 || alpha >= 1) {
    stop("analysis$alpha must be one finite number strictly between 0 and 1.", call. = FALSE)
  }

  method_selection <- tolower(config$analysis$method_selection %||% "automatic")
  if (!method_selection %in% c("automatic", "anova", "art")) {
    stop("analysis$method_selection must be 'automatic', 'anova', or 'art'.", call. = FALSE)
  }

  anova_type <- as.integer(config$analysis$anova_type %||% 3L)
  if (!anova_type %in% c(2L, 3L)) {
    stop("analysis$anova_type must be 2 or 3 for car::Anova().", call. = FALSE)
  }

  levene_center <- tolower(config$analysis$levene_center %||% "median")
  if (!levene_center %in% c("median", "mean")) {
    stop("analysis$levene_center must be 'median' or 'mean'.", call. = FALSE)
  }

  minimum_valid_n <- as.integer(config$analysis$minimum_valid_n %||% 10L)
  if (!is.finite(minimum_valid_n) || minimum_valid_n < 3L) {
    stop("analysis$minimum_valid_n must be an integer of at least 3.", call. = FALSE)
  }

  correlation_config <- config$correlation %||% list()
  correlation_enabled <- correlation_config$enabled %||% TRUE
  if (length(correlation_enabled) != 1L || !is.logical(correlation_enabled) ||
      is.na(correlation_enabled)) {
    stop("correlation$enabled must be TRUE or FALSE.", call. = FALSE)
  }

  correlation_minimum_n <- as.integer(correlation_config$minimum_complete_pairs %||% 10L)
  if (!is.finite(correlation_minimum_n) || correlation_minimum_n < 3L) {
    stop("correlation$minimum_complete_pairs must be an integer of at least 3.", call. = FALSE)
  }

  correlation_normality_alpha <- as.numeric(correlation_config$normality_alpha %||% alpha)
  if (length(correlation_normality_alpha) != 1L ||
      !is.finite(correlation_normality_alpha) ||
      correlation_normality_alpha <= 0 || correlation_normality_alpha >= 1) {
    stop("correlation$normality_alpha must be strictly between 0 and 1.", call. = FALSE)
  }

  correlation_p_adjust <- as.character(
    correlation_config$p_adjust %||% "bonferroni"
  )
  if (length(correlation_p_adjust) != 1L ||
      !correlation_p_adjust %in% stats::p.adjust.methods) {
    stop(
      "correlation$p_adjust must be one of: ",
      paste(stats::p.adjust.methods, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  correlation_label_wrap_width <- as.integer(correlation_config$label_wrap_width %||% 18L)
  if (!is.finite(correlation_label_wrap_width) || correlation_label_wrap_width <= 0L) {
    stop("correlation$label_wrap_width must be a positive integer.", call. = FALSE)
  }

  error_bar <- tolower(config$plots$error_bar %||% "sd")
  if (!error_bar %in% c("sd", "se")) {
    stop("plots$error_bar must be 'sd' or 'se'.", call. = FALSE)
  }

  p_adjust <- config$analysis$p_adjust
  if (length(p_adjust) != 1L || is.na(p_adjust) || !nzchar(trimws(as.character(p_adjust)))) {
    stop("analysis$p_adjust must be one non-empty adjustment-method name.", call. = FALSE)
  }

  random_seed <- config$analysis$random_seed %||% 20260731L
  if (length(random_seed) != 1L || !is.numeric(random_seed) || !is.finite(random_seed)) {
    stop("analysis$random_seed must be one finite numeric value.", call. = FALSE)
  }

  for (setting_name in c("main_alpha", "interaction_alpha")) {
    setting_value <- config$plots[[setting_name]]
    if (!is.null(setting_value) &&
        (length(setting_value) != 1L || !is.numeric(setting_value) ||
         !is.finite(setting_value) || setting_value < 0 || setting_value > 1)) {
      stop("plots$", setting_name, " must be between 0 and 1.", call. = FALSE)
    }
  }

  positive_plot_settings <- c(
    "base_font_size", "stat_font_size", "title_wrap_width",
    "page_title_wrap_width", "interaction_ncol", "caption_wrap_width",
    "pdf_width", "pdf_height", "three_way_facet_rows"
  )
  for (setting_name in positive_plot_settings) {
    setting_value <- config$plots[[setting_name]]
    if (!is.null(setting_value) &&
        (length(setting_value) != 1L || !is.numeric(setting_value) ||
         !is.finite(setting_value) || setting_value <= 0)) {
      stop("plots$", setting_name, " must be one positive numeric value.", call. = FALSE)
    }
  }

  if (!is.null(config$output$directory) &&
      (length(config$output$directory) != 1L || !is.character(config$output$directory) ||
       is.na(config$output$directory))) {
    stop("output$directory must be NULL or one path string.", call. = FALSE)
  }
  if (!is.null(config$plots$create_pdf) &&
      (length(config$plots$create_pdf) != 1L || !is.logical(config$plots$create_pdf) ||
       is.na(config$plots$create_pdf))) {
    stop("plots$create_pdf must be TRUE or FALSE.", call. = FALSE)
  }
  for (setting_name in c("save_art_diagnostics", "save_logs")) {
    setting_value <- config$output[[setting_name]]
    if (!is.null(setting_value) &&
        (length(setting_value) != 1L || !is.logical(setting_value) || is.na(setting_value))) {
      stop("output$", setting_name, " must be TRUE or FALSE.", call. = FALSE)
    }
  }

  if (!is.null(config$plots$factor_colors)) {
    for (code in enabled_factors$code) {
      configured_colors <- config$plots$factor_colors[[code]]
      if (is.null(configured_colors)) next
      configured_levels <- as.character(config$factor_levels[[code]])
      if (is.null(names(configured_colors)) || any(!nzchar(names(configured_colors)))) {
        if (length(configured_colors) != length(configured_levels)) {
          stop("Unnamed colors for factor ", code, " must contain one color per configured level.", call. = FALSE)
        }
      } else {
        missing_color_levels <- setdiff(configured_levels, names(configured_colors))
        if (length(missing_color_levels) > 0L) {
          stop(
            "Missing colors for factor ", code, ": ",
            paste(missing_color_levels, collapse = ", "),
            call. = FALSE
          )
        }
      }
      invalid_color <- vapply(
        as.character(configured_colors),
        function(value) inherits(try(grDevices::col2rgb(value), silent = TRUE), "try-error"),
        logical(1)
      )
      if (any(invalid_color)) {
        stop("Invalid color value(s) configured for factor ", code, ".", call. = FALSE)
      }
    }
  }

  if (length(config$packages$auto_install) != 1L ||
      !is.logical(config$packages$auto_install) || is.na(config$packages$auto_install)) {
    stop("packages$auto_install must be TRUE or FALSE.", call. = FALSE)
  }
  if (length(config$packages$repository) != 1L ||
      !is.character(config$packages$repository) || is.na(config$packages$repository) ||
      !nzchar(trimws(config$packages$repository))) {
    stop("packages$repository must be one non-empty repository URL.", call. = FALSE)
  }

  if (nrow(enabled_factors) == 3L && !is.null(config$plots$three_way_mapping)) {
    mapping_values <- unlist(config$plots$three_way_mapping[c("x", "color", "facet")], use.names = FALSE)
    if (length(mapping_values) != 3L || anyDuplicated(mapping_values) ||
        !all(mapping_values %in% enabled_factors$code)) {
      stop(
        "plots$three_way_mapping must assign three distinct enabled factor codes to x, color, and facet.",
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

install_and_load_packages <- function(config) {
  required_packages <- c(
    "readxl", "readr", "dplyr", "tidyr", "purrr", "stringr", "tibble",
    "car", "ARTool", "emmeans", "ggplot2", "openxlsx", "fs", "rlang", "patchwork"
  )

  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]

  auto_install <- isTRUE(config$packages$auto_install)
  if (length(missing_packages) > 0L && !auto_install) {
    stop(
      "Missing R packages: ", paste(missing_packages, collapse = ", "),
      ". Install them or set packages$auto_install = TRUE.",
      call. = FALSE
    )
  }

  if (length(missing_packages) > 0L) {
    install.packages(
      missing_packages,
      repos = config$packages$repository %||% "https://cloud.r-project.org",
      dependencies = TRUE
    )
  }

  invisible(lapply(required_packages, library, character.only = TRUE))
}

read_input_file <- function(file_path, sheet = NULL) {
  extension <- tolower(tools::file_ext(file_path))
  if (extension %in% c("xlsx", "xls")) {
    return(readxl::read_excel(file_path, sheet = sheet %||% 1))
  }
  if (extension == "csv") {
    return(readr::read_csv(file_path, show_col_types = FALSE, progress = FALSE))
  }
  if (extension %in% c("tsv", "txt")) {
    return(readr::read_tsv(file_path, show_col_types = FALSE, progress = FALSE))
  }
  if (extension == "rds") {
    return(readRDS(file_path))
  }
  stop("Unsupported input-file extension: ", extension, call. = FALSE)
}

prepare_input_data <- function(raw_data, config) {
  factor_spec <- config$factors[config$factors$enabled %in% TRUE, , drop = FALSE]
  id_column <- config$input$id_column
  data_format <- tolower(config$input$data_format %||% "wide")

  if (data_format == "long") {
    outcome_name_column <- config$input$long$outcome_name_column
    outcome_value_column <- config$input$long$outcome_value_column
    required_long_columns <- c(id_column, factor_spec$column, outcome_name_column, outcome_value_column)
    missing_long_columns <- setdiff(required_long_columns, names(raw_data))
    if (length(missing_long_columns) > 0L) {
      stop("Long-format input is missing columns: ", paste(missing_long_columns, collapse = ", "), call. = FALSE)
    }

    duplicate_keys <- raw_data |>
      dplyr::count(dplyr::across(dplyr::all_of(c(id_column, factor_spec$column, outcome_name_column)))) |>
      dplyr::filter(.data$n > 1L)
    if (nrow(duplicate_keys) > 0L) {
      stop("Long-format input contains duplicate ID/factor/outcome rows.", call. = FALSE)
    }

    raw_data <- raw_data |>
      tidyr::pivot_wider(
        id_cols = dplyr::all_of(c(id_column, factor_spec$column)),
        names_from = dplyr::all_of(outcome_name_column),
        values_from = dplyr::all_of(outcome_value_column)
      )
  }

  required_base_columns <- c(id_column, factor_spec$column)
  missing_base_columns <- setdiff(required_base_columns, names(raw_data))
  if (length(missing_base_columns) > 0L) {
    stop("Input data is missing ID or factor columns: ", paste(missing_base_columns, collapse = ", "), call. = FALSE)
  }

  outcome_spec <- config$outcomes
  if (is.null(outcome_spec)) {
    excluded_columns <- c(id_column, factor_spec$column)
    candidate_columns <- setdiff(names(raw_data), excluded_columns)
    numeric_columns <- candidate_columns[vapply(raw_data[candidate_columns], is.numeric, logical(1))]
    outcome_spec <- data.frame(
      column = numeric_columns,
      label = numeric_columns,
      category = "Uncategorized",
      enabled = TRUE,
      include_in_correlation = TRUE,
      stringsAsFactors = FALSE
    )
  }
  if (!"include_in_correlation" %in% names(outcome_spec)) {
    outcome_spec$include_in_correlation <- TRUE
  }
  outcome_spec <- outcome_spec[outcome_spec$enabled %in% TRUE, , drop = FALSE]
  if (nrow(outcome_spec) == 0L) stop("No dependent variables are enabled.", call. = FALSE)

  missing_outcomes <- setdiff(outcome_spec$column, names(raw_data))
  if (length(missing_outcomes) > 0L) {
    stop("Input data is missing outcome columns: ", paste(missing_outcomes, collapse = ", "), call. = FALSE)
  }

  analysis_data <- tibble::tibble(ID = raw_data[[id_column]])
  for (i in seq_len(nrow(factor_spec))) {
    code <- factor_spec$code[[i]]
    source_column <- factor_spec$column[[i]]
    configured_levels <- as.character(config$factor_levels[[code]])
    observed_levels <- unique(as.character(raw_data[[source_column]]))
    unknown_levels <- setdiff(observed_levels[!is.na(observed_levels)], configured_levels)
    if (length(unknown_levels) > 0L) {
      stop(
        "Factor ", source_column, " contains levels not listed in factor_levels$", code,
        ": ", paste(unknown_levels, collapse = ", "),
        call. = FALSE
      )
    }
    analysis_data[[code]] <- factor(as.character(raw_data[[source_column]]), levels = configured_levels)
  }

  conversion_report <- list()
  for (i in seq_len(nrow(outcome_spec))) {
    source_column <- outcome_spec$column[[i]]
    original_values <- raw_data[[source_column]]

    # Converting a factor directly with as.numeric() returns its internal level
    # codes rather than the displayed values. Convert character/factor columns
    # through as.character() so values such as "4.5" remain 4.5.
    numeric_values <- if (is.numeric(original_values)) {
      as.numeric(original_values)
    } else {
      suppressWarnings(as.numeric(as.character(original_values)))
    }

    failed_conversion <- sum(!is.na(original_values) & is.na(numeric_values))
    non_finite_values <- sum(!is.na(numeric_values) & !is.finite(numeric_values))
    analysis_data[[source_column]] <- numeric_values
    conversion_report[[length(conversion_report) + 1L]] <- tibble::tibble(
      DV = outcome_spec$label[[i]],
      Category = outcome_spec$category[[i]],
      Source_Column = source_column,
      Non_Numeric_Values_Converted_to_NA = failed_conversion,
      Non_Finite_Numeric_Values = non_finite_values
    )
  }

  list(
    data = analysis_data,
    factor_spec = factor_spec,
    outcome_spec = outcome_spec,
    conversion_report = dplyr::bind_rows(conversion_report)
  )
}

p_to_label <- function(p) {
  dplyr::case_when(
    is.na(p) ~ "",
    p < 0.001 ~ "***",
    p < 0.01 ~ "**",
    p < 0.05 ~ "*",
    p < 0.10 ~ ".",
    TRUE ~ "n.s."
  )
}

category_page_significance_note <- function() {
  paste(
    "p < 0.001: ***",
    "p < 0.01: **",
    "p < 0.05: *",
    "p < 0.10: .",
    "p >= 0.10: n.s.",
    sep = "\n"
  )
}

format_p_for_plot <- function(p) {
  if (is.na(p)) return("p=NA")
  if (p < 0.001) return("p<.001")
  paste0("p=", sub("^0", "", sprintf("%.3f", p)))
}

partial_eta2_from_f <- function(f_value, df1, df2) {
  ifelse(
    is.finite(f_value) & is.finite(df1) & is.finite(df2) & f_value >= 0,
    (f_value * df1) / (f_value * df1 + df2),
    NA_real_
  )
}

cohens_f_from_eta2 <- function(eta2) {
  ifelse(is.finite(eta2) & eta2 >= 0 & eta2 < 1, sqrt(eta2 / (1 - eta2)), NA_real_)
}

eta2_magnitude <- function(eta2) {
  dplyr::case_when(
    is.na(eta2) ~ NA_character_,
    eta2 < 0.01 ~ "negligible",
    eta2 < 0.06 ~ "small",
    eta2 < 0.14 ~ "medium",
    TRUE ~ "large"
  )
}

capture_warnings <- function(expression) {
  warning_messages <- character(0)
  value <- withCallingHandlers(
    expression,
    warning = function(w) {
      warning_messages <<- c(warning_messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = unique(warning_messages))
}

safe_shapiro <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3L) return(list(W = NA_real_, p = NA_real_, note = "Fewer than three observations"))
  if (length(unique(x)) < 2L) return(list(W = NA_real_, p = NA_real_, note = "Constant values"))
  sampled <- FALSE
  if (length(x) > 5000L) {
    x <- sample(x, 5000L)
    sampled <- TRUE
  }
  result <- tryCatch(stats::shapiro.test(x), error = function(e) e)
  if (inherits(result, "error")) return(list(W = NA_real_, p = NA_real_, note = conditionMessage(result)))
  list(
    W = unname(result$statistic),
    p = unname(result$p.value),
    note = if (sampled) "Random sample of 5,000 observations" else ""
  )
}

get_correlation_config <- function(config) {
  correlation_config <- config$correlation %||% list()
  list(
    enabled = isTRUE(correlation_config$enabled %||% TRUE),
    minimum_complete_pairs = as.integer(correlation_config$minimum_complete_pairs %||% 10L),
    normality_alpha = as.numeric(correlation_config$normality_alpha %||% config$analysis$alpha),
    p_adjust = as.character(
      correlation_config$p_adjust %||% "bonferroni"
    ),
    label_wrap_width = as.integer(correlation_config$label_wrap_width %||% 18L)
  )
}

make_correlation_matrix_frame <- function(matrix_object, variable_labels) {
  frame <- as.data.frame(matrix_object, stringsAsFactors = FALSE)
  names(frame) <- variable_labels
  frame <- cbind(
    data.frame(Variable = variable_labels, check.names = FALSE, stringsAsFactors = FALSE),
    frame
  )
  rownames(frame) <- NULL
  frame
}

make_correlation_heatmap <- function(
    coefficient_matrix,
    adjusted_p_matrix,
    variable_labels,
    selected_method,
    config) {
  if (length(variable_labels) < 2L) return(NULL)

  correlation_config <- get_correlation_config(config)
  heatmap_frame <- expand.grid(
    Row = variable_labels,
    Column = variable_labels,
    stringsAsFactors = FALSE
  )
  heatmap_frame$Row_Index <- match(heatmap_frame$Row, variable_labels)
  heatmap_frame$Column_Index <- match(heatmap_frame$Column, variable_labels)
  heatmap_frame$Coefficient <- mapply(
    function(row_label, column_label) coefficient_matrix[row_label, column_label],
    heatmap_frame$Row,
    heatmap_frame$Column
  )
  heatmap_frame$Adjusted_p <- mapply(
    function(row_label, column_label) adjusted_p_matrix[row_label, column_label],
    heatmap_frame$Row,
    heatmap_frame$Column
  )

  # Use complementary halves of the matrix to prevent coefficient,
  # significance, and method labels from overlapping in the same cell.
  # The lower triangle contains only coefficients, the upper triangle contains
  # only adjusted-p significance labels, and the diagonal is intentionally blank.
  significance_label <- p_to_label(heatmap_frame$Adjusted_p)
  significance_label[is.na(heatmap_frame$Adjusted_p)] <- "NA"
  coefficient_label <- ifelse(
    is.na(heatmap_frame$Coefficient),
    "NA",
    sprintf("%.2f", heatmap_frame$Coefficient)
  )
  heatmap_frame$Cell_Label <- dplyr::case_when(
    heatmap_frame$Row_Index > heatmap_frame$Column_Index ~ coefficient_label,
    heatmap_frame$Row_Index < heatmap_frame$Column_Index ~ significance_label,
    TRUE ~ ""
  )
  heatmap_frame$Text_Color <- ifelse(
    is.finite(heatmap_frame$Coefficient) & abs(heatmap_frame$Coefficient) >= 0.55,
    "white",
    "black"
  )

  display_labels <- setNames(
    stringr::str_wrap(variable_labels, width = correlation_config$label_wrap_width),
    variable_labels
  )
  heatmap_frame$Column <- factor(heatmap_frame$Column, levels = variable_labels)
  heatmap_frame$Row <- factor(heatmap_frame$Row, levels = rev(variable_labels))

  coefficient_symbol <- if (identical(selected_method, "Pearson")) "r" else "rho"

  ggplot2::ggplot(
    heatmap_frame,
    ggplot2::aes(x = .data$Column, y = .data$Row, fill = .data$Coefficient)
  ) +
    ggplot2::geom_tile(color = "white", linewidth = 0.35) +
    ggplot2::geom_text(
      ggplot2::aes(label = .data$Cell_Label, color = .data$Text_Color),
      size = 3.1,
      lineheight = 0.92,
      na.rm = TRUE
    ) +
    ggplot2::scale_color_identity() +
    ggplot2::scale_fill_gradient2(
      low = "#B2182B",
      mid = "#F7F7F7",
      high = "#2166AC",
      midpoint = 0,
      limits = c(-1, 1),
      na.value = "grey90",
      name = "Correlation"
    ) +
    ggplot2::scale_x_discrete(labels = display_labels, drop = FALSE) +
    ggplot2::scale_y_discrete(labels = display_labels, drop = FALSE) +
    ggplot2::coord_fixed() +
    ggplot2::labs(
      title = paste0("Correlation Heatmap (", selected_method, ")"),
      subtitle = paste0(
        "Lower triangle: correlation coefficients; upper triangle: adjusted-p significance symbols"
      ),
      caption = paste0(
        "Lower triangle reports ", coefficient_symbol,
        "; upper triangle uses ", correlation_config$p_adjust,
        "-adjusted p values; diagonal cells are omitted"
      ),
      x = NULL,
      y = NULL
    ) +
    ggplot2::theme_minimal(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 18, face = "bold", hjust = 0.5),
      plot.subtitle = ggplot2::element_text(size = 11, hjust = 0.5),
      plot.caption = ggplot2::element_text(size = 9, hjust = 0),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, vjust = 1, size = 8.5),
      axis.text.y = ggplot2::element_text(size = 8.5),
      panel.grid = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(20, 25, 20, 25)
    )
}

analyze_correlations <- function(analysis_data, outcome_spec, config) {
  correlation_config <- get_correlation_config(config)
  empty_result <- list(
    enabled = correlation_config$enabled,
    included_outcomes = tibble::tibble(),
    selected_method = NA_character_,
    method_selection_reason = NA_character_,
    variable_normality = tibble::tibble(),
    results = tibble::tibble(),
    coefficient_matrix = tibble::tibble(),
    method_matrix = tibble::tibble(),
    adjusted_p_matrix = tibble::tibble(),
    heatmap = NULL,
    warnings_errors = tibble::tibble()
  )
  if (!correlation_config$enabled) return(empty_result)

  correlation_spec <- outcome_spec |>
    dplyr::filter(.data$include_in_correlation %in% TRUE)
  empty_result$included_outcomes <- correlation_spec

  if (nrow(correlation_spec) < 2L) {
    empty_result$warnings_errors <- tibble::tibble(
      DV = NA_character_,
      Category = "Correlation Analysis",
      Stage = "Correlation analysis",
      Type = "Warning",
      Message = "Fewer than two enabled dependent variables were selected for correlation analysis."
    )
    return(empty_result)
  }

  variable_labels <- as.character(correlation_spec$label)
  variable_columns <- as.character(correlation_spec$column)
  variable_categories <- as.character(correlation_spec$category)
  names(variable_columns) <- variable_labels
  names(variable_categories) <- variable_labels

  # Select one common method for the complete correlation analysis. Normality
  # is evaluated once for every included variable using all of its finite
  # observations. Pearson is used only when every variable passes the same
  # eligibility rule; otherwise every tested pair uses Spearman.
  variable_normality_records <- lapply(seq_along(variable_labels), function(index) {
    variable_label <- variable_labels[[index]]
    variable_column <- variable_columns[[variable_label]]
    values <- as.numeric(analysis_data[[variable_column]])
    finite_values <- values[is.finite(values)]
    n_finite <- length(finite_values)
    n_unique <- length(unique(finite_values))
    shapiro_result <- safe_shapiro(finite_values)
    pearson_eligible <-
      n_finite >= correlation_config$minimum_complete_pairs &&
      n_unique >= 3L &&
      is.finite(shapiro_result$p) &&
      shapiro_result$p >= correlation_config$normality_alpha

    eligibility_reason <- if (n_finite < correlation_config$minimum_complete_pairs) {
      paste0(
        "Fewer than ", correlation_config$minimum_complete_pairs,
        " finite observations."
      )
    } else if (n_unique < 3L) {
      "Fewer than three unique finite values."
    } else if (!is.finite(shapiro_result$p)) {
      "Shapiro-Wilk normality could not be evaluated."
    } else if (shapiro_result$p < correlation_config$normality_alpha) {
      paste0(
        "Shapiro-Wilk p < ", correlation_config$normality_alpha, "."
      )
    } else {
      paste0(
        "Shapiro-Wilk p >= ", correlation_config$normality_alpha,
        " and at least three unique values."
      )
    }

    tibble::tibble(
      Variable = variable_label,
      Category = variable_categories[[variable_label]],
      N_Finite = n_finite,
      N_Unique = n_unique,
      Shapiro_W = shapiro_result$W,
      Shapiro_p = shapiro_result$p,
      Normality_Alpha = correlation_config$normality_alpha,
      Shapiro_Decision = if (is.finite(shapiro_result$p)) {
        ifelse(
          shapiro_result$p >= correlation_config$normality_alpha,
          "Pass",
          "Fail"
        )
      } else {
        "Not evaluable"
      },
      Pearson_Eligible = pearson_eligible,
      Eligibility_Reason = eligibility_reason,
      Note = shapiro_result$note
    )
  })
  variable_normality <- dplyr::bind_rows(variable_normality_records)

  all_variables_pearson_eligible <-
    nrow(variable_normality) > 0L &&
    all(variable_normality$Pearson_Eligible %in% TRUE)
  selected_method <- if (all_variables_pearson_eligible) "Pearson" else "Spearman"

  if (identical(selected_method, "Pearson")) {
    method_selection_reason <- paste0(
      "Pearson was selected uniformly because every included variable passed ",
      "Shapiro-Wilk normality at alpha = ", correlation_config$normality_alpha,
      " and contained at least three unique finite values."
    )
  } else {
    method_selection_reason <- paste0(
      "Spearman was selected uniformly because at least one included variable ",
      "failed or could not be evaluated under the Pearson eligibility rule. ",
      "See 18_Correlation_Normality for variable-level diagnostics."
    )
  }

  variable_normality <- variable_normality |>
    dplyr::mutate(
      Correlation_Method = selected_method,
      Correlation_Method_Selection_Reason = method_selection_reason
    )

  pair_indexes <- utils::combn(seq_along(variable_labels), 2L, simplify = FALSE)
  pair_results <- vector("list", length(pair_indexes))
  warning_records <- list()

  for (pair_index in seq_along(pair_indexes)) {
    indexes <- pair_indexes[[pair_index]]
    label_1 <- variable_labels[[indexes[[1]]]]
    label_2 <- variable_labels[[indexes[[2]]]]
    column_1 <- variable_columns[[label_1]]
    column_2 <- variable_columns[[label_2]]

    normality_1 <- variable_normality |>
      dplyr::filter(.data$Variable == .env$label_1) |>
      dplyr::slice(1L)
    normality_2 <- variable_normality |>
      dplyr::filter(.data$Variable == .env$label_2) |>
      dplyr::slice(1L)

    x <- as.numeric(analysis_data[[column_1]])
    y <- as.numeric(analysis_data[[column_2]])
    complete_rows <- is.finite(x) & is.finite(y)
    x_complete <- x[complete_rows]
    y_complete <- y[complete_rows]
    n_complete <- length(x_complete)
    pair_unique_1 <- length(unique(x_complete))
    pair_unique_2 <- length(unique(y_complete))

    method <- selected_method
    method_reason <- method_selection_reason
    coefficient <- NA_real_
    statistic_name <- NA_character_
    statistic <- NA_real_
    parameter <- NA_real_
    p_value <- NA_real_
    note <- ""

    if (n_complete < correlation_config$minimum_complete_pairs) {
      method <- NA_character_
      method_reason <- paste0(
        "Not tested: ", n_complete,
        " complete pairs, below minimum ", correlation_config$minimum_complete_pairs,
        ". The globally selected method was ", selected_method, "."
      )
    } else if (pair_unique_1 < 2L || pair_unique_2 < 2L) {
      method <- NA_character_
      method_reason <- paste0(
        "Not tested: at least one variable is constant in the pairwise-complete sample. ",
        "The globally selected method was ", selected_method, "."
      )
    } else if (
      identical(selected_method, "Pearson") &&
      (pair_unique_1 < 3L || pair_unique_2 < 3L)
    ) {
      method <- NA_character_
      method_reason <- paste0(
        "Not tested: the uniform Pearson rule requires at least three unique values ",
        "for both variables in the pairwise-complete sample."
      )
    } else {
      test_capture <- tryCatch(
        capture_warnings(
          if (identical(selected_method, "Pearson")) {
            stats::cor.test(x_complete, y_complete, method = "pearson")
          } else {
            stats::cor.test(x_complete, y_complete, method = "spearman", exact = FALSE)
          }
        ),
        error = function(e) e
      )

      if (inherits(test_capture, "error")) {
        note <- conditionMessage(test_capture)
        warning_records[[length(warning_records) + 1L]] <- tibble::tibble(
          DV = paste(label_1, "vs", label_2),
          Category = "Correlation Analysis",
          Stage = "Correlation test",
          Type = "Error",
          Message = conditionMessage(test_capture)
        )
      } else {
        test_result <- test_capture$value
        coefficient <- unname(test_result$estimate[[1]])
        statistic_names <- names(test_result$statistic)
        statistic_name <- if (length(statistic_names) > 0L) statistic_names[[1]] else NA_character_
        statistic <- unname(test_result$statistic[[1]])
        parameter <- if (!is.null(test_result$parameter)) {
          unname(test_result$parameter[[1]])
        } else {
          NA_real_
        }
        p_value <- unname(test_result$p.value)
        if (length(test_capture$warnings) > 0L) {
          note <- paste(test_capture$warnings, collapse = " | ")
          warning_records[[length(warning_records) + 1L]] <- tibble::tibble(
            DV = paste(label_1, "vs", label_2),
            Category = "Correlation Analysis",
            Stage = "Correlation test",
            Type = "Warning",
            Message = note
          )
        }
      }
    }

    pair_results[[pair_index]] <- tibble::tibble(
      Variable_1 = label_1,
      Category_1 = variable_categories[[label_1]],
      Variable_2 = label_2,
      Category_2 = variable_categories[[label_2]],
      N_Complete = n_complete,
      Variable_1_Unique = normality_1$N_Unique[[1]],
      Variable_2_Unique = normality_2$N_Unique[[1]],
      Variable_1_Shapiro_W = normality_1$Shapiro_W[[1]],
      Variable_1_Shapiro_p = normality_1$Shapiro_p[[1]],
      Variable_2_Shapiro_W = normality_2$Shapiro_W[[1]],
      Variable_2_Shapiro_p = normality_2$Shapiro_p[[1]],
      Normality_Alpha = correlation_config$normality_alpha,
      Method = method,
      Method_Selection_Reason = method_reason,
      Coefficient = coefficient,
      Statistic_Name = statistic_name,
      Statistic = statistic,
      Parameter = parameter,
      p_value = p_value,
      Note = note
    )
  }

  result_frame <- dplyr::bind_rows(pair_results)
  result_frame$p_adjusted <- NA_real_
  valid_p <- is.finite(result_frame$p_value)
  if (any(valid_p)) {
    result_frame$p_adjusted[valid_p] <- stats::p.adjust(
      result_frame$p_value[valid_p],
      method = correlation_config$p_adjust
    )
  }
  result_frame <- result_frame |>
    dplyr::mutate(
      P_Adjustment = correlation_config$p_adjust,
      Significance = p_to_label(.data$p_adjusted),
      Significant = !is.na(.data$p_adjusted) & .data$p_adjusted < config$analysis$alpha
    )

  coefficient_matrix <- matrix(
    NA_real_,
    nrow = length(variable_labels),
    ncol = length(variable_labels),
    dimnames = list(variable_labels, variable_labels)
  )
  adjusted_p_matrix <- coefficient_matrix
  method_matrix <- matrix(
    NA_character_,
    nrow = length(variable_labels),
    ncol = length(variable_labels),
    dimnames = list(variable_labels, variable_labels)
  )
  diag(coefficient_matrix) <- 1
  diag(adjusted_p_matrix) <- NA_real_
  diag(method_matrix) <- "Self"

  for (row_index in seq_len(nrow(result_frame))) {
    label_1 <- result_frame$Variable_1[[row_index]]
    label_2 <- result_frame$Variable_2[[row_index]]
    coefficient_matrix[label_1, label_2] <- result_frame$Coefficient[[row_index]]
    coefficient_matrix[label_2, label_1] <- result_frame$Coefficient[[row_index]]
    adjusted_p_matrix[label_1, label_2] <- result_frame$p_adjusted[[row_index]]
    adjusted_p_matrix[label_2, label_1] <- result_frame$p_adjusted[[row_index]]
    method_matrix[label_1, label_2] <- result_frame$Method[[row_index]]
    method_matrix[label_2, label_1] <- result_frame$Method[[row_index]]
  }

  heatmap <- make_correlation_heatmap(
    coefficient_matrix,
    adjusted_p_matrix,
    variable_labels,
    selected_method,
    config
  )

  list(
    enabled = TRUE,
    included_outcomes = correlation_spec,
    selected_method = selected_method,
    method_selection_reason = method_selection_reason,
    variable_normality = variable_normality,
    results = result_frame,
    coefficient_matrix = make_correlation_matrix_frame(coefficient_matrix, variable_labels),
    method_matrix = make_correlation_matrix_frame(method_matrix, variable_labels),
    adjusted_p_matrix = make_correlation_matrix_frame(adjusted_p_matrix, variable_labels),
    heatmap = heatmap,
    warnings_errors = dplyr::bind_rows(warning_records)
  )
}

safe_levene <- function(data, factor_codes, center_name) {
  group <- interaction(data[factor_codes], drop = TRUE, lex.order = TRUE)
  center_function <- if (tolower(center_name) == "mean") base::mean else stats::median
  result <- tryCatch(
    car::leveneTest(data$Y, group, center = center_function),
    error = function(e) e
  )
  if (inherits(result, "error")) {
    return(list(F = NA_real_, df1 = NA_real_, df2 = NA_real_, p = NA_real_, note = conditionMessage(result)))
  }
  result_frame <- as.data.frame(result, check.names = FALSE)
  f_column <- grep("F", names(result_frame), value = TRUE)[[1]]
  p_column <- grep("Pr", names(result_frame), value = TRUE)[[1]]
  list(
    F = as.numeric(result_frame[[f_column]][[1]]),
    df1 = as.numeric(result_frame$Df[[1]]),
    df2 = as.numeric(result_frame$Df[[nrow(result_frame)]]),
    p = as.numeric(result_frame[[p_column]][[1]]),
    note = paste0(tolower(center_name), "-centered Levene test")
  )
}

generate_effect_codes <- function(factor_codes, max_order) {
  max_order <- min(length(factor_codes), max_order)
  unlist(lapply(seq_len(max_order), function(order) {
    apply(utils::combn(factor_codes, order), 2L, paste, collapse = ":")
  }), use.names = FALSE)
}

factor_label <- function(code, factor_spec, short = FALSE) {
  row <- factor_spec[factor_spec$code == code, , drop = FALSE]
  if (nrow(row) == 0L) return(code)
  if (short) row$short_label[[1]] else row$label[[1]]
}

effect_label <- function(effect_code, factor_spec, short = FALSE) {
  codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
  paste(vapply(codes, factor_label, character(1), factor_spec = factor_spec, short = short), collapse = " × ")
}

wrap_plot_title <- function(text, config, page = FALSE) {
  configured_width <- if (isTRUE(page)) {
    config$plots$page_title_wrap_width %||% 70L
  } else {
    config$plots$title_wrap_width %||% 58L
  }
  stringr::str_wrap(as.character(text), width = configured_width)
}

summarise_groups <- function(data, grouping_variables, outcome_label, category, effect_code, factor_spec) {
  data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grouping_variables))) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      SE = .data$SD / sqrt(.data$N),
      Median = stats::median(.data$Y, na.rm = TRUE),
      IQR = stats::IQR(.data$Y, na.rm = TRUE),
      Min = min(.data$Y, na.rm = TRUE),
      Max = max(.data$Y, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      DV = outcome_label,
      Category = category,
      Effect_Code = effect_code,
      Effect_Label = effect_label(effect_code, factor_spec),
      .before = 1
    )
}


extract_anova_table <- function(model, outcome_label, category, factor_spec, anova_type, alpha) {
  table <- as.data.frame(car::Anova(model, type = anova_type), check.names = FALSE)
  table$Effect_Code <- rownames(table)
  rownames(table) <- NULL

  f_candidates <- grep("^F", names(table), value = TRUE)
  p_candidates <- grep("Pr", names(table), value = TRUE)
  ss_candidates <- grep("Sum Sq", names(table), value = TRUE)
  if (length(f_candidates) == 0L || length(p_candidates) == 0L || length(ss_candidates) == 0L) {
    stop(
      "Could not identify the F, p-value, or sum-of-squares columns in the car::Anova() table.",
      call. = FALSE
    )
  }

  f_column <- f_candidates[[1]]
  p_column <- p_candidates[[1]]
  ss_column <- ss_candidates[[1]]
  residual_df <- stats::df.residual(model)

  table |>
    dplyr::filter(.data$Effect_Code != "(Intercept)") |>
    dplyr::transmute(
      DV = outcome_label,
      Category = category,
      Model_Method = paste0("ANOVA (Type ", anova_type, ")"),
      Effect_Code = .data$Effect_Code,
      Effect_Label = vapply(.data$Effect_Code, effect_label, character(1), factor_spec = factor_spec),
      df1 = as.numeric(.data$Df),
      df2 = residual_df,
      Sum_Squares = as.numeric(.data[[ss_column]]),
      Mean_Square = .data$Sum_Squares / .data$df1,
      F_value = as.numeric(.data[[f_column]]),
      p_value = as.numeric(.data[[p_column]])
    ) |>
    dplyr::mutate(
      Partial_Eta2 = partial_eta2_from_f(.data$F_value, .data$df1, .data$df2),
      Cohens_f = cohens_f_from_eta2(.data$Partial_Eta2),
      Effect_Size_Magnitude = eta2_magnitude(.data$Partial_Eta2),
      Effect_Size_Scale = "raw response",
      Significance = p_to_label(.data$p_value),
      Significant = !is.na(.data$p_value) & .data$p_value < alpha
    )
}


extract_art_table <- function(model, outcome_label, category, factor_spec, alpha) {
  table <- as.data.frame(stats::anova(model), check.names = FALSE)
  effect_codes <- if ("Term" %in% names(table)) as.character(table$Term) else rownames(table)

  f_candidates <- intersect(c("F", "F value", "F.value"), names(table))
  if (length(f_candidates) == 0L) f_candidates <- grep("^F", names(table), value = TRUE)
  p_candidates <- grep("Pr", names(table), value = TRUE)
  df1_candidates <- intersect(c("Df", "df"), names(table))
  df2_candidates <- intersect(c("Df.res", "Df.residual", "df.res"), names(table))

  if (length(f_candidates) == 0L || length(p_candidates) == 0L ||
      length(df1_candidates) == 0L || length(df2_candidates) == 0L) {
    stop(
      "Could not identify the F, p-value, or degrees-of-freedom columns in the ART ANOVA table.",
      call. = FALSE
    )
  }

  tibble::tibble(
    DV = outcome_label,
    Category = category,
    Model_Method = "ART-ANOVA (Type III)",
    Effect_Code = effect_codes,
    Effect_Label = vapply(effect_codes, effect_label, character(1), factor_spec = factor_spec),
    df1 = as.numeric(table[[df1_candidates[[1]]]]),
    df2 = as.numeric(table[[df2_candidates[[1]]]]),
    Sum_Squares = NA_real_,
    Mean_Square = NA_real_,
    F_value = as.numeric(table[[f_candidates[[1]]]]),
    p_value = as.numeric(table[[p_candidates[[1]]]])
  ) |>
    dplyr::mutate(
      Partial_Eta2 = partial_eta2_from_f(.data$F_value, .data$df1, .data$df2),
      Cohens_f = cohens_f_from_eta2(.data$Partial_Eta2),
      Effect_Size_Magnitude = eta2_magnitude(.data$Partial_Eta2),
      Effect_Size_Scale = "aligned-rank response",
      Significance = p_to_label(.data$p_value),
      Significant = !is.na(.data$p_value) & .data$p_value < alpha
    )
}

add_contrast_metadata <- function(result, outcome_label, category, method, effect_code, contrast_type, estimate_scale, factor_spec, p_adjust, alpha) {
  if (is.null(result) || nrow(result) == 0L) return(tibble::tibble())
  frame <- tibble::as_tibble(as.data.frame(result, check.names = FALSE))
  if ("p.value" %in% names(frame)) {
    frame$Significance <- p_to_label(frame$p.value)
    frame$Significant <- !is.na(frame$p.value) & frame$p.value < alpha
  }
  frame |>
    dplyr::mutate(
      DV = outcome_label,
      Category = category,
      Model_Method = method,
      Effect_Code = effect_code,
      Effect_Label = effect_label(effect_code, factor_spec),
      Contrast_Type = contrast_type,
      P_Adjustment = p_adjust,
      Estimate_Scale = estimate_scale,
      .before = 1
    )
}


parse_pairwise_groups <- function(frame, factor_levels = NULL) {
  if (nrow(frame) == 0L) {
    frame$Group1 <- character(0)
    frame$Group2 <- character(0)
    frame$Group_Parse_Method <- character(0)
    return(frame)
  }

  frame$Group1 <- NA_character_
  frame$Group2 <- NA_character_
  frame$Group_Parse_Method <- "unresolved"

  if (!"contrast" %in% names(frame)) return(frame)

  contrast_text <- as.character(frame$contrast)
  normalized_text <- stringr::str_squish(
    stringr::str_replace_all(contrast_text, "[\u2212\u2013\u2014]", "-")
  )

  if (!is.null(factor_levels)) {
    factor_levels <- as.character(factor_levels)
    expected_pairs <- if (length(factor_levels) >= 2L) {
      as.data.frame(t(utils::combn(factor_levels, 2L)), stringsAsFactors = FALSE)
    } else {
      data.frame(V1 = character(0), V2 = character(0))
    }

    # First match exact labels generated from configured levels. This is more
    # reliable than splitting on a dash when factor levels themselves contain
    # punctuation or when one level name is a substring of another.
    if (nrow(expected_pairs) > 0L) {
      for (row_index in seq_len(nrow(frame))) {
        current_text <- normalized_text[[row_index]]
        for (pair_index in seq_len(nrow(expected_pairs))) {
          first_level <- expected_pairs$V1[[pair_index]]
          second_level <- expected_pairs$V2[[pair_index]]
          forward_label <- stringr::str_squish(paste(first_level, "-", second_level))
          reverse_label <- stringr::str_squish(paste(second_level, "-", first_level))

          if (identical(current_text, forward_label)) {
            frame$Group1[[row_index]] <- first_level
            frame$Group2[[row_index]] <- second_level
            frame$Group_Parse_Method[[row_index]] <- "exact configured-pair label"
            break
          }
          if (identical(current_text, reverse_label)) {
            frame$Group1[[row_index]] <- second_level
            frame$Group2[[row_index]] <- first_level
            frame$Group_Parse_Method[[row_index]] <- "exact configured-pair label"
            break
          }
        }
      }
    }
  }

  unresolved <- is.na(frame$Group1) | is.na(frame$Group2)
  if (any(unresolved)) {
    pieces <- stringr::str_split_fixed(normalized_text[unresolved], "\\s+-\\s+", 2L)
    frame$Group1[unresolved] <- stringr::str_trim(pieces[, 1])
    frame$Group2[unresolved] <- stringr::str_trim(pieces[, 2])
    frame$Group_Parse_Method[unresolved] <- "normalized contrast text"
  }

  if (!is.null(factor_levels)) {
    valid_parse <- frame$Group1 %in% factor_levels & frame$Group2 %in% factor_levels

    # Standard pairwise output follows the combination order of the configured
    # levels. Use this deterministic fallback only when all possible pairwise
    # comparisons are present.
    if (any(!valid_parse) && nrow(frame) == nrow(expected_pairs)) {
      frame$Group1[!valid_parse] <- expected_pairs$V1[!valid_parse]
      frame$Group2[!valid_parse] <- expected_pairs$V2[!valid_parse]
      frame$Group_Parse_Method[!valid_parse] <- "configured-level order fallback"
    }
  }

  frame
}

make_stat_annotation <- function(effect_row) {
  if (is.null(effect_row) || nrow(effect_row) == 0L) return("Effect not available")

  # Build the annotation with R plotmath syntax instead of Unicode characters.
  # This prevents eta and the subscript p from becoming missing-glyph dots in
  # PDF devices whose default fonts do not contain those Unicode glyphs.
  df1_text <- format(round(effect_row$df1[[1]], 3), trim = TRUE)
  df2_text <- format(round(effect_row$df2[[1]], 3), trim = TRUE)
  f_text <- sprintf("%.3f", effect_row$F_value[[1]])
  eta_text <- sprintf("%.3f", effect_row$Partial_Eta2[[1]])
  significance_text <- p_to_label(effect_row$p_value[[1]])
  p_value <- effect_row$p_value[[1]]

  if (is.na(p_value)) {
    p_expression <- "italic(p)==plain(NA)"
  } else if (p_value < 0.001) {
    p_expression <- "italic(p)<.001"
  } else {
    p_expression <- paste0(
      "italic(p)==",
      sub("^0", "", sprintf("%.3f", p_value))
    )
  }

  annotation_text <- paste0(
    "italic(F)(", df1_text, ",", df2_text, ")==", f_text,
    "*','~~", p_expression,
    "*','~~eta[p]^2==", eta_text,
    "~~'", significance_text, "'"
  )

  parse(text = annotation_text)[[1]]
}

get_effect_row <- function(effect_table, effect_code) {
  effect_table |>
    dplyr::filter(.data$Effect_Code == effect_code) |>
    dplyr::slice_head(n = 1L)
}

add_significance_brackets <- function(plot_object, pairwise_frame, x_levels, raw_y, alpha) {
  if (is.null(pairwise_frame) || nrow(pairwise_frame) == 0L || !all(c("Group1", "Group2", "p.value") %in% names(pairwise_frame))) {
    return(plot_object)
  }

  significant <- pairwise_frame |>
    dplyr::mutate(
      Group1 = as.character(.data$Group1),
      Group2 = as.character(.data$Group2),
      p.value = suppressWarnings(as.numeric(.data$p.value))
    ) |>
    dplyr::filter(!is.na(.data$p.value), .data$p.value < alpha) |>
    dplyr::mutate(
      xmin = match(.data$Group1, as.character(x_levels)),
      xmax = match(.data$Group2, as.character(x_levels))
    ) |>
    dplyr::filter(!is.na(.data$xmin), !is.na(.data$xmax), .data$xmin != .data$xmax) |>
    dplyr::arrange(abs(.data$xmax - .data$xmin), .data$p.value)

  if (nrow(significant) == 0L) return(plot_object)
  y_values <- raw_y[is.finite(raw_y)]
  y_min <- min(y_values)
  y_max <- max(y_values)
  y_span <- y_max - y_min
  if (!is.finite(y_span) || y_span == 0) y_span <- max(abs(y_values), 1)

  significant <- significant |>
    dplyr::mutate(
      y_position = y_max + 0.10 * y_span + (dplyr::row_number() - 1L) * 0.11 * y_span,
      label = p_to_label(.data$p.value)
    )
  tick <- 0.025 * y_span

  plot_object +
    ggplot2::geom_segment(
      data = significant,
      ggplot2::aes(x = .data$xmin, xend = .data$xmax, y = .data$y_position, yend = .data$y_position),
      inherit.aes = FALSE,
      linewidth = 0.45
    ) +
    ggplot2::geom_segment(
      data = significant,
      ggplot2::aes(x = .data$xmin, xend = .data$xmin, y = .data$y_position, yend = .data$y_position - tick),
      inherit.aes = FALSE,
      linewidth = 0.45
    ) +
    ggplot2::geom_segment(
      data = significant,
      ggplot2::aes(x = .data$xmax, xend = .data$xmax, y = .data$y_position, yend = .data$y_position - tick),
      inherit.aes = FALSE,
      linewidth = 0.45
    ) +
    ggplot2::geom_text(
      data = significant,
      ggplot2::aes(x = (.data$xmin + .data$xmax) / 2, y = .data$y_position + 0.015 * y_span, label = .data$label),
      inherit.aes = FALSE,
      size = 4
    ) +
    ggplot2::expand_limits(y = max(significant$y_position) + 0.08 * y_span)
}


get_factor_colors <- function(factor_code, data, config) {
  factor_levels <- levels(data[[factor_code]])
  configured <- config$plots$factor_colors[[factor_code]]
  if (is.null(configured)) {
    configured <- grDevices::hcl.colors(length(factor_levels), palette = "Dark 3")
    names(configured) <- factor_levels
    return(configured)
  }
  configured <- as.character(configured)
  if (is.null(names(configured)) || any(!nzchar(names(configured)))) {
    if (length(configured) != length(factor_levels)) {
      stop("An unnamed factor color vector must have one color per factor level for ", factor_code, ".", call. = FALSE)
    }
    names(configured) <- factor_levels
  }
  missing_colors <- setdiff(factor_levels, names(configured))
  if (length(missing_colors) > 0L) {
    stop("Missing configured colors for factor ", factor_code, ": ", paste(missing_colors, collapse = ", "), call. = FALSE)
  }
  configured[factor_levels]
}

make_main_effect_plot <- function(data, factor_code, outcome_label, effect_row, pairwise_frame, config, factor_spec) {
  summary_data <- data |>
    dplyr::group_by(.data[[factor_code]]) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      .groups = "drop"
    )

  error_amount <- if (tolower(config$plots$error_bar) == "se") summary_data$SD / sqrt(summary_data$N) else summary_data$SD
  summary_data$Error <- error_amount

  factor_colors <- get_factor_colors(factor_code, data, config)

  total_pairwise <- if (is.null(pairwise_frame)) 0L else nrow(pairwise_frame)
  significant_pairwise <- if (
    total_pairwise == 0L || !"p.value" %in% names(pairwise_frame)
  ) {
    0L
  } else {
    sum(
      suppressWarnings(as.numeric(pairwise_frame$p.value)) < config$analysis$alpha,
      na.rm = TRUE
    )
  }
  pairwise_caption <- if (total_pairwise == 0L) {
    "Pairwise comparisons were unavailable; see 24_Warnings_Errors."
  } else {
    paste0(
      "Significant pairwise comparisons after ", config$analysis$p_adjust,
      " adjustment: ", significant_pairwise, "/", total_pairwise, "."
    )
  }

  plot_object <- ggplot2::ggplot(
    summary_data,
    ggplot2::aes(x = .data[[factor_code]], y = .data$Mean, fill = .data[[factor_code]], color = .data[[factor_code]])
  ) +
    ggplot2::geom_col(
      width = 0.64,
      alpha = config$plots$main_alpha %||% 0.65,
      linewidth = 0.35,
      show.legend = FALSE
    ) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$Mean - .data$Error, ymax = .data$Mean + .data$Error),
      width = 0.14,
      linewidth = 0.55,
      color = "black",
      show.legend = FALSE
    ) +
    ggplot2::geom_point(size = 2.4, show.legend = FALSE) +
    ggplot2::scale_fill_manual(values = factor_colors, drop = FALSE) +
    ggplot2::scale_color_manual(values = factor_colors, drop = FALSE) +
    ggplot2::labs(
      title = wrap_plot_title(factor_label(factor_code, factor_spec), config),
      subtitle = make_stat_annotation(effect_row),
      x = factor_label(factor_code, factor_spec),
      y = paste0(outcome_label, " (Mean ± ", toupper(config$plots$error_bar %||% "SD"), ")"),
      caption = stringr::str_wrap(
        pairwise_caption,
        width = config$plots$caption_wrap_width %||% 58L
      )
    ) +
    ggplot2::theme_bw(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      plot.subtitle = ggplot2::element_text(size = config$plots$stat_font_size %||% 9.5),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8.2, lineheight = 1.05),
      plot.margin = ggplot2::margin(12, 14, 12, 14, unit = "pt"),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "none"
    )

  x_levels <- levels(data[[factor_code]])
  annotation_y_values <- c(
    data$Y,
    summary_data$Mean - summary_data$Error,
    summary_data$Mean + summary_data$Error
  )
  add_significance_brackets(
    plot_object,
    pairwise_frame,
    x_levels,
    annotation_y_values,
    config$analysis$alpha
  )
}

choose_two_way_mapping <- function(effect_codes, data) {
  first <- effect_codes[[1]]
  second <- effect_codes[[2]]
  first_levels <- nlevels(data[[first]])
  second_levels <- nlevels(data[[second]])
  if (first_levels <= second_levels) {
    list(x = first, legend = second)
  } else {
    list(x = second, legend = first)
  }
}

make_two_way_plot <- function(data, effect_code, outcome_label, effect_row, contrast_frame, config, factor_spec) {
  codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
  mapping <- choose_two_way_mapping(codes, data)
  x_code <- mapping$x
  legend_code <- mapping$legend

  summary_data <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(x_code, legend_code)))) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      .groups = "drop"
    )
  summary_data$Error <- if (tolower(config$plots$error_bar) == "se") summary_data$SD / sqrt(summary_data$N) else summary_data$SD

  significant_contrasts <- if (is.null(contrast_frame) || nrow(contrast_frame) == 0L || !"p.value" %in% names(contrast_frame)) {
    0L
  } else {
    sum(contrast_frame$p.value < config$analysis$alpha, na.rm = TRUE)
  }
  total_contrasts <- if (is.null(contrast_frame)) 0L else nrow(contrast_frame)
  caption <- if (total_contrasts == 0L) {
    "Interaction contrasts were unavailable; see 24_Warnings_Errors."
  } else {
    stringr::str_wrap(
      paste0(
        "Significant interaction contrasts after ", config$analysis$p_adjust,
        " adjustment: ", significant_contrasts, "/", total_contrasts, "."
      ),
      width = config$plots$caption_wrap_width %||% 58L
    )
  }
  legend_colors <- get_factor_colors(legend_code, data, config)

  ggplot2::ggplot(
    summary_data,
    ggplot2::aes(
      x = .data[[x_code]],
      y = .data$Mean,
      color = .data[[legend_code]],
      shape = .data[[legend_code]],
      group = .data[[legend_code]]
    )
  ) +
    ggplot2::geom_line(linewidth = 0.85, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_point(size = 2.8, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$Mean - .data$Error, ymax = .data$Mean + .data$Error),
      width = 0.10,
      linewidth = 0.50,
      alpha = config$plots$interaction_alpha %||% 1
    ) +
    ggplot2::scale_color_manual(values = legend_colors, drop = FALSE) +
    ggplot2::labs(
      title = wrap_plot_title(effect_label(effect_code, factor_spec, short = TRUE), config),
      subtitle = make_stat_annotation(effect_row),
      x = factor_label(x_code, factor_spec),
      y = paste0(outcome_label, " (Mean ± ", toupper(config$plots$error_bar %||% "SD"), ")"),
      color = factor_label(legend_code, factor_spec),
      shape = factor_label(legend_code, factor_spec),
      caption = caption
    ) +
    ggplot2::guides(
      color = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      ),
      shape = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      )
    ) +
    ggplot2::theme_bw(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      plot.subtitle = ggplot2::element_text(size = config$plots$stat_font_size %||% 9.5),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8.2, lineheight = 1.05),
      plot.margin = ggplot2::margin(14, 10, 12, 10, unit = "pt"),
      legend.position = "top",
      legend.direction = "horizontal",
      legend.box = "vertical",
      legend.title = ggplot2::element_text(hjust = 0.5, margin = ggplot2::margin(b = 2, unit = "pt")),
      panel.grid.minor = ggplot2::element_blank()
    )
}

make_three_way_plot <- function(data, effect_code, outcome_label, effect_row, contrast_frame, config, factor_spec) {
  codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
  mapping <- config$plots$three_way_mapping
  x_code <- mapping$x %||% codes[[1]]
  color_code <- mapping$color %||% codes[[2]]
  facet_code <- mapping$facet %||% codes[[3]]
  if (!all(c(x_code, color_code, facet_code) %in% codes)) {
    stop("plots$three_way_mapping must use the enabled three-way factor codes.", call. = FALSE)
  }

  summary_data <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(x_code, color_code, facet_code)))) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      .groups = "drop"
    )
  summary_data$Error <- if (tolower(config$plots$error_bar) == "se") summary_data$SD / sqrt(summary_data$N) else summary_data$SD

  significant_contrasts <- if (is.null(contrast_frame) || nrow(contrast_frame) == 0L || !"p.value" %in% names(contrast_frame)) {
    0L
  } else {
    sum(contrast_frame$p.value < config$analysis$alpha, na.rm = TRUE)
  }
  total_contrasts <- if (is.null(contrast_frame)) 0L else nrow(contrast_frame)
  caption <- if (total_contrasts == 0L) {
    "Three-way interaction contrasts were unavailable; see 24_Warnings_Errors."
  } else {
    stringr::str_wrap(
      paste0(
        "Significant three-way interaction contrasts after ", config$analysis$p_adjust,
        " adjustment: ", significant_contrasts, "/", total_contrasts, "."
      ),
      width = config$plots$caption_wrap_width %||% 58L
    )
  }
  color_values <- get_factor_colors(color_code, data, config)

  ggplot2::ggplot(
    summary_data,
    ggplot2::aes(
      x = .data[[x_code]],
      y = .data$Mean,
      color = .data[[color_code]],
      shape = .data[[color_code]],
      group = .data[[color_code]]
    )
  ) +
    ggplot2::geom_line(linewidth = 0.85, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_point(size = 2.7, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$Mean - .data$Error, ymax = .data$Mean + .data$Error),
      width = 0.10,
      linewidth = 0.50,
      alpha = config$plots$interaction_alpha %||% 1
    ) +

    ggplot2::facet_wrap(ggplot2::vars(!!rlang::sym(facet_code)), nrow = config$plots$three_way_facet_rows %||% 2L) +
    ggplot2::scale_color_manual(values = color_values, drop = FALSE) +
    ggplot2::labs(
      title = wrap_plot_title(effect_label(effect_code, factor_spec, short = TRUE), config),
      subtitle = make_stat_annotation(effect_row),
      x = factor_label(x_code, factor_spec),
      y = paste0(outcome_label, " (Mean ± ", toupper(config$plots$error_bar %||% "SD"), ")"),
      color = factor_label(color_code, factor_spec),
      shape = factor_label(color_code, factor_spec),
      caption = caption
    ) +
    ggplot2::guides(
      color = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      ),
      shape = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      )
    ) +
    ggplot2::theme_bw(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      plot.subtitle = ggplot2::element_text(size = config$plots$stat_font_size %||% 9.5),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8.2, lineheight = 1.05),
      plot.margin = ggplot2::margin(14, 10, 12, 10, unit = "pt"),
      legend.position = "top",
      legend.direction = "horizontal",
      legend.box = "vertical",
      legend.title = ggplot2::element_text(hjust = 0.5, margin = ggplot2::margin(b = 2, unit = "pt")),
      panel.grid.minor = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold")
    )
}

column_description <- function(column_name, factor_codes = character(0)) {
  descriptions <- c(
    Item = "Run-information item.",
    Value = "Value or description associated with the run-information item.",
    DV = "Dependent-variable display name.",
    Category = "User-defined dependent-variable category used for organization only.",
    Source_Column = "Original column name in the input data.",
    Enabled = "Whether the dependent variable was enabled for analysis.",
    Factor_Code = "Internal syntactic factor code used in statistical formulas.",
    Factor_Label = "Full factor label used in tables and axis labels.",
    Factor_Short_Label = "Short factor label used in compact interaction-plot titles.",
    Level_Order = "Configured order of factor levels.",
    Level = "Factor level stored in the input data.",
    N = "Number of non-missing observations.",
    N_Total = "Total number of rows in the prepared analysis data.",
    N_Valid = "Number of valid observations included in the outcome analysis.",
    N_Missing = "Number of missing outcome observations.",
    Missing_Percent = "Percentage of missing outcome observations.",
    Empty_Cell = "TRUE when a configured factorial design cell has zero observations.",
    Mean = "Arithmetic mean.",
    SD = "Sample standard deviation.",
    SE = "Standard error of the estimate or mean, as applicable.",
    std.error = "Standard error of the estimated contrast.",
    Median = "Sample median.",
    IQR = "Interquartile range.",
    Min = "Minimum observed value.",
    Max = "Maximum observed value.",
    Effect_Code = "Internal effect code; colon-separated codes indicate interactions.",
    Effect_Label = "Human-readable effect label.",
    Model_Method = "Statistical method selected for the dependent variable.",
    Formula = "Model formula fitted for the dependent variable.",
    Residual_df = "Residual degrees of freedom for the fitted model.",
    R_squared = "Coefficient of determination for the ordinary linear model.",
    Adjusted_R_squared = "R-squared adjusted for the number of model parameters.",
    ART_Max_Absolute_Aligned_Sum = "Maximum absolute column sum of ART aligned responses; values should be close to zero.",
    ART_Diagnostic_File = "Relative path to the saved ART diagnostic text file, when enabled.",
    df1 = "Numerator degrees of freedom.",
    df2 = "Denominator degrees of freedom.",
    df = "Degrees of freedom for a post-hoc contrast.",
    Sum_Squares = "Effect sum of squares; unavailable for some ART outputs.",
    Mean_Square = "Effect mean square.",
    F_value = "F statistic.",
    p_value = "Unadjusted omnibus p value.",
    p.value = "P value reported by the post-hoc contrast procedure.",
    Minimum_Omnibus_p = "Smallest omnibus p value for the dependent variable.",
    Partial_Eta2 = "Partial eta-squared effect-size estimate.",
    Cohens_f = "Cohen's f derived from partial eta-squared.",
    Effect_Size_Magnitude = "Qualitative effect-size magnitude.",
    Effect_Size_Scale = "Response scale on which the reported effect size is based.",
    Significance = "Significance label: ***, **, *, ., or n.s.",
    Significant = "TRUE when the corresponding p value is below alpha.",
    Residual_Shapiro_W = "Shapiro-Wilk W statistic for residual normality.",
    Shapiro_p = "P value from the Shapiro-Wilk residual-normality test.",
    Shapiro_Decision = "Decision from the residual-normality test at the configured alpha level.",
    Levene_F = "F statistic from the Levene variance-homogeneity test.",
    Levene_df1 = "Numerator degrees of freedom for the Levene test.",
    Levene_df2 = "Denominator degrees of freedom for the Levene test.",
    Levene_p = "P value from the Levene homogeneity-of-variance test.",
    Levene_Decision = "Decision from the variance-homogeneity test at the configured alpha level.",
    Selected_Method = "ANOVA or ART-ANOVA selected according to the configuration and assumption checks.",
    Selection_Reason = "Reason the reported analysis method was selected.",
    W = "Shapiro-Wilk W statistic for a factorial design cell.",
    Decision = "Decision associated with the diagnostic test.",
    Note = "Additional diagnostic or output note.",
    Contrast_Type = "Type of post-hoc comparison or interaction contrast.",
    contrast = "Contrast label generated by emmeans or ARTool.",
    Group1 = "First configured factor level in a main-effect pairwise comparison.",
    Group2 = "Second configured factor level in a main-effect pairwise comparison.",
    Group_Parse_Method = "Method used to map the contrast label to configured factor levels for plot annotation.",
    Annotation_Eligible = "TRUE when the comparison can be mapped to the plot x-axis and annotated if significant.",
    estimate = "Estimated contrast on the scale stated in Estimate_Scale.",
    lower.CL = "Lower confidence limit for the estimated contrast.",
    upper.CL = "Upper confidence limit for the estimated contrast.",
    asymp.LCL = "Lower asymptotic confidence limit for the estimated contrast.",
    asymp.UCL = "Upper asymptotic confidence limit for the estimated contrast.",
    t.ratio = "T statistic for a post-hoc contrast.",
    z.ratio = "Z statistic for a post-hoc contrast.",
    null = "Null-hypothesis contrast value, usually zero.",
    P_Adjustment = "Multiple-comparison adjustment method.",
    Estimate_Scale = "Scale on which the contrast estimate is expressed.",
    Plot_Type = "Type of plots shown on the indexed PDF page.",
    PDF_File = "Name of the generated figures PDF.",
    PDF_Page = "Page number in the generated figures PDF.",
    Stage = "Analysis stage that produced the warning or error.",
    Type = "Warning or error classification.",
    Message = "Captured warning or error message.",
    N_Significant_Main_Effects = "Number of significant omnibus main effects for the dependent variable.",
    N_Significant_Interactions = "Number of significant omnibus interaction effects for the dependent variable.",
    Non_Numeric_Values_Converted_to_NA = "Count of non-missing source values that could not be converted to numeric values.",
    Non_Finite_Numeric_Values = "Count of numeric values equal to Inf, -Inf, or NaN.",
    Correlation_Enabled = "TRUE when the dependent variable is included in correlation analysis.",
    Variable_1 = "First dependent variable in the correlation pair.",
    Category_1 = "Category of the first dependent variable in the correlation pair.",
    Variable_2 = "Second dependent variable in the correlation pair.",
    Category_2 = "Category of the second dependent variable in the correlation pair.",
    N_Complete = "Number of rows with finite values for both variables in the correlation pair.",
    Variable_1_Unique = "Number of unique finite values for the first variable across all available finite observations.",
    Variable_2_Unique = "Number of unique finite values for the second variable across all available finite observations.",
    Variable_1_Shapiro_W = "Shapiro-Wilk W statistic for the first variable across all available finite observations.",
    Variable_1_Shapiro_p = "Shapiro-Wilk p value for the first variable across all available finite observations.",
    Variable_2_Shapiro_W = "Shapiro-Wilk W statistic for the second variable across all available finite observations.",
    Variable_2_Shapiro_p = "Shapiro-Wilk p value for the second variable across all available finite observations.",
    Normality_Alpha = "Alpha threshold used for Pearson-versus-Spearman automatic method selection.",
    Method = "Uniform correlation method selected for the complete analysis: Pearson or Spearman.",
    Method_Selection_Reason = "Reason one common Pearson or Spearman method was selected for all tested variable pairs.",
    Coefficient = "Pearson r or Spearman rho correlation coefficient.",
    Statistic_Name = "Name of the test statistic returned by cor.test().",
    Statistic = "Correlation-test statistic returned by cor.test().",
    Parameter = "Test degrees of freedom when supplied by cor.test(); unavailable for some methods.",
    p_adjusted = "Correlation p value after the configured multiplicity adjustment.",
    Variable = "Dependent variable included in the correlation analysis or row variable in a correlation matrix.",
    N_Finite = "Number of finite observations available for the variable-level correlation-method diagnostic.",
    N_Unique = "Number of unique finite values available for the variable-level correlation-method diagnostic.",
    Pearson_Eligible = "TRUE when the variable satisfies all configured requirements for global Pearson selection.",
    Eligibility_Reason = "Variable-level reason for passing or failing the Pearson eligibility rule.",
    Correlation_Method = "Single Pearson or Spearman method selected for the complete correlation analysis.",
    Correlation_Method_Selection_Reason = "Reason the same Pearson or Spearman method was selected for every tested variable pair."
  )

  if (column_name %in% names(descriptions)) return(descriptions[[column_name]])
  if (column_name %in% factor_codes) {
    return(paste0("Observed level of configured factor ", column_name, "."))
  }
  if (grepl("_pairwise$", column_name)) {
    factor_code <- sub("_pairwise$", "", column_name)
    return(paste0("Pairwise level contrast for configured factor ", factor_code, "."))
  }
  "Output field generated by the analysis procedure."
}

sheet_purpose <- function(sheet_name) {
  purposes <- c(
    `00_Run_Info` = "Input, configuration, software, and output-path information.",
    `01_Analysis_Summary` = "One-row summary of method selection and significant effects for each dependent variable.",
    `02_Outcome_Spec` = "Enabled dependent variables analyzed by the script, with source columns and categories.",
    `03_Factor_Spec` = "Factor codes, source columns, labels, and configured levels.",
    `04_Design_Cell_Counts` = "Observation counts for every configured factorial design cell, including empty cells.",
    `06_Missing_Summary` = "Missing-data counts for each dependent variable.",
    `07_Assumption_Tests` = "Residual normality, variance-homogeneity tests, and selected analysis method.",
    `08_Cell_Shapiro` = "Optional Shapiro-Wilk diagnostics within factorial design cells.",
    `09_Model_Summary` = "Model-level summary information and ART diagnostics.",
    `13_Omnibus_Effects` = "Omnibus main-effect and interaction tests with effect sizes.",
    `14_Significant_Effects` = "Subset of omnibus effects with p below alpha, retaining the configured outcome and effect order.",
    `10_Overall_Desc` = "Overall descriptive statistics for each dependent variable.",
    `11_Main_Desc` = "Descriptive statistics grouped by each main-effect factor.",
    `12_Interaction_Desc` = "Descriptive statistics grouped by each interaction combination.",
    `15_Main_Posthoc` = "Pairwise comparisons for all enabled main effects.",
    `16_Interaction_Cells` = "Pairwise comparisons among interaction-cell combinations.",
    `17_Interaction_Contrasts` = "Difference-of-differences and higher-order interaction contrasts.",
    `23_Plot_Index` = "Index of figure types and page numbers in the PDF.",
    `24_Warnings_Errors` = "Warnings and errors captured during analysis.",
    `05_Conversion_Report` = "Numeric-conversion checks for dependent-variable columns.",
    `19_Correlation_Results` = "Correlation tests using one automatically selected common Pearson or Spearman method, with normality diagnostics and adjusted p values.",
    `20_Correlation_Coeff` = "Symmetric matrix of coefficients calculated using the single method selected for the complete correlation analysis.",
    `22_Correlation_Methods` = "Symmetric matrix confirming the single Pearson or Spearman method used throughout the correlation analysis.",
    `21_Correlation_Adj_p` = "Symmetric matrix of multiplicity-adjusted correlation p values.",
    `18_Correlation_Normality` = "Variable-level normality diagnostics and the global Pearson-versus-Spearman method decision."
  )
  purposes[[sheet_name]] %||% "Analysis output table."
}

output_column_template <- function(sheet_name, factor_codes) {
  factor_pairwise_columns <- paste0(factor_codes, "_pairwise")
  contrast_statistics <- c(
    "contrast", "Group1", "Group2", "Group_Parse_Method", "Annotation_Eligible",
    "estimate", "SE", "std.error", "df", "lower.CL", "upper.CL",
    "asymp.LCL", "asymp.UCL", "t.ratio", "z.ratio", "null", "p.value",
    "P_Adjustment", "Estimate_Scale", "Significance", "Significant"
  )

  templates <- list(
    `00_Run_Info` = c("Item", "Value"),
    `01_Analysis_Summary` = c(
      "DV", "Category", "N_Valid", "Shapiro_p", "Levene_p",
      "Selected_Method", "Selection_Reason", "N_Significant_Main_Effects",
      "N_Significant_Interactions", "Minimum_Omnibus_p"
    ),
    `02_Outcome_Spec` = c(
      "DV", "Category", "Source_Column", "Enabled", "Correlation_Enabled"
    ),
    `03_Factor_Spec` = c(
      "Factor_Code", "Factor_Label", "Factor_Short_Label", "Source_Column",
      "Level_Order", "Level"
    ),
    `04_Design_Cell_Counts` = c(factor_codes, "N", "Empty_Cell"),
    `06_Missing_Summary` = c(
      "DV", "Category", "N_Total", "N_Valid", "N_Missing", "Missing_Percent"
    ),
    `07_Assumption_Tests` = c(
      "DV", "Category", "N_Valid", "Residual_Shapiro_W", "Shapiro_p",
      "Shapiro_Decision", "Levene_F", "Levene_df1", "Levene_df2",
      "Levene_p", "Levene_Decision", "Selected_Method", "Selection_Reason"
    ),
    `08_Cell_Shapiro` = c(
      "DV", "Category", factor_codes, "N", "W", "p_value", "Decision", "Note"
    ),
    `09_Model_Summary` = c(
      "DV", "Category", "Model_Method", "Formula", "N", "Residual_df",
      "R_squared", "Adjusted_R_squared", "ART_Max_Absolute_Aligned_Sum",
      "ART_Diagnostic_File"
    ),
    `13_Omnibus_Effects` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "df1", "df2", "Sum_Squares", "Mean_Square", "F_value", "p_value",
      "Partial_Eta2", "Cohens_f", "Effect_Size_Magnitude", "Effect_Size_Scale",
      "Significance", "Significant"
    ),
    `14_Significant_Effects` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "df1", "df2", "Sum_Squares", "Mean_Square", "F_value", "p_value",
      "Partial_Eta2", "Cohens_f", "Effect_Size_Magnitude", "Effect_Size_Scale",
      "Significance", "Significant"
    ),
    `10_Overall_Desc` = c(
      "DV", "Category", "N", "Mean", "SD", "SE", "Median", "IQR", "Min", "Max"
    ),
    `11_Main_Desc` = c(
      "DV", "Category", "Effect_Code", "Effect_Label", factor_codes,
      "N", "Mean", "SD", "SE", "Median", "IQR", "Min", "Max"
    ),
    `12_Interaction_Desc` = c(
      "DV", "Category", "Effect_Code", "Effect_Label", factor_codes,
      "N", "Mean", "SD", "SE", "Median", "IQR", "Min", "Max"
    ),
    `15_Main_Posthoc` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "Contrast_Type", factor_codes, factor_pairwise_columns, contrast_statistics
    ),
    `16_Interaction_Cells` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "Contrast_Type", factor_codes, factor_pairwise_columns, contrast_statistics
    ),
    `17_Interaction_Contrasts` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "Contrast_Type", factor_codes, factor_pairwise_columns, contrast_statistics
    ),
    `23_Plot_Index` = c("DV", "Category", "Plot_Type", "PDF_File", "PDF_Page"),
    `24_Warnings_Errors` = c("DV", "Category", "Stage", "Type", "Message"),
    `05_Conversion_Report` = c(
      "DV", "Category", "Source_Column",
      "Non_Numeric_Values_Converted_to_NA", "Non_Finite_Numeric_Values"
    ),
    `19_Correlation_Results` = c(
      "Variable_1", "Category_1", "Variable_2", "Category_2",
      "N_Complete", "Variable_1_Unique", "Variable_2_Unique",
      "Variable_1_Shapiro_W", "Variable_1_Shapiro_p",
      "Variable_2_Shapiro_W", "Variable_2_Shapiro_p",
      "Normality_Alpha", "Method", "Method_Selection_Reason",
      "Coefficient", "Statistic_Name", "Statistic", "Parameter",
      "p_value", "p_adjusted", "P_Adjustment", "Significance",
      "Significant", "Note"
    ),
    `20_Correlation_Coeff` = c("Variable"),
    `22_Correlation_Methods` = c("Variable"),
    `21_Correlation_Adj_p` = c("Variable"),
    `18_Correlation_Normality` = c(
      "Variable", "Category", "N_Finite", "N_Unique", "Shapiro_W",
      "Shapiro_p", "Normality_Alpha", "Shapiro_Decision",
      "Pearson_Eligible", "Eligibility_Reason", "Correlation_Method",
      "Correlation_Method_Selection_Reason", "Note"
    )
  )

  unique(templates[[sheet_name]] %||% c("DV", "Category", factor_codes, factor_pairwise_columns))
}

standardize_output_frame <- function(frame, sheet_name, factor_codes) {
  if (is.null(frame) || nrow(frame) == 0L) {
    return(data.frame(Note = "No results were generated for this table.", check.names = FALSE))
  }

  frame <- as.data.frame(frame, check.names = FALSE)
  column_names <- names(frame)
  blank_columns <- which(is.na(column_names) | !nzchar(trimws(column_names)))
  if (length(blank_columns) > 0L) {
    column_names[blank_columns] <- paste0("Unnamed_Column_", blank_columns)
  }
  names(frame) <- make.unique(column_names, sep = "_")

  requested_order <- output_column_template(sheet_name, factor_codes)
  requested_order <- requested_order[requested_order %in% names(frame)]
  remaining_columns <- setdiff(names(frame), requested_order)
  frame[c(requested_order, remaining_columns)]
}

write_results_workbook <- function(sheet_data, output_file, alpha, factor_codes) {
  workbook <- openxlsx::createWorkbook(creator = "Reusable factorial ANOVA / ART-ANOVA analysis")
  header_style <- openxlsx::createStyle(
    fontColour = "#FFFFFF", fgFill = "#1F4E78", textDecoration = "bold",
    halign = "center", valign = "center", border = "Bottom"
  )
  definition_title_style <- openxlsx::createStyle(
    fontColour = "#FFFFFF", fgFill = "#548235", textDecoration = "bold",
    halign = "left", valign = "center"
  )
  definition_purpose_style <- openxlsx::createStyle(
    fgFill = "#E2F0D9", fontColour = "#375623", textDecoration = "italic",
    wrapText = TRUE, valign = "top"
  )
  definition_header_style <- openxlsx::createStyle(
    fontColour = "#FFFFFF", fgFill = "#70AD47", textDecoration = "bold",
    halign = "center", valign = "center"
  )
  definition_body_style <- openxlsx::createStyle(
    wrapText = TRUE, valign = "top", border = "TopBottomLeftRight",
    borderColour = "#D9EAD3"
  )
  significant_style <- openxlsx::createStyle(fgFill = "#FFF2CC")
  p_style <- openxlsx::createStyle(numFmt = "0.000000")
  integer_style <- openxlsx::createStyle(numFmt = "0")
  number_style <- openxlsx::createStyle(numFmt = "0.000")

  integer_column_names <- c(
    "N", "N_Total", "N_Valid", "N_Missing", "Level_Order", "PDF_Page",
    "N_Significant_Main_Effects", "N_Significant_Interactions",
    "Non_Numeric_Values_Converted_to_NA", "Non_Finite_Numeric_Values",
    "N_Complete", "Variable_1_Unique", "Variable_2_Unique",
    "N_Finite", "N_Unique"
  )
  p_column_names <- c(
    "p_value", "p.value", "p_adjusted", "Shapiro_p", "Levene_p",
    "Minimum_Omnibus_p", "Variable_1_Shapiro_p", "Variable_2_Shapiro_p"
  )

  for (index in seq_along(sheet_data)) {
    sheet_name <- names(sheet_data)[[index]]
    frame <- standardize_output_frame(sheet_data[[index]], sheet_name, factor_codes)

    openxlsx::addWorksheet(workbook, sheet_name, gridLines = FALSE)
    openxlsx::writeDataTable(
      workbook, sheet = sheet_name, x = frame,
      tableStyle = "TableStyleMedium2",
      tableName = paste0("tbl_", sprintf("%02d", index))
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = header_style,
      rows = 1, cols = seq_len(ncol(frame)), gridExpand = TRUE, stack = TRUE
    )
    openxlsx::freezePane(workbook, sheet = sheet_name, firstRow = TRUE)

    widths <- vapply(seq_along(frame), function(column_index) {
      values <- c(names(frame)[[column_index]], as.character(frame[[column_index]]))
      values[is.na(values)] <- ""
      min(max(nchar(values, type = "width"), na.rm = TRUE) + 2, 38)
    }, numeric(1))
    openxlsx::setColWidths(
      workbook, sheet = sheet_name, cols = seq_len(ncol(frame)),
      widths = pmax(widths, 10)
    )

    p_columns <- which(names(frame) %in% p_column_names)
    if (identical(sheet_name, "21_Correlation_Adj_p")) {
      p_columns <- which(vapply(frame, is.numeric, logical(1)))
    }
    if (length(p_columns) > 0L && nrow(frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = p_style,
        rows = 2:(nrow(frame) + 1L), cols = p_columns,
        gridExpand = TRUE, stack = TRUE
      )
      for (p_column in p_columns) {
        numeric_p <- suppressWarnings(as.numeric(as.character(frame[[p_column]])))
        significant_rows <- which(!is.na(numeric_p) & numeric_p < alpha) + 1L
        if (length(significant_rows) > 0L) {
          openxlsx::addStyle(
            workbook, sheet = sheet_name, style = significant_style,
            rows = significant_rows, cols = p_column,
            gridExpand = TRUE, stack = TRUE
          )
        }
      }
    }

    integer_columns <- which(names(frame) %in% integer_column_names & vapply(frame, is.numeric, logical(1)))
    if (length(integer_columns) > 0L && nrow(frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = integer_style,
        rows = 2:(nrow(frame) + 1L), cols = integer_columns,
        gridExpand = TRUE, stack = TRUE
      )
    }

    numeric_columns <- setdiff(
      which(vapply(frame, is.numeric, logical(1))),
      union(p_columns, integer_columns)
    )
    if (length(numeric_columns) > 0L && nrow(frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = number_style,
        rows = 2:(nrow(frame) + 1L), cols = numeric_columns,
        gridExpand = TRUE, stack = TRUE
      )
    }

    definition_start_column <- ncol(frame) + 3L
    definition_frame <- data.frame(
      Column = names(frame),
      Description = vapply(
        names(frame), column_description, character(1), factor_codes = factor_codes
      ),
      stringsAsFactors = FALSE
    )

    openxlsx::mergeCells(
      workbook, sheet = sheet_name,
      cols = definition_start_column:(definition_start_column + 1L), rows = 1
    )
    openxlsx::writeData(
      workbook, sheet_name, "Column Definitions",
      startRow = 1, startCol = definition_start_column, colNames = FALSE
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = definition_title_style,
      rows = 1, cols = definition_start_column:(definition_start_column + 1L),
      gridExpand = TRUE, stack = TRUE
    )

    openxlsx::mergeCells(
      workbook, sheet = sheet_name,
      cols = definition_start_column:(definition_start_column + 1L), rows = 2
    )
    openxlsx::writeData(
      workbook, sheet_name, paste0("Sheet purpose: ", sheet_purpose(sheet_name)),
      startRow = 2, startCol = definition_start_column, colNames = FALSE
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = definition_purpose_style,
      rows = 2, cols = definition_start_column:(definition_start_column + 1L),
      gridExpand = TRUE, stack = TRUE
    )

    openxlsx::writeDataTable(
      workbook, sheet = sheet_name, x = definition_frame,
      startRow = 4, startCol = definition_start_column,
      tableStyle = "TableStyleMedium4",
      tableName = paste0("def_", sprintf("%02d", index))
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = definition_header_style,
      rows = 4, cols = definition_start_column:(definition_start_column + 1L),
      gridExpand = TRUE, stack = TRUE
    )
    if (nrow(definition_frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = definition_body_style,
        rows = 5:(nrow(definition_frame) + 4L),
        cols = definition_start_column:(definition_start_column + 1L),
        gridExpand = TRUE, stack = TRUE
      )
      openxlsx::setRowHeights(
        workbook, sheet = sheet_name,
        rows = 5:(nrow(definition_frame) + 4L), heights = 34
      )
    }
    openxlsx::setColWidths(workbook, sheet_name, cols = definition_start_column, widths = 26)
    openxlsx::setColWidths(workbook, sheet_name, cols = definition_start_column + 1L, widths = 58)
    openxlsx::setRowHeights(workbook, sheet_name, rows = 2, heights = 35)
  }

  openxlsx::saveWorkbook(workbook, output_file, overwrite = TRUE)
}

analyze_outcome <- function(analysis_data, outcome_row, factor_spec, config, output_paths) {
  outcome_column <- outcome_row$column[[1]]
  outcome_label <- outcome_row$label[[1]]
  category <- outcome_row$category[[1]]
  factor_codes <- factor_spec$code

  # Always analyze the complete factorial structure for all enabled factors.
  # For three factors this includes three main effects, three two-way
  # interactions, and the three-way interaction. Reporting decisions belong to
  # the analyst and are not implemented by suppressing model terms here.
  effect_codes <- generate_effect_codes(factor_codes, length(factor_codes))
  interaction_codes <- effect_codes[grepl(":", effect_codes, fixed = TRUE)]

  warnings_errors <- list()
  selected_data <- analysis_data |>
    dplyr::select(ID, dplyr::all_of(factor_codes), dplyr::all_of(outcome_column)) |>
    dplyr::rename(Y = dplyr::all_of(outcome_column))

  non_finite_n <- sum(!is.na(selected_data$Y) & !is.finite(selected_data$Y))
  if (non_finite_n > 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Warning",
      Message = paste0(non_finite_n, " non-finite outcome value(s) were excluded.")
    )
  }

  data <- selected_data |>
    dplyr::filter(is.na(.data$Y) | is.finite(.data$Y)) |>
    tidyr::drop_na(dplyr::all_of(c("Y", factor_codes))) |>
    droplevels()

  minimum_valid_n <- as.integer(config$analysis$minimum_valid_n %||% 10L)
  observed_level_counts <- vapply(data[factor_codes], nlevels, integer(1))
  configured_level_counts <- vapply(
    factor_codes,
    function(code) length(config$factor_levels[[code]]),
    integer(1)
  )
  missing_factor_levels <- factor_codes[observed_level_counts < configured_level_counts]
  if (length(missing_factor_levels) > 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Error",
      Message = paste0(
        "Outcome-specific missing-data removal eliminated one or more configured levels of factor(s): ",
        paste(missing_factor_levels, collapse = ", "),
        "."
      )
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  if (nrow(data) < minimum_valid_n || any(observed_level_counts < 2L)) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Error",
      Message = "Insufficient valid observations or fewer than two levels for an enabled factor."
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  if (length(unique(data$Y)) < 2L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Error",
      Message = "The dependent variable is constant after missing and non-finite values are removed."
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  # Type-III tests are not straightforwardly interpretable for models with
  # aliased coefficients. Detect empty factorial cells before model fitting.
  complete_cell_counts <- data |>
    dplyr::count(dplyr::across(dplyr::all_of(factor_codes)), name = "N", .drop = FALSE)
  empty_cells <- complete_cell_counts |>
    dplyr::filter(.data$N == 0L)
  if (nrow(empty_cells) > 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Design-cell validation", Type = "Error",
      Message = paste0(
        nrow(empty_cells),
        " empty factorial cell(s) remain after outcome-specific missing-data removal; ",
        "the full factorial model would be rank deficient."
      )
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  # Both analysis branches use the same complete factorial fixed-effects model.
  # Using the product operator expands to all main effects and interactions.
  formula_text <- paste("Y ~", paste(factor_codes, collapse = " * "))
  model_formula <- stats::as.formula(formula_text)
  art_formula_text <- formula_text
  art_model_formula <- model_formula
  lm_capture <- tryCatch(capture_warnings(stats::lm(model_formula, data = data)), error = function(e) e)
  if (inherits(lm_capture, "error")) {
    warnings_errors[[1]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Linear model", Type = "Error",
      Message = conditionMessage(lm_capture)
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }
  lm_model <- lm_capture$value
  if (length(lm_capture$warnings) > 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Linear model", Type = "Warning",
      Message = paste(lm_capture$warnings, collapse = " | ")
    )
  }

  if (lm_model$rank < length(stats::coef(lm_model)) || stats::df.residual(lm_model) <= 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Linear model", Type = "Error",
      Message = paste0(
        "The fitted factorial model is rank deficient or has no residual degrees of freedom ",
        "(rank ", lm_model$rank, " of ", length(stats::coef(lm_model)),
        "; residual df ", stats::df.residual(lm_model), ")."
      )
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  shapiro_result <- safe_shapiro(stats::residuals(lm_model))
  levene_result <- safe_levene(data, factor_codes, config$analysis$levene_center %||% "median")
  assumptions_met <- is.finite(shapiro_result$p) && is.finite(levene_result$p) &&
    shapiro_result$p >= config$analysis$alpha && levene_result$p >= config$analysis$alpha

  method_selection <- tolower(config$analysis$method_selection %||% "automatic")
  selected_method <- if (method_selection == "anova") {
    "ANOVA"
  } else if (method_selection == "art") {
    "ART-ANOVA"
  } else if (assumptions_met) {
    "ANOVA"
  } else {
    "ART-ANOVA"
  }

  selection_reason <- if (method_selection != "automatic") {
    paste0("Method forced by configuration: ", selected_method, ".")
  } else if (assumptions_met) {
    "Residual Shapiro-Wilk and Levene tests were both non-significant."
  } else {
    paste0(
      "At least one assumption test was significant or unavailable: ",
      format_p_for_plot(shapiro_result$p), " (Shapiro); ",
      format_p_for_plot(levene_result$p), " (Levene)."
    )
  }

  assumption_table <- tibble::tibble(
    DV = outcome_label,
    Category = category,
    N_Valid = nrow(data),
    Residual_Shapiro_W = shapiro_result$W,
    Shapiro_p = shapiro_result$p,
    Shapiro_Decision = ifelse(is.na(shapiro_result$p), "Unavailable", ifelse(shapiro_result$p >= config$analysis$alpha, "Normality not rejected", "Normality rejected")),
    Levene_F = levene_result$F,
    Levene_df1 = levene_result$df1,
    Levene_df2 = levene_result$df2,
    Levene_p = levene_result$p,
    Levene_Decision = ifelse(is.na(levene_result$p), "Unavailable", ifelse(levene_result$p >= config$analysis$alpha, "Homogeneity not rejected", "Homogeneity rejected")),
    Selected_Method = selected_method,
    Selection_Reason = selection_reason
  )

  cell_shapiro <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(factor_codes))) |>
    dplyr::group_modify(function(group_data, group_keys) {
      result <- safe_shapiro(group_data$Y)
      tibble::tibble(
        N = nrow(group_data), W = result$W, p_value = result$p,
        Decision = ifelse(is.na(result$p), "Unavailable", ifelse(result$p >= config$analysis$alpha, "Normality not rejected", "Normality rejected")),
        Note = result$note
      )
    }) |>
    dplyr::ungroup() |>
    dplyr::mutate(DV = outcome_label, Category = category, .before = 1)

  overall_descriptive <- tibble::tibble(
    DV = outcome_label, Category = category, N = nrow(data),
    Mean = mean(data$Y), SD = stats::sd(data$Y), SE = stats::sd(data$Y) / sqrt(nrow(data)),
    Median = stats::median(data$Y), IQR = stats::IQR(data$Y), Min = min(data$Y), Max = max(data$Y)
  )
  main_descriptive <- dplyr::bind_rows(lapply(factor_codes, function(code) {
    summarise_groups(data, code, outcome_label, category, code, factor_spec)
  }))
  interaction_descriptive <- dplyr::bind_rows(lapply(interaction_codes, function(effect_code) {
    summarise_groups(data, strsplit(effect_code, ":", fixed = TRUE)[[1]], outcome_label, category, effect_code, factor_spec)
  }))

  fitted_model <- NULL
  model_method_label <- NULL
  estimate_scale <- NULL
  omnibus_table <- NULL
  model_summary <- NULL
  art_model <- NULL

  if (selected_method == "ANOVA") {
    fitted_model <- lm_model
    model_method_label <- paste0("ANOVA (Type ", config$analysis$anova_type %||% 3L, ")")
    estimate_scale <- "raw outcome"
    omnibus_capture <- tryCatch(
      extract_anova_table(
        fitted_model, outcome_label, category, factor_spec,
        config$analysis$anova_type %||% 3L,
        config$analysis$alpha
      ),
      error = function(e) e
    )
    if (inherits(omnibus_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ANOVA omnibus table", Type = "Error",
        Message = conditionMessage(omnibus_capture)
      )
      return(list(
        assumptions = assumption_table, cell_shapiro = cell_shapiro,
        overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
        interaction_descriptive = interaction_descriptive,
        warnings_errors = dplyr::bind_rows(warnings_errors)
      ))
    }
    omnibus_table <- omnibus_capture
    model_summary <- tibble::tibble(
      DV = outcome_label, Category = category, Model_Method = model_method_label,
      Formula = formula_text, N = nrow(data), Residual_df = stats::df.residual(fitted_model),
      R_squared = summary(fitted_model)$r.squared,
      Adjusted_R_squared = summary(fitted_model)$adj.r.squared,
      ART_Max_Absolute_Aligned_Sum = NA_real_, ART_Diagnostic_File = NA_character_
    )
  } else {
    art_capture <- tryCatch(capture_warnings(ARTool::art(art_model_formula, data = data)), error = function(e) e)
    if (inherits(art_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ART model", Type = "Error",
        Message = conditionMessage(art_capture)
      )
      return(list(
        assumptions = assumption_table, cell_shapiro = cell_shapiro,
        overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
        interaction_descriptive = interaction_descriptive,
        warnings_errors = dplyr::bind_rows(warnings_errors)
      ))
    }
    art_model <- art_capture$value
    fitted_model <- art_model
    model_method_label <- "ART-ANOVA (Type III)"
    estimate_scale <- "aligned ranks"
    omnibus_capture <- tryCatch(
      extract_art_table(art_model, outcome_label, category, factor_spec, config$analysis$alpha) |>
        dplyr::filter(.data$Effect_Code %in% effect_codes),
      error = function(e) e
    )
    if (inherits(omnibus_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ART omnibus table", Type = "Error",
        Message = conditionMessage(omnibus_capture)
      )
      return(list(
        assumptions = assumption_table, cell_shapiro = cell_shapiro,
        overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
        interaction_descriptive = interaction_descriptive,
        warnings_errors = dplyr::bind_rows(warnings_errors)
      ))
    }
    omnibus_table <- omnibus_capture

    if (length(art_capture$warnings) > 0L) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ART model", Type = "Warning",
        Message = paste(art_capture$warnings, collapse = " | ")
      )
    }

    aligned_sums <- colSums(art_model$aligned, na.rm = TRUE)
    maximum_aligned_sum <- max(abs(aligned_sums), na.rm = TRUE)
    diagnostic_relative_path <- NA_character_
    if (isTRUE(config$output$save_art_diagnostics)) {
      diagnostic_file <- file.path(output_paths$art_diagnostics_dir, paste0(safe_path_component(outcome_label), "_ART_diagnostics.txt"))
      writeLines(
        c(
          paste0("Dependent variable: ", outcome_label),
          "",
          "Column sums of aligned responses:",
          capture.output(print(aligned_sums)),
          "",
          paste0("Maximum absolute aligned-column sum: ", format(maximum_aligned_sum, scientific = TRUE)),
          "",
          "summary(art_model):",
          capture.output(print(summary(art_model))),
          "",
          "ANOVA on aligned responses:",
          capture.output(print(stats::anova(art_model, response = "aligned")))
        ),
        diagnostic_file,
        useBytes = TRUE
      )
      diagnostic_relative_path <- fs::path_rel(diagnostic_file, start = output_paths$root)
    }
    model_summary <- tibble::tibble(
      DV = outcome_label, Category = category, Model_Method = model_method_label,
      Formula = art_formula_text, N = nrow(data), Residual_df = unique(omnibus_table$df2)[[1]],
      R_squared = NA_real_, Adjusted_R_squared = NA_real_,
      ART_Max_Absolute_Aligned_Sum = maximum_aligned_sum,
      ART_Diagnostic_File = diagnostic_relative_path
    )
  }

  main_posthoc <- list()
  interaction_cells <- list()
  interaction_contrasts <- list()
  main_posthoc_by_effect <- list()
  interaction_contrasts_by_effect <- list()

  for (factor_code in factor_codes) {
    result_capture <- tryCatch({
      if (selected_method == "ANOVA") {
        means <- emmeans::emmeans(fitted_model, specs = factor_code)
        capture_warnings(emmeans::contrast(means, method = "pairwise", adjust = config$analysis$p_adjust))
      } else {
        capture_warnings(ARTool::art.con(art_model, factor_code, adjust = config$analysis$p_adjust))
      }
    }, error = function(e) e)

    if (inherits(result_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = paste0("Main-effect post-hoc: ", factor_code),
        Type = "Error", Message = conditionMessage(result_capture)
      )
    } else {
      result_frame <- summary(result_capture$value, infer = c(TRUE, TRUE)) |>
        add_contrast_metadata(
          outcome_label, category, model_method_label, factor_code,
          "Main-effect pairwise comparison", estimate_scale,
          factor_spec, config$analysis$p_adjust, config$analysis$alpha
        ) |>
        parse_pairwise_groups(levels(data[[factor_code]]))
      result_frame$Annotation_Eligible <-
        result_frame$Group1 %in% levels(data[[factor_code]]) &
        result_frame$Group2 %in% levels(data[[factor_code]])
      main_posthoc[[length(main_posthoc) + 1L]] <- result_frame
      main_posthoc_by_effect[[factor_code]] <- result_frame

      unmatched_significant <- result_frame |>
        dplyr::filter(
          !is.na(.data$p.value), .data$p.value < config$analysis$alpha,
          !(.data$Group1 %in% levels(data[[factor_code]]) & .data$Group2 %in% levels(data[[factor_code]]))
        )
      if (nrow(unmatched_significant) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = paste0("Main-effect plot annotation: ", factor_code),
          Type = "Warning",
          Message = paste0(
            nrow(unmatched_significant),
            " significant pairwise comparison(s) could not be mapped to configured factor levels."
          )
        )
      }

      if (length(result_capture$warnings) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category, Stage = paste0("Main-effect post-hoc: ", factor_code),
          Type = "Warning", Message = paste(result_capture$warnings, collapse = " | ")
        )
      }
    }
  }

  for (effect_code in interaction_codes) {
    codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
    specifications <- stats::as.formula(paste("~", paste(codes, collapse = " * ")))

    cell_capture <- tryCatch({
      if (selected_method == "ANOVA") {
        means <- emmeans::emmeans(fitted_model, specs = specifications)
        capture_warnings(emmeans::contrast(means, method = "pairwise", adjust = config$analysis$p_adjust))
      } else {
        capture_warnings(ARTool::art.con(art_model, effect_code, adjust = config$analysis$p_adjust))
      }
    }, error = function(e) e)

    if (inherits(cell_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = paste0("Interaction-cell post-hoc: ", effect_code),
        Type = "Error", Message = conditionMessage(cell_capture)
      )
    } else {
      interaction_cells[[length(interaction_cells) + 1L]] <- summary(cell_capture$value, infer = c(TRUE, TRUE)) |>
        add_contrast_metadata(
          outcome_label, category, model_method_label, effect_code,
          "Factor-combination pairwise comparison", estimate_scale,
          factor_spec, config$analysis$p_adjust, config$analysis$alpha
        )
      if (length(cell_capture$warnings) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = paste0("Interaction-cell post-hoc: ", effect_code),
          Type = "Warning", Message = paste(cell_capture$warnings, collapse = " | ")
        )
      }
    }

    interaction_capture <- tryCatch({
      if (selected_method == "ANOVA") {
        means <- emmeans::emmeans(fitted_model, specs = specifications)
        capture_warnings(
          emmeans::contrast(
            means,
            interaction = rep("pairwise", length(codes)),
            adjust = config$analysis$p_adjust
          )
        )
      } else {
        capture_warnings(
          ARTool::art.con(
            art_model, effect_code,
            interaction = TRUE,
            adjust = config$analysis$p_adjust
          )
        )
      }
    }, error = function(e) e)

    if (inherits(interaction_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = paste0("Interaction contrast: ", effect_code),
        Type = "Error", Message = conditionMessage(interaction_capture)
      )
      interaction_contrasts_by_effect[[effect_code]] <- tibble::tibble()
    } else {
      contrast_frame <- summary(interaction_capture$value, infer = c(TRUE, TRUE)) |>
        add_contrast_metadata(
          outcome_label, category, model_method_label, effect_code,
          ifelse(length(codes) == 2L, "Difference-of-differences interaction contrast", "Higher-order interaction contrast"),
          estimate_scale, factor_spec, config$analysis$p_adjust, config$analysis$alpha
        )
      interaction_contrasts[[length(interaction_contrasts) + 1L]] <- contrast_frame
      interaction_contrasts_by_effect[[effect_code]] <- contrast_frame
      if (length(interaction_capture$warnings) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = paste0("Interaction contrast: ", effect_code),
          Type = "Warning", Message = paste(interaction_capture$warnings, collapse = " | ")
        )
      }
    }
  }

  main_plots <- lapply(factor_codes, function(code) {
    make_main_effect_plot(
      data, code, outcome_label, get_effect_row(omnibus_table, code),
      main_posthoc_by_effect[[code]] %||% tibble::tibble(),
      config, factor_spec
    )
  })
  names(main_plots) <- factor_codes

  interaction_plots <- lapply(interaction_codes, function(effect_code) {
    effect_order <- length(strsplit(effect_code, ":", fixed = TRUE)[[1]])
    if (effect_order == 2L) {
      make_two_way_plot(
        data, effect_code, outcome_label, get_effect_row(omnibus_table, effect_code),
        interaction_contrasts_by_effect[[effect_code]] %||% tibble::tibble(),
        config, factor_spec
      )
    } else {
      make_three_way_plot(
        data, effect_code, outcome_label, get_effect_row(omnibus_table, effect_code),
        interaction_contrasts_by_effect[[effect_code]] %||% tibble::tibble(),
        config, factor_spec
      )
    }
  })
  names(interaction_plots) <- interaction_codes

  list(
    assumptions = assumption_table,
    cell_shapiro = cell_shapiro,
    model_summary = model_summary,
    omnibus = omnibus_table,
    overall_descriptive = overall_descriptive,
    main_descriptive = main_descriptive,
    interaction_descriptive = interaction_descriptive,
    main_posthoc = dplyr::bind_rows(main_posthoc),
    interaction_cells = dplyr::bind_rows(interaction_cells),
    interaction_contrasts = dplyr::bind_rows(interaction_contrasts),
    warnings_errors = dplyr::bind_rows(warnings_errors),
    main_plots = main_plots,
    interaction_plots = interaction_plots,
    selected_method = selected_method,
    data = data
  )
}

create_figures_pdf <- function(
    results_by_outcome,
    outcome_spec,
    factor_spec,
    config,
    pdf_file,
    correlation_analysis = NULL) {
  if (!isTRUE(config$plots$create_pdf)) return(tibble::tibble())
  has_factorial_plots <- any(vapply(
    results_by_outcome,
    function(result) {
      !is.null(result) &&
        ((!is.null(result$main_plots) && length(result$main_plots) > 0L) ||
         (!is.null(result$interaction_plots) && length(result$interaction_plots) > 0L))
    },
    logical(1)
  ))
  has_correlation_plot <- !is.null(correlation_analysis) &&
    !is.null(correlation_analysis$heatmap)
  if (!has_factorial_plots && !has_correlation_plot) return(tibble::tibble())

  grDevices::pdf(
    pdf_file,
    width = config$plots$pdf_width %||% 16,
    height = config$plots$pdf_height %||% 9,
    onefile = TRUE,
    useDingbats = FALSE
  )
  on.exit(grDevices::dev.off(), add = TRUE)

  category_order <- config$plots$category_order %||% unique(outcome_spec$category)
  category_order <- c(category_order, setdiff(unique(outcome_spec$category), category_order))
  page_number <- 0L
  plot_index <- list()

  for (category in category_order) {
    # Use .env$category for the loop variable. Without .env, dplyr data
    # masking resolves both occurrences of category to the data-frame column,
    # making the condition category == category and selecting every outcome.
    category_outcomes <- outcome_spec |>
      dplyr::filter(.data$category == .env$category)
    if (nrow(category_outcomes) > 0L) {
      has_plots <- vapply(
        category_outcomes$label,
        function(label) {
          result <- results_by_outcome[[label]]
          !is.null(result) && !is.null(result$main_plots) && length(result$main_plots) > 0L
        },
        logical(1)
      )
      category_outcomes <- category_outcomes[has_plots, , drop = FALSE]
    }
    if (nrow(category_outcomes) == 0L) next

    category_page <- ggplot2::ggplot() +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.61,
        label = wrap_plot_title(category, config, page = TRUE),
        size = 12,
        fontface = "bold"
      ) +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.48,
        label = "Factorial ANOVA / ART-ANOVA results",
        size = 6
      ) +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.34,
        label = "Significance notation",
        size = 5,
        fontface = "bold"
      ) +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.19,
        label = category_page_significance_note(),
        size = 4.5,
        lineheight = 1.25,
        hjust = 0.5,
        vjust = 0.5
      ) +
      ggplot2::xlim(0, 1) +
      ggplot2::ylim(0, 1) +
      ggplot2::theme_void()
    print(category_page)
    page_number <- page_number + 1L

    for (outcome_index in seq_len(nrow(category_outcomes))) {
      outcome_label <- category_outcomes$label[[outcome_index]]
      result <- results_by_outcome[[outcome_label]]
      if (is.null(result) || is.null(result$main_plots)) next

      main_page <- patchwork::wrap_plots(
        result$main_plots,
        ncol = length(result$main_plots)
      ) +
        patchwork::plot_annotation(
          title = wrap_plot_title(category, config, page = TRUE),
          subtitle = wrap_plot_title(paste0(outcome_label, " — Main Effects (", result$selected_method, ")"), config, page = TRUE),
          theme = ggplot2::theme(
            plot.title = ggplot2::element_text(size = 18, face = "bold"),
            plot.subtitle = ggplot2::element_text(size = 14, face = "bold"),
            plot.margin = ggplot2::margin(18, 18, 18, 18)
          )
        )
      print(main_page)
      page_number <- page_number + 1L
      plot_index[[length(plot_index) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Plot_Type = "Main Effects",
        PDF_File = basename(pdf_file), PDF_Page = page_number
      )

      if (length(result$interaction_plots) > 0L) {
        interaction_page <- patchwork::wrap_plots(
          result$interaction_plots,
          ncol = min(config$plots$interaction_ncol %||% 4L, length(result$interaction_plots))
        ) +
          patchwork::plot_annotation(
            title = wrap_plot_title(category, config, page = TRUE),
            subtitle = wrap_plot_title(paste0(outcome_label, " — Interaction Effects (", result$selected_method, ")"), config, page = TRUE),
            theme = ggplot2::theme(
              plot.title = ggplot2::element_text(size = 18, face = "bold"),
              plot.subtitle = ggplot2::element_text(size = 14, face = "bold"),
              plot.margin = ggplot2::margin(18, 18, 18, 18)
            )
          )
        print(interaction_page)
        page_number <- page_number + 1L
        plot_index[[length(plot_index) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category, Plot_Type = "Interaction Effects",
          PDF_File = basename(pdf_file), PDF_Page = page_number
        )
      }
    }
  }

  if (has_correlation_plot) {
    print(correlation_analysis$heatmap)
    page_number <- page_number + 1L
    plot_index[[length(plot_index) + 1L]] <- tibble::tibble(
      DV = "All selected outcomes",
      Category = "Correlation Analysis",
      Plot_Type = "Correlation Heatmap",
      PDF_File = basename(pdf_file),
      PDF_Page = page_number
    )
  }

  dplyr::bind_rows(plot_index)
}

run_analysis <- function(config_file) {
  analysis_start_time <- Sys.time()
  config <- load_configuration(config_file)
  validate_configuration(config)
  install_and_load_packages(config)

  # Preserve the caller's session state. The analysis still uses a reproducible
  # random seed and sum-to-zero contrasts internally, but restores the previous
  # RNG state and options when run_analysis() exits.
  previous_options <- options(c("contrasts", "stringsAsFactors", "scipen"))
  on.exit(options(previous_options), add = TRUE)

  had_random_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  previous_random_seed <- if (had_random_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (had_random_seed) {
      assign(".Random.seed", previous_random_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)

  set.seed(config$analysis$random_seed %||% 20260731L)
  options(contrasts = c("contr.sum", "contr.poly"), stringsAsFactors = FALSE, scipen = 999)

  config_dir <- attr(config, "config_dir")
  input_file <- resolve_relative_path(config$input$file, config_dir)
  if (!file.exists(input_file)) stop("Input data file not found: ", input_file, call. = FALSE)

  input_stem <- safe_path_component(tools::file_path_sans_ext(basename(input_file)))
  output_root <- if (is.null(config$output$directory) || !nzchar(config$output$directory)) {
    file.path(dirname(input_file), paste0(input_stem, "_analysis_results"))
  } else {
    resolve_relative_path(config$output$directory, config_dir)
  }

  output_paths <- list(
    root = output_root,
    workbook = file.path(output_root, paste0(input_stem, "_statistical_results.xlsx")),
    figures = file.path(output_root, paste0(input_stem, "_figures.pdf")),
    logs_dir = file.path(output_root, "logs"),
    art_diagnostics_dir = file.path(output_root, "art_diagnostics")
  )
  fs::dir_create(output_paths$root)
  if (isTRUE(config$output$save_logs)) fs::dir_create(output_paths$logs_dir)
  if (isTRUE(config$output$save_art_diagnostics)) fs::dir_create(output_paths$art_diagnostics_dir)

  initial_sink_count <- sink.number(type = "output")
  sink_started <- FALSE
  sink_closed <- FALSE
  if (isTRUE(config$output$save_logs)) {
    console_log <- file.path(output_paths$logs_dir, "run_console_output.txt")
    sink(console_log, split = TRUE)
    sink_started <- TRUE
  }
  close_script_sink <- function() {
    if (isTRUE(sink_closed)) return(invisible(NULL))
    if (isTRUE(sink_started)) {
      while (sink.number(type = "output") > initial_sink_count) {
        before_level <- sink.number(type = "output")
        try(sink(type = "output"), silent = TRUE)
        if (sink.number(type = "output") >= before_level) break
      }
    }
    sink_closed <<- TRUE
    invisible(NULL)
  }
  on.exit(close_script_sink(), add = TRUE)

  cat("Analysis started:", format(analysis_start_time), "\n")
  cat("Configuration file:", attr(config, "config_path"), "\n")
  cat("Input file:", input_file, "\n")
  cat("Output directory:", output_root, "\n\n")

  raw_data <- tibble::as_tibble(read_input_file(input_file, config$input$sheet))
  prepared <- prepare_input_data(raw_data, config)
  analysis_data <- prepared$data
  factor_spec <- prepared$factor_spec
  outcome_spec <- prepared$outcome_spec
  factor_codes <- factor_spec$code
  global_warnings_errors <- list()

  missing_id_count <- sum(is.na(analysis_data$ID) | !nzchar(trimws(as.character(analysis_data$ID))))
  if (missing_id_count > 0L) {
    stop(
      "The ID column contains ", missing_id_count,
      " missing or empty value(s). Every row must have an ID.",
      call. = FALSE
    )
  }

  duplicate_id_count <- sum(duplicated(analysis_data$ID))
  if (duplicate_id_count > 0L) {
    warning("The ID column contains duplicate values. Confirm that rows are independent between-subject observations.")
    global_warnings_errors[[length(global_warnings_errors) + 1L]] <- tibble::tibble(
      DV = NA_character_, Category = NA_character_, Stage = "Input validation", Type = "Warning",
      Message = paste0(
        duplicate_id_count,
        " duplicated ID occurrence(s) were found after input preparation."
      )
    )
  }

  conversion_problem_rows <- prepared$conversion_report |>
    dplyr::filter(
      .data$Non_Numeric_Values_Converted_to_NA > 0L |
        .data$Non_Finite_Numeric_Values > 0L
    )
  if (nrow(conversion_problem_rows) > 0L) {
    global_warnings_errors[[length(global_warnings_errors) + 1L]] <- conversion_problem_rows |>
      dplyr::transmute(
        DV = .data$DV,
        Category = .data$Category,
        Stage = "Numeric conversion",
        Type = "Warning",
        Message = paste0(
          .data$Non_Numeric_Values_Converted_to_NA,
          " non-numeric value(s) converted to NA; ",
          .data$Non_Finite_Numeric_Values,
          " non-finite numeric value(s) detected."
        )
      )
  }

  design_cell_counts <- analysis_data |>
    dplyr::count(dplyr::across(dplyr::all_of(factor_codes)), name = "N", .drop = FALSE) |>
    dplyr::mutate(Empty_Cell = .data$N == 0L)
  missing_summary <- dplyr::bind_rows(lapply(seq_len(nrow(outcome_spec)), function(index) {
    source_column <- outcome_spec$column[[index]]
    tibble::tibble(
      DV = outcome_spec$label[[index]],
      Category = outcome_spec$category[[index]],
      N_Total = nrow(analysis_data),
      N_Valid = sum(!is.na(analysis_data[[source_column]])),
      N_Missing = sum(is.na(analysis_data[[source_column]])),
      Missing_Percent = 100 * sum(is.na(analysis_data[[source_column]])) / nrow(analysis_data)
    )
  }))

  factor_level_table <- dplyr::bind_rows(lapply(seq_len(nrow(factor_spec)), function(index) {
    code <- factor_spec$code[[index]]
    tibble::tibble(
      Factor_Code = code,
      Factor_Label = factor_spec$label[[index]],
      Factor_Short_Label = factor_spec$short_label[[index]],
      Source_Column = factor_spec$column[[index]],
      Level_Order = seq_along(config$factor_levels[[code]]),
      Level = config$factor_levels[[code]]
    )
  }))

  results_by_outcome <- list()
  for (index in seq_len(nrow(outcome_spec))) {
    outcome_label <- outcome_spec$label[[index]]
    cat(strrep("=", 80), "\n", sep = "")
    cat("Analyzing:", outcome_label, "\n")
    results_by_outcome[[outcome_label]] <- analyze_outcome(
      analysis_data,
      outcome_spec[index, , drop = FALSE],
      factor_spec,
      config,
      output_paths
    )
  }

  bind_result <- function(name) {
    frames <- lapply(results_by_outcome, function(result) result[[name]])
    frames <- frames[!vapply(frames, is.null, logical(1))]
    if (length(frames) == 0L) tibble::tibble() else dplyr::bind_rows(frames)
  }

  assumptions <- bind_result("assumptions")
  cell_shapiro <- bind_result("cell_shapiro")
  model_summary <- bind_result("model_summary")
  omnibus <- bind_result("omnibus")
  overall_descriptive <- bind_result("overall_descriptive")
  main_descriptive <- bind_result("main_descriptive")
  interaction_descriptive <- bind_result("interaction_descriptive")
  main_posthoc <- bind_result("main_posthoc")
  interaction_cells <- bind_result("interaction_cells")
  interaction_contrasts <- bind_result("interaction_contrasts")
  correlation_analysis <- analyze_correlations(analysis_data, outcome_spec, config)
  warnings_errors <- dplyr::bind_rows(
    dplyr::bind_rows(global_warnings_errors),
    bind_result("warnings_errors"),
    correlation_analysis$warnings_errors
  )

  significant_effects <- if (nrow(omnibus) > 0L) {
    # Filtering preserves the configured dependent-variable and factorial-effect
    # order already present in the omnibus table. Do not re-sort categories
    # alphabetically or effects by p value.
    omnibus |>
      dplyr::filter(.data$p_value < config$analysis$alpha)
  } else tibble::tibble()

  plot_index <- create_figures_pdf(
    results_by_outcome,
    outcome_spec,
    factor_spec,
    config,
    output_paths$figures,
    correlation_analysis = correlation_analysis
  )

  analysis_summary <- if (nrow(assumptions) > 0L) {
    assumptions |>
      dplyr::select(
        DV, Category, N_Valid, Shapiro_p, Levene_p,
        Selected_Method, Selection_Reason
      ) |>
      dplyr::left_join(
        omnibus |>
          dplyr::group_by(.data$DV) |>
          dplyr::summarise(
            N_Significant_Main_Effects = sum(.data$p_value < config$analysis$alpha & !grepl(":", .data$Effect_Code, fixed = TRUE), na.rm = TRUE),
            N_Significant_Interactions = sum(.data$p_value < config$analysis$alpha & grepl(":", .data$Effect_Code, fixed = TRUE), na.rm = TRUE),
            Minimum_Omnibus_p = if (all(is.na(.data$p_value))) NA_real_ else min(.data$p_value, na.rm = TRUE),
            .groups = "drop"
          ),
        by = "DV"
      )
  } else tibble::tibble()

  outcome_spec_table <- outcome_spec |>
    dplyr::transmute(
      DV = .data$label,
      Category = .data$category,
      Source_Column = .data$column,
      Enabled = .data$enabled,
      Correlation_Enabled = .data$include_in_correlation
    )

  analysis_end_time <- Sys.time()
  run_info <- tibble::tibble(
    Item = c(
      "Analysis engine", "Configuration file", "Input file", "Input sheet",
      "Input data format", "Output directory", "Statistical workbook",
      "Figures PDF", "Enabled factors", "Dependent variables", "Alpha",
      "P-value adjustment", "Method selection", "Model specification",
      "Correlation analysis enabled", "Correlation variables",
      "Correlation method selection", "Correlation p-value adjustment",
      "R version", "Analysis started", "Analysis completed", "Elapsed seconds"
    ),
    Value = c(
      ENGINE_PATH, attr(config, "config_path"), input_file,
      as.character(config$input$sheet %||% "First sheet"),
      config$input$data_format %||% "wide", output_root,
      output_paths$workbook,
      if (file.exists(output_paths$figures)) output_paths$figures else NA_character_,
      paste(factor_spec$label, collapse = " × "), nrow(outcome_spec),
      config$analysis$alpha, config$analysis$p_adjust,
      config$analysis$method_selection,
      paste0("Full factorial: Y ~ ", paste(factor_codes, collapse = " * ")),
      get_correlation_config(config)$enabled,
      if (get_correlation_config(config)$enabled) {
        sum(outcome_spec$include_in_correlation %in% TRUE)
      } else {
        0L
      },
      if (get_correlation_config(config)$enabled &&
          !is.na(correlation_analysis$selected_method)) {
        paste0(
          correlation_analysis$selected_method,
          ": ",
          correlation_analysis$method_selection_reason
        )
      } else if (get_correlation_config(config)$enabled) {
        "Enabled, but fewer than two eligible variables were available."
      } else {
        "Disabled"
      },
      get_correlation_config(config)$p_adjust,
      R.version.string,
      format(analysis_start_time), format(analysis_end_time),
      round(as.numeric(difftime(analysis_end_time, analysis_start_time, units = "secs")), 3)
    )
  )

  sheet_data <- list(
    `00_Run_Info` = run_info,
    `01_Analysis_Summary` = analysis_summary,
    `02_Outcome_Spec` = outcome_spec_table,
    `03_Factor_Spec` = factor_level_table,
    `04_Design_Cell_Counts` = design_cell_counts,
    `05_Conversion_Report` = prepared$conversion_report,
    `06_Missing_Summary` = missing_summary,
    `07_Assumption_Tests` = assumptions,
    `08_Cell_Shapiro` = cell_shapiro,
    `09_Model_Summary` = model_summary,
    `10_Overall_Desc` = overall_descriptive,
    `11_Main_Desc` = main_descriptive,
    `12_Interaction_Desc` = interaction_descriptive,
    `13_Omnibus_Effects` = omnibus,
    `14_Significant_Effects` = significant_effects,
    `15_Main_Posthoc` = main_posthoc,
    `16_Interaction_Cells` = interaction_cells,
    `17_Interaction_Contrasts` = interaction_contrasts,
    `18_Correlation_Normality` = correlation_analysis$variable_normality,
    `19_Correlation_Results` = correlation_analysis$results,
    `20_Correlation_Coeff` = correlation_analysis$coefficient_matrix,
    `21_Correlation_Adj_p` = correlation_analysis$adjusted_p_matrix,
    `22_Correlation_Methods` = correlation_analysis$method_matrix,
    `23_Plot_Index` = plot_index,
    `24_Warnings_Errors` = warnings_errors
  )

  write_results_workbook(sheet_data, output_paths$workbook, config$analysis$alpha, factor_codes)

  if (isTRUE(config$output$save_logs)) {
    writeLines(capture.output(sessionInfo()), file.path(output_paths$logs_dir, "sessionInfo.txt"), useBytes = TRUE)
    file.copy(attr(config, "config_path"), file.path(output_paths$logs_dir, "configuration_used.R"), overwrite = TRUE)
    file.copy(ENGINE_PATH, file.path(output_paths$logs_dir, "analysis_engine_used.R"), overwrite = TRUE)
  }

  close_script_sink()
  message("Analysis completed. Results: ", output_root)

  invisible(list(
    configuration = config,
    data = analysis_data,
    outcomes = outcome_spec,
    factors = factor_spec,
    results = results_by_outcome,
    correlations = correlation_analysis,
    workbook = output_paths$workbook,
    figures = output_paths$figures,
    output_directory = output_root
  ))
}

if (sys.nframe() == 0L) {
  trailing_arguments <- commandArgs(trailingOnly = TRUE)
  default_config <- file.path(ENGINE_DIR, "configs", "Config_Example_1_Default_TVCG.R")
  selected_config <- if (length(trailing_arguments) >= 1L) trailing_arguments[[1]] else default_config
  run_analysis(selected_config)
}
