# ============================================================================
# Configuration: Example 3 (two-factor between-subjects design)
# ============================================================================
# Edit this file, not the analysis engine.
# The object name must remain CONFIG.
# Relative paths are resolved relative to this configuration file.
# ============================================================================

CONFIG <- list(
  input = list(
    file = "../examples/Example_Data_3_Two_Factor.xlsx",
    sheet = "StudyData",
    data_format = "wide",
    id_column = "ParticipantID",
    long = list(
      outcome_name_column = "MeasureName",
      outcome_value_column = "MeasureValue"
    )
  ),

  factors = data.frame(
    code = c("F1", "F2"),
    column = c("InterfaceStyle", "FeedbackMode"),
    label = c("Interface Style", "Feedback Mode"),
    short_label = c("Interface", "Feedback"),
    enabled = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  ),

  factor_levels = list(
    F1 = c("Minimal", "Immersive"),
    F2 = c("None", "Visual", "Multimodal")
  ),

  outcomes = data.frame(
    column = c(
      "AccuracyPct",
      "CompletionTimeSec",
      "MentalEffort",
      "SystemUsability",
      "EnjoymentScore",
      "ConfidenceRating"
    ),
    label = c(
      "Accuracy",
      "Completion Time",
      "Mental Effort",
      "System Usability",
      "Enjoyment",
      "Confidence"
    ),
    category = c(
      "Task Performance",
      "Task Performance",
      "Workload",
      "User Experience",
      "User Experience",
      "User Experience"
    ),
    enabled = rep(TRUE, 6),
    include_in_correlation = rep(TRUE, 6),
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
      F1 = c(Minimal = "#66C2A5", Immersive = "#FC8D62"),
      F2 = c(None = "#F8766D", Visual = "#00BA38", Multimodal = "#619CFF")
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
