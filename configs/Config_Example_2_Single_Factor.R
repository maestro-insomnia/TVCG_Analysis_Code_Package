# ============================================================================
# Configuration: Example 2 (single-factor between-subjects design)
# ============================================================================
# Edit this file, not the analysis engine.
# The object name must remain CONFIG.
# Relative paths are resolved relative to this configuration file.
# ============================================================================

CONFIG <- list(
  input = list(
    file = "../examples/Example_Data_2_Single_Factor.xlsx",
    sheet = "StudyData",
    data_format = "wide",
    id_column = "ParticipantID",
    long = list(
      outcome_name_column = "MeasureName",
      outcome_value_column = "MeasureValue"
    )
  ),

  # One enabled row defines the single between-subjects factor.
  factors = data.frame(
    code = "F1",
    column = "TrainingMode",
    label = "Training Mode",
    short_label = "Training",
    enabled = TRUE,
    stringsAsFactors = FALSE
  ),

  factor_levels = list(
    F1 = c("Standard", "Guided", "Adaptive")
  ),

  outcomes = data.frame(
    column = c(
      "AccuracyScore",
      "CompletionTimeSec",
      "MentalEffort",
      "Satisfaction"
    ),
    label = c(
      "Accuracy Score",
      "Completion Time",
      "Mental Effort",
      "Satisfaction"
    ),
    category = c(
      "Task Performance",
      "Task Performance",
      "Workload",
      "User Experience"
    ),
    enabled = rep(TRUE, 4),
    include_in_correlation = rep(TRUE, 4),
    stringsAsFactors = FALSE
  ),

  analysis = list(
    alpha = 0.05,
    method_selection = "automatic",
    anova_type = 3,
    levene_center = "median",
    p_adjust = "bonferroni",
    minimum_valid_n = 10,
    random_seed = 20260731
  ),

  correlation = list(
    enabled = TRUE,
    minimum_complete_pairs = 10,
    normality_alpha = 0.05,
    p_adjust = "bonferroni",
    label_wrap_width = 18
  ),

  plots = list(
    create_pdf = TRUE,
    error_bar = "sd",
    main_alpha = 0.65,
    interaction_alpha = 1.00,
    factor_colors = list(
      F1 = c(Standard = "#66C2A5", Guided = "#FC8D62", Adaptive = "#8DA0CB")
    ),
    base_font_size = 11,
    stat_font_size = 9.5,
    title_wrap_width = 58,
    page_title_wrap_width = 70,
    interaction_ncol = 4,
    caption_wrap_width = 58,
    pdf_width = 16,
    pdf_height = 9,
    category_order = c("Task Performance", "Workload", "User Experience"),

    # This setting is ignored unless exactly three factors are enabled.
    three_way_mapping = NULL,
    three_way_facet_rows = 1
  ),

  output = list(
    directory = NULL,
    save_art_diagnostics = TRUE,
    save_logs = TRUE
  ),

  packages = list(
    auto_install = TRUE,
    repository = "https://cloud.r-project.org"
  )
)
