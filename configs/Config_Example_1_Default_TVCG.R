# ============================================================================
# Configuration: Example 1 (default TVCG-style data structure)
# ============================================================================
# Edit this file, not the analysis engine.
# The object name must remain CONFIG.
# Relative paths are resolved relative to this configuration file.
# ============================================================================

CONFIG <- list(
  input = list(
    # Supported extensions: xlsx, xls, csv, tsv, txt, and rds.
    file = "../examples/Example_Data_1_Default_TVCG_Format.xlsx",

    # Excel sheet name or number. Ignored for CSV, TSV, TXT, and RDS files.
    sheet = "Sheet1",

    # Use "wide" when dependent variables are stored in separate columns.
    # Use "long" when outcome names and values are stored in two columns.
    data_format = "wide",

    # Column containing the participant or experimental-unit identifier.
    id_column = "ID",

    # These settings are used only when data_format = "long".
    long = list(
      outcome_name_column = "OutcomeName",
      outcome_value_column = "OutcomeValue"
    )
  ),

  # Each enabled row defines one factor.
  # code        : short internal R name used in formulas; must be unique.
  # column      : exact factor-column name in the input data.
  # label       : full name used on axes, legends, and tables.
  # short_label : compact name used in interaction-plot titles.
  # enabled     : TRUE includes the factor; FALSE ignores it.
  factors = data.frame(
    code = c("X1", "X2", "X3"),
    column = c("Appearance-Fidelity", "Speech-Fidelity", "Character-Identity"),
    label = c("Appearance-Fidelity", "Speech-Fidelity", "Character-Identity"),
    short_label = c("A-Fidelity", "S-Fidelity", "Char-Id"),
    enabled = c(TRUE, TRUE, TRUE),
    # Keep text columns as character vectors rather than converting them
    # automatically to factors. Leave this as FALSE; factor level order is
    # controlled explicitly by factor_levels in this configuration.
    stringsAsFactors = FALSE
  ),

  # The names in this list must match the factor codes above.
  # The order controls reference/display order throughout the analysis.
  factor_levels = list(
    X1 = c("H", "L"),
    X2 = c("H", "L"),
    X3 = c("1(M1)", "2(M2)", "3(F1)", "4(F2)")
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
      "Communication Efficiency",
      "Communication Intention",
      "Social Presence",
      "Interpersonal Trust",
      "Perceived Humanness",
      "Eeriness",
      "Attractiveness",
      "Anthropomorphism",
      "Animacy",
      "Likeability",
      "Perceived Intelligence",
      "Perceived Safety",
      "Perceived Appearance Realism",
      "Perceived Speech Realism",
      "Perceived Overall Realism"
    ),
    label = c(
      "Communication Efficiency",
      "Communication Intention",
      "Social Presence",
      "Interpersonal Trust",
      "Perceived Humanness",
      "Eeriness",
      "Attractiveness",
      "Anthropomorphism",
      "Animacy",
      "Likeability",
      "Perceived Intelligence",
      "Perceived Safety",
      "Perceived Appearance Realism",
      "Perceived Speech Realism",
      "Perceived Overall Realism"
    ),
    category = c(
      "Communication Outcomes",
      "Communication Outcomes",
      "Social Perception",
      "Social Perception",
      "Uncanny Valley",
      "Uncanny Valley",
      "Uncanny Valley",
      "Godspeed",
      "Godspeed",
      "Godspeed",
      "Godspeed",
      "Godspeed",
      "Perceived Realism (Manipulation Check)",
      "Perceived Realism (Manipulation Check)",
      "Perceived Realism (Manipulation Check)"
    ),
    enabled = rep(TRUE, 15),
    include_in_correlation = rep(TRUE, 15),
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
      X1 = c(H = "#66C2A5", L = "#FC8D62"),
      X2 = c(H = "#8DA0CB", L = "#E78AC3"),
      X3 = c(`1(M1)` = "#F8766D", `2(M2)` = "#7CAE00", `3(F1)` = "#00BFC4", `4(F2)` = "#C77CFF")
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
    category_order = c(
      "Communication Outcomes",
      "Social Perception",
      "Uncanny Valley",
      "Godspeed",
      "Perceived Realism (Manipulation Check)"
    ),

    # Mapping for the three-way interaction plot. These values must be enabled
    # factor codes from the factors table.
    three_way_mapping = list(
      x = "X1",
      color = "X2",
      facet = "X3"
    ),
    three_way_facet_rows = 2
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
