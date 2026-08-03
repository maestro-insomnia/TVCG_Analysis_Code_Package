# ============================================================================
# Configuration: Example 2 (different factor and dependent-variable names)
# ============================================================================
# Edit this file, not the analysis engine.
# The object name must remain CONFIG.
# Relative paths are resolved relative to this configuration file.
# ============================================================================

CONFIG <- list(
  input = list(
    # Supported extensions: xlsx, xls, csv, tsv, txt, and rds.
    file = "../examples/Example_Data_2_Alternative_Names.xlsx",

    # Excel sheet name or number. Ignored for CSV, TSV, TXT, and RDS files.
    sheet = "StudyData",

    # Use "wide" when dependent variables are stored in separate columns.
    # Use "long" when outcome names and values are stored in two columns.
    data_format = "wide",

    # Column containing the participant or experimental-unit identifier.
    id_column = "ParticipantID",

    # These settings are used only when data_format = "long".
    long = list(
      outcome_name_column = "MeasureName",
      outcome_value_column = "MeasureValue"
    )
  ),

  # Each enabled row defines one factor.
  # code        : short internal R name used in formulas; must be unique.
  # column      : exact factor-column name in the input data.
  # label       : full name used on axes, legends, and tables.
  # short_label : compact name used in interaction-plot titles.
  # enabled     : TRUE includes the factor; FALSE ignores it.
  factors = data.frame(
    code = c("F1", "F2", "F3"),
    column = c("InterfaceStyle", "FeedbackMode", "TaskDifficulty"),
    label = c("Interface Style", "Feedback Mode", "Task Difficulty"),
    short_label = c("Interface", "Feedback", "Difficulty"),
    enabled = c(TRUE, TRUE, TRUE),
    # Keep text columns as character vectors rather than converting them
    # automatically to factors. Leave this as FALSE; factor level order is
    # controlled explicitly by factor_levels in this configuration.
    stringsAsFactors = FALSE
  ),

  # The names in this list must match the factor codes above.
  # The order controls reference/display order throughout the analysis.
  factor_levels = list(
    F1 = c("Minimal", "Immersive"),
    F2 = c("None", "Visual", "Multimodal"),
    F3 = c("Easy", "Hard")
  ),

  # Each enabled row defines one dependent variable.
  # column   : exact source-column name in the input data.
  # label    : name displayed in output tables and figures.
  # category : organizational label used to order the figures PDF.
  # enabled  : TRUE analyzes the variable; FALSE skips it.
# include_in_correlation: TRUE includes the variable in correlation analysis.
  #
  # Set outcomes = NULL to automatically analyze all numeric columns that are
  # not the ID or factor columns. Automatically detected outcomes are assigned
  # to the category "Uncategorized".
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
    # Keep text columns as character vectors rather than converting them
    # automatically to factors. Leave this as FALSE; factor level order is
    # controlled explicitly by factor_levels in this configuration.
    stringsAsFactors = FALSE
  ),

  analysis = list(
    # Statistical significance threshold.
    alpha = 0.05,

    # "automatic": ANOVA when both assumption tests are non-significant;
    #              otherwise ART-ANOVA.
    # "anova"    : always use ANOVA.
    # "art"      : always use ART-ANOVA.
    method_selection = "automatic",

    # Type of sums of squares used by car::Anova for parametric analyses.
    anova_type = 3,

    # Center used by Levene's test: "median" or "mean".
    levene_center = "median",

    # Multiplicity correction used for pairwise comparisons and contrasts.
    p_adjust = "bonferroni",

    # Minimum valid sample size required for an outcome analysis.
    minimum_valid_n = 10,

    # The engine always fits and exports the complete factorial model for all
    # enabled factors. No interaction-order setting is required.

    # Seed used for any reproducible sampling, such as Shapiro-Wilk when more
    # than 5,000 residuals are available.
    random_seed = 20260731
  ),


  correlation = list(
    # Master switch for the correlation module.
    enabled = TRUE,

    # Minimum number of pairwise-complete observations required for a test.
    minimum_complete_pairs = 10,

    # One common method is used for the complete correlation matrix. Pearson
    # is selected only when every included variable passes Shapiro-Wilk
    # normality at this alpha and has at least three unique finite values.
    # If any included variable fails or cannot be evaluated, Spearman is used
    # for every tested variable pair.
    normality_alpha = 0.05,

    # Multiplicity adjustment applied across all tested variable pairs.
    p_adjust = "bonferroni",

    # Heatmap labels are split across the full matrix: the lower triangle
    # shows correlation coefficients, the upper triangle shows adjusted-p
    # significance symbols, and diagonal cells are blank.
    label_wrap_width = 18
  ),

  plots = list(
    # Set FALSE to skip PDF generation.
    create_pdf = TRUE,

    # Error bars: "sd" for Mean ± SD or "se" for Mean ± SE.
    error_bar = "sd",

    # Alpha transparency for main-effect bars and interaction marks.
    main_alpha = 0.65,
    interaction_alpha = 1.00,

    # Named colors are shared by main-effect and interaction plots, ensuring
    # that the same factor level always has the same color.
    factor_colors = list(
      F1 = c(Minimal = "#66C2A5", Immersive = "#FC8D62"),
      F2 = c(None = "#F8766D", Visual = "#00BA38", Multimodal = "#619CFF"),
      F3 = c(Easy = "#8DA0CB", Hard = "#E78AC3")
    ),

    # Figure typography.
    base_font_size = 11,
    stat_font_size = 9.5,

    # Maximum approximate character width for automatic wrapping of each
    # individual plot title. Reduce this value to wrap titles earlier.
    title_wrap_width = 58,

    # Maximum approximate character width for the category and outcome titles
    # printed at the top of each PDF page.
    page_title_wrap_width = 70,

    # Number of interaction plots per PDF row.
    interaction_ncol = 4,

    # Width used to wrap the explanatory caption below interaction plots.
    caption_wrap_width = 58,

    # PDF page size in inches.
    pdf_width = 16,
    pdf_height = 9,

    # Order of category sections in the PDF.
    category_order = c("Task Performance", "Workload", "User Experience"),

    # Mapping for the three-way interaction plot. These values must be enabled
    # factor codes from the factors table.
    three_way_mapping = list(
      x = "F1",
      color = "F2",
      facet = "F3"
    ),
    three_way_facet_rows = 1
  ),

  output = list(
    # NULL creates <input_file_stem>_analysis_results next to the input file.
    # Supply a relative or absolute path to use a custom directory.
    directory = NULL,

    # Only one Excel workbook is generated. All result tables are stored as
    # separate worksheets in that workbook.
    save_art_diagnostics = TRUE,
    save_logs = TRUE
  ),

  packages = list(
    # TRUE installs missing CRAN packages automatically.
    auto_install = TRUE,
    repository = "https://cloud.r-project.org"
  )
)
