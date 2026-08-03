# Usage Guide

This guide documents the configurable analysis workflow in the `TVCG_Analysis_Code_Package` repository. It explains how to run the supplied examples, prepare new datasets, edit configuration files, interpret the automatic statistical decisions, and locate results in the Excel workbook and figures PDF.

For a project overview and quick start, see the repository [README](../README.md).

## 1. Workflow architecture

The repository separates the statistical implementation from study-specific settings:

- `TVCG_Factorial_ANOVA_ART_Analysis.R` is the analysis engine.
- `configs/*.R` files define the data source, factors, outcomes, analysis rules, correlation settings, plots, and output behavior.
- `run_example_1.R` and `run_example_2.R` are launcher scripts.
- `examples/*.xlsx` contains synthetic demonstration data.

The configuration object must always be named:

```r
CONFIG
```

For a new analysis, copy and edit `configs/Config_Template.R`. Do not normally edit the engine.

## 2. Repository contents

```text
TVCG_Analysis_Code_Package/
├── README.md
├── TVCG_Factorial_ANOVA_ART_Analysis.R
├── run_example_1.R
├── run_example_2.R
├── configs/
│   ├── Config_Example_1_Default_TVCG.R
│   ├── Config_Example_2_Alternative_Names.R
│   └── Config_Template.R
├── docs/
│   └── USAGE_GUIDE.md
└── examples/
    ├── Example_Data_1_Default_TVCG_Format.xlsx
    └── Example_Data_2_Alternative_Names.xlsx
```

### Example 1

`Config_Example_1_Default_TVCG.R` analyzes a synthetic `2 × 2 × 4` design using the TVCG-style factor and outcome names.

### Example 2

`Config_Example_2_Alternative_Names.R` analyzes a synthetic design with different factor names, level counts, dependent-variable names, categories, and Excel sheet name. It demonstrates how to reuse the engine for another study.

## 3. R environment and packages

A recent R installation is required. RStudio is optional.

The engine uses:

```r
c(
  "readxl", "readr", "dplyr", "tidyr", "purrr", "stringr", "tibble",
  "car", "ARTool", "emmeans", "ggplot2", "openxlsx", "fs", "rlang",
  "patchwork"
)
```

The supplied configurations use:

```r
packages = list(
  auto_install = TRUE,
  repository = "https://cloud.r-project.org"
)
```

With `auto_install = TRUE`, missing packages are installed from the configured CRAN repository. Set it to `FALSE` when package installation is managed externally.

The script records the R version and session information in the run outputs when logs are enabled.

## 4. Running the supplied examples

### 4.1 RStudio or R console

From the repository folder:

```r
source("run_example_1.R")
```

or:

```r
source("run_example_2.R")
```

The launcher scripts determine their own directory before locating the engine and configuration file. This avoids relying on the active working directory in most RStudio, `source()`, and `Rscript` workflows.

### 4.2 Direct engine call

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_Example_1_Default_TVCG.R")
```

### 4.3 Command line

```bash
Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
```

## 5. Preparing input data

Supported input formats are:

```text
.xlsx
.xls
.csv
.tsv
.txt
.rds
```

For Excel files, specify the worksheet name or number in `input$sheet`.

### 5.1 Wide format

Wide format is recommended. Each row represents one independent participant or experimental unit, and each dependent variable has its own column.

```text
ID | FactorA | FactorB | FactorC | Outcome1 | Outcome2
1  | Low     | Text    | C1      | 4.2      | 75
2  | High    | Audio   | C2      | 5.1      | 82
```

Configuration:

```r
input = list(
  file = "../examples/my_data.xlsx",
  sheet = "Sheet1",
  data_format = "wide",
  id_column = "ID",
  long = list(
    outcome_name_column = "OutcomeName",
    outcome_value_column = "OutcomeValue"
  )
)
```

The `long` fields are ignored in wide-format analyses.

### 5.2 Long format

Long format stores outcome names and values in two columns.

```text
ID | FactorA | FactorB | OutcomeName | OutcomeValue
1  | Low     | Text    | Outcome1   | 4.2
1  | Low     | Text    | Outcome2   | 75
```

Configuration:

```r
input = list(
  file = "../examples/my_long_data.csv",
  sheet = NULL,
  data_format = "long",
  id_column = "ID",
  long = list(
    outcome_name_column = "OutcomeName",
    outcome_value_column = "OutcomeValue"
  )
)
```

Each ID/factor/outcome combination must be unique. The engine converts valid long-format input to wide format internally.

### 5.3 Identifier requirements

The current engine is designed for between-subjects data. The ID column should normally identify one independent participant or experimental unit. Duplicate IDs are reported because they may indicate repeated measurements or incorrectly structured input.

### 5.4 Factor values

Configured factor levels must match the values in the input data after conversion to text. Differences in capitalization, spaces, punctuation, or numeric formatting can cause an unknown-level error.

### 5.5 Outcome values

Outcome columns are converted to numeric. Non-numeric values that cannot be converted become missing and are recorded in the conversion report. Factor-valued outcomes are converted through their displayed text rather than internal factor codes.

## 6. Creating a configuration file

Copy the template:

```text
configs/Config_Template.R
```

Rename it, for example:

```text
configs/Config_My_Study.R
```

Keep the object name unchanged:

```r
CONFIG <- list(...)
```

Relative paths in a configuration are resolved relative to that configuration file.

## 7. Configuration reference

### 7.1 `input`

```r
input = list(
  file = "../examples/your_data.xlsx",
  sheet = "Sheet1",
  data_format = "wide",
  id_column = "ID",
  long = list(
    outcome_name_column = "OutcomeName",
    outcome_value_column = "OutcomeValue"
  )
)
```

#### `input$file`

Path to the input file. Relative paths are evaluated from the configuration directory.

#### `input$sheet`

Excel worksheet name or number. Ignored for CSV, TSV, TXT, and RDS input.

#### `input$data_format`

Accepted values:

```r
"wide"
"long"
```

#### `input$id_column`

Exact name of the participant or experimental-unit identifier column.

#### `input$long`

Used only for long-format data:

- `outcome_name_column`: column containing outcome names;
- `outcome_value_column`: column containing outcome values.

### 7.2 `factors`

Exactly two or three factors must be enabled.

```r
factors = data.frame(
  code = c("X1", "X2", "X3"),
  column = c("Factor1Column", "Factor2Column", "Factor3Column"),
  label = c("Factor 1", "Factor 2", "Factor 3"),
  short_label = c("F1", "F2", "F3"),
  enabled = c(TRUE, TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

#### `code`

Short internal name used in formulas and output tables. Codes must be unique and valid R names. Simple values such as `X1`, `X2`, and `X3` are recommended.

#### `column`

Exact factor-column name in the input data.

#### `label`

Full factor name used in tables, axes, and legends.

#### `short_label`

Compact label used in interaction-plot titles.

#### `enabled`

- `TRUE`: include the factor;
- `FALSE`: ignore the factor.

### 7.3 `factor_levels`

```r
factor_levels = list(
  X1 = c("Low", "High"),
  X2 = c("Text", "Audio"),
  X3 = c("C1", "C2", "C3")
)
```

The list names must match enabled factor codes. Level order controls:

- factor coding;
- table order;
- axis order;
- legend order; and
- pairwise-comparison direction.

Every observed factor value must appear in the corresponding configured level vector. Configured but unobserved combinations are reported as empty cells.

### 7.4 `outcomes`

```r
outcomes = data.frame(
  column = c("Outcome1Column", "Outcome2Column"),
  label = c("Outcome 1", "Outcome 2"),
  category = c("Category A", "Category B"),
  enabled = c(TRUE, TRUE),
  include_in_correlation = c(TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

#### `column`

Exact source-column name in the input data.

#### `label`

Display name used in tables and figures. Labels must be unique.

#### `category`

Organizational label used to group and order PDF pages. It does not change the statistical model.

#### `enabled`

Controls factorial ANOVA/ART-ANOVA analysis for the variable.

#### `include_in_correlation`

Controls whether the variable is included in the correlation module. This setting is independent of `enabled`.

#### Automatic outcome detection

Set:

```r
outcomes = NULL
```

The engine then detects numeric columns other than the ID and enabled factor columns. Automatically detected outcomes are assigned to `Uncategorized`.

Explicit outcome definitions are recommended for reproducible public code because they preserve labels, categories, order, and correlation inclusion decisions.

### 7.5 `analysis`

```r
analysis = list(
  alpha = 0.05,
  method_selection = "automatic",
  anova_type = 3,
  levene_center = "median",
  p_adjust = "bonferroni",
  minimum_valid_n = 10,
  random_seed = 20260731
)
```

#### `analysis$alpha`

Statistical significance threshold used for assumption decisions, omnibus effects, and plot annotations unless another module has its own threshold.

#### `analysis$method_selection`

Accepted values:

```r
"automatic"
"anova"
"art"
```

- `automatic`: select ANOVA only when both assumption tests are non-significant; otherwise select ART-ANOVA.
- `anova`: always use parametric factorial ANOVA.
- `art`: always use ART-ANOVA.

#### `analysis$anova_type`

Type of sums of squares passed to `car::Anova()` for parametric analyses. The supplied configurations use Type III:

```r
anova_type = 3
```

The engine uses sum-to-zero contrasts while running the analysis.

#### `analysis$levene_center`

Accepted values:

```r
"median"
"mean"
```

The supplied configurations use median-centered Levene tests.

#### `analysis$p_adjust`

Multiplicity adjustment used for main-effect pairwise comparisons and interaction follow-up analyses. The supplied configurations use:

```r
p_adjust = "bonferroni"
```

Use an adjustment method supported by the underlying R procedures.

#### `analysis$minimum_valid_n`

Minimum valid sample size required before attempting an outcome analysis.

#### Complete factorial model

The engine always uses the complete factorial model for all enabled factors. There is no maximum-interaction-order option.

Two-factor example:

```r
Y ~ X1 * X2
```

Three-factor example:

```r
Y ~ X1 * X2 * X3
```

All enabled main effects and interactions are calculated and exported. Manuscript reporting decisions remain with the analyst.

#### `analysis$random_seed`

Used for reproducible internal sampling, including Shapiro–Wilk evaluation when more than 5,000 values are available. In that case, a random sample of 5,000 observations is used and documented.

### 7.6 `correlation`

```r
correlation = list(
  enabled = TRUE,
  minimum_complete_pairs = 10,
  normality_alpha = 0.05,
  p_adjust = "bonferroni",
  label_wrap_width = 18
)
```

#### `correlation$enabled`

Master switch for the complete correlation module.

```r
enabled = TRUE
```

When `FALSE`, correlation tests and the heatmap are skipped. The workbook retains the correlation worksheet positions with no computed correlation results so that the workbook structure remains predictable.

#### `correlation$minimum_complete_pairs`

This value has two roles:

- each variable needs at least this many finite observations to be eligible for global Pearson selection;
- each variable pair needs at least this many pairwise-complete observations for a correlation test.

#### `correlation$normality_alpha`

Threshold used for the global Pearson/Spearman decision.

Each included variable is evaluated once using all of its finite observations. Pearson is selected only when every included variable:

1. has at least `minimum_complete_pairs` finite observations;
2. has at least three unique finite values; and
3. has Shapiro–Wilk `p >= normality_alpha`.

If any included variable fails or cannot be evaluated, Spearman is used for all tested pairs.

This global decision ensures that one correlation matrix contains one consistent coefficient type.

#### `correlation$p_adjust`

Multiplicity adjustment applied across all successfully tested variable pairs. The adjusted values determine the significance symbols in the heatmap.

#### `correlation$label_wrap_width`

Approximate character width used to wrap long variable labels on the correlation heatmap axes.

#### Pairwise missing values

After the global method is selected, each correlation is calculated using the finite observations shared by that variable pair. As a result, `N_Complete` may differ among pairs.

#### Heatmap layout

- lower triangle: correlation coefficients;
- upper triangle: adjusted-*p* significance symbols;
- diagonal: blank;
- unavailable pairs: `NA`.

The title reports the globally selected method.

### 7.7 `plots`

```r
plots = list(
  create_pdf = TRUE,
  error_bar = "sd",
  main_alpha = 0.65,
  interaction_alpha = 1.00,
  factor_colors = list(...),
  base_font_size = 11,
  stat_font_size = 9.5,
  title_wrap_width = 58,
  page_title_wrap_width = 70,
  interaction_ncol = 4,
  caption_wrap_width = 58,
  pdf_width = 16,
  pdf_height = 9,
  category_order = c(...),
  three_way_mapping = list(
    x = "X1",
    color = "X2",
    facet = "X3"
  ),
  three_way_facet_rows = 2
)
```

#### `plots$create_pdf`

Set to `FALSE` to skip PDF generation.

#### `plots$error_bar`

Accepted values:

```r
"sd"
"se"
```

The selected measure is used in main-effect and interaction plots.

#### Transparency

- `main_alpha`: opacity of main-effect bars;
- `interaction_alpha`: opacity of interaction lines, points, and error bars.

#### `plots$factor_colors`

Named colors for each configured factor level.

```r
factor_colors = list(
  X1 = c(Low = "#66C2A5", High = "#FC8D62"),
  X2 = c(Text = "#8DA0CB", Audio = "#E78AC3")
)
```

Names must match configured factor levels. Consistent factor-level colors are reused across plots.

#### Font sizes

- `base_font_size`: general ggplot text size;
- `stat_font_size`: omnibus statistic annotation size.

The script does not require a user-installed custom font. PDF and Excel outputs inherit standard device or workbook defaults unless the engine is modified to specify a font family.

#### Title and caption wrapping

- `title_wrap_width`: individual plot-title wrapping; supplied configurations use `58`.
- `page_title_wrap_width`: category and dependent-variable page heading wrapping.
- `caption_wrap_width`: interaction-caption wrapping.

#### `plots$interaction_ncol`

Number of interaction plots per PDF row.

#### PDF dimensions

`pdf_width` and `pdf_height` are in inches.

#### `plots$category_order`

Controls the order of category sections in the PDF. Categories not listed can still be retained after configured categories, depending on the generated results.

#### Three-way mapping

For three enabled factors, define which factor appears on each visual channel:

```r
three_way_mapping = list(
  x = "X1",
  color = "X2",
  facet = "X3"
)
```

The three entries must be distinct enabled factor codes.

`three_way_facet_rows` controls the number of facet rows.

### 7.8 `output`

```r
output = list(
  directory = NULL,
  save_art_diagnostics = TRUE,
  save_logs = TRUE
)
```

#### `output$directory`

When `NULL`, the engine creates:

```text
<input_file_stem>_analysis_results/
```

next to the input file.

Supply a relative or absolute path to use a custom output directory. Relative output paths are resolved from the configuration directory.

#### `output$save_art_diagnostics`

Controls creation of the `art_diagnostics/` directory and ART diagnostic files.

#### `output$save_logs`

Controls creation of the `logs/` directory and reproducibility files.

### 7.9 `packages`

```r
packages = list(
  auto_install = TRUE,
  repository = "https://cloud.r-project.org"
)
```

Set `auto_install = FALSE` when installation should not be performed by the analysis script.

## 8. Statistical analysis logic

### 8.1 Input and design validation

The engine checks, among other conditions:

- missing input files or worksheets;
- missing ID, factor, or outcome columns;
- invalid or duplicate factor codes;
- duplicate outcome labels;
- conflicting ID, factor, and outcome columns;
- unknown factor levels;
- duplicated IDs;
- empty factorial cells;
- numeric-conversion failures;
- missing and non-finite outcome values;
- insufficient valid observations;
- constant outcomes;
- rank-deficient models; and
- unavailable residual degrees of freedom.

Warnings and recoverable errors are collected in `24_Warnings_Errors` so that one failed follow-up analysis does not necessarily stop every other outcome.

### 8.2 Assumption testing

For each outcome, the engine first fits the complete factorial linear model and evaluates:

- Shapiro–Wilk normality of model residuals;
- Levene homogeneity of variance across factorial cells.

When more than 5,000 residuals are available, `safe_shapiro()` uses a reproducible random sample of 5,000.

Cell-level Shapiro–Wilk diagnostics are also exported for inspection, but the automatic method decision is based on model residuals and Levene's test.

### 8.3 Automatic method selection

With:

```r
method_selection = "automatic"
```

ANOVA is selected only when both tests have:

```text
p >= analysis$alpha
```

ART-ANOVA is selected when either test rejects the assumption or the parametric assumption result is unavailable.

The selected method and reason are recorded for every dependent variable and shown in the PDF page titles.

### 8.4 Parametric ANOVA

The parametric branch uses the complete factorial model and `car::Anova()` with the configured sums-of-squares type. The supplied configurations use Type III tests with sum-to-zero contrasts.

### 8.5 ART-ANOVA

The nonparametric factorial branch uses `ARTool::art()` and the complete factorial model. The engine checks ART alignment diagnostics and records diagnostic output when enabled.

### 8.6 Omnibus effect sizes

The omnibus output includes:

- effect code and label;
- numerator and denominator degrees of freedom;
- *F* statistic;
- *p* value;
- partial eta-squared;
- Cohen's *f*; and
- qualitative magnitude.

The qualitative partial eta-squared labels use these thresholds:

```text
< .01       negligible
.01–< .06   small
.06–< .14   medium
>= .14      large
```

For ART-ANOVA, effect sizes are calculated from the aligned-rank analysis and identified accordingly.

### 8.7 Main-effect comparisons

- ANOVA branch: estimated marginal means followed by pairwise contrasts.
- ART branch: ART-compatible contrasts.
- Multiplicity adjustment follows `analysis$p_adjust`.
- Significant adjusted comparisons that can be mapped to configured factor levels are drawn as brackets on main-effect plots.

The main-posthoc worksheet includes parsing and annotation-eligibility fields so bracket mapping can be audited.

### 8.8 Interaction follow-up analyses

The engine attempts:

- comparisons among interaction cells;
- difference-of-differences contrasts for two-way interactions; and
- higher-order contrasts for three-way interactions.

Sparse, empty, or non-estimable combinations may prevent some contrasts. These cases are recorded rather than silently replaced with artificial values.

### 8.9 Descriptive statistics

The workbook includes:

- overall descriptive statistics for each outcome;
- descriptive statistics grouped by each main-effect factor; and
- descriptive statistics for each interaction combination.

The configured factor order is enforced in all relevant worksheets.

### 8.10 Significance notation

The PDF uses:

```text
p < 0.001   ***
p < 0.01    **
p < 0.05    *
p < 0.10    .
p >= 0.10   n.s.
```

The dot indicates a trend-level result under this display convention, not significance at `alpha = .05`.

## 9. Output directory and files

Default output structure:

```text
<input_file_stem>_analysis_results/
├── <input_file_stem>_statistical_results.xlsx
├── <input_file_stem>_figures.pdf
├── logs/
└── art_diagnostics/
```

The PDF is omitted when `plots$create_pdf = FALSE` or when no plot can be generated. Log and ART diagnostic directories are created only when their output switches are enabled.

## 10. Excel workbook reference

The workbook is organized in the following order.

| Sheet | Purpose |
|---|---|
| `00_Run_Info` | Input, configuration, software, timing, and output-path information. |
| `01_Analysis_Summary` | One-row summary of method selection and significant effects for each outcome. |
| `02_Outcome_Spec` | Outcome labels, source columns, categories, and analysis/correlation switches. |
| `03_Factor_Spec` | Factor codes, labels, source columns, and configured level order. |
| `04_Design_Cell_Counts` | Counts for every configured factorial cell, including empty cells. |
| `05_Conversion_Report` | Numeric-conversion checks for outcome columns. |
| `06_Missing_Summary` | Missing-data counts and percentages by outcome. |
| `07_Assumption_Tests` | Residual Shapiro–Wilk, Levene tests, and selected method. |
| `08_Cell_Shapiro` | Optional Shapiro–Wilk diagnostics within factorial cells. |
| `09_Model_Summary` | Formula, sample size, residual degrees of freedom, model summaries, and ART diagnostics. |
| `10_Overall_Desc` | Overall descriptive statistics. |
| `11_Main_Desc` | Descriptive statistics by each main-effect factor. |
| `12_Interaction_Desc` | Descriptive statistics by interaction combinations. |
| `13_Omnibus_Effects` | Main effects and interactions with test statistics and effect sizes. |
| `14_Significant_Effects` | Omnibus effects with `p < alpha`, preserving configured order. |
| `15_Main_Posthoc` | Main-effect pairwise comparisons and bracket-mapping diagnostics. |
| `16_Interaction_Cells` | Pairwise comparisons among interaction cells. |
| `17_Interaction_Contrasts` | Difference-of-differences and higher-order interaction contrasts. |
| `18_Correlation_Normality` | Variable-level diagnostics and the global Pearson/Spearman decision. |
| `19_Correlation_Results` | Pairwise correlation tests, sample sizes, method, coefficients, and adjusted *p* values. |
| `20_Correlation_Coeff` | Symmetric correlation-coefficient matrix. |
| `21_Correlation_Adj_p` | Symmetric adjusted-*p* matrix. |
| `22_Correlation_Methods` | Matrix confirming the single method used throughout the correlation analysis. |
| `23_Plot_Index` | Figure type and PDF page index. |
| `24_Warnings_Errors` | Captured warnings and recoverable errors. |

Each worksheet includes a right-side section describing its output columns. Factor columns follow the enabled factor order defined in the configuration.

When correlation analysis is disabled or cannot be performed, the corresponding correlation worksheets remain in their logical positions but contain no computed test results or only the available diagnostic information.

## 11. Figures PDF reference

### 11.1 Category title pages

Each category with generated plots begins with a title page containing the significance notation.

### 11.2 Main-effects pages

The page title contains the dependent variable, page type, and selected method, for example:

```text
Social Presence — Main Effects (ANOVA)
```

Each enabled factor receives a main-effect plot. The plots include:

- mean ± configured error bar;
- omnibus statistic annotation;
- consistent factor-level colors;
- significant adjusted pairwise brackets when available; and
- a caption reporting the number of significant adjusted comparisons.

### 11.3 Interaction-effects pages

Two-way and three-way interaction plots are placed on the interaction page. Plot titles use factor short labels where configured. Captions summarize the number of significant interaction contrasts or direct the user to the warning worksheet when contrasts are unavailable.

### 11.4 Correlation heatmap

When correlation analysis succeeds, the heatmap is appended after the factorial-analysis pages.

- The title identifies Pearson or Spearman.
- The lower triangle contains coefficients.
- The upper triangle contains significance symbols based on adjusted *p* values.
- The diagonal is blank.

### 11.5 PDF fonts and mathematical symbols

The script controls font sizes but does not require a custom locally installed font family. Standard R PDF-device and ggplot defaults are used.

Partial eta-squared is rendered with R plotmath rather than Unicode subscript characters. This reduces missing-glyph problems in PDF output.

## 12. Adapting the template to a new study

### Step 1: copy the template

```text
configs/Config_Template.R
```

to:

```text
configs/Config_My_Study.R
```

### Step 2: set the input file

```r
input = list(
  file = "../examples/My_Study_Data.xlsx",
  sheet = "Data",
  data_format = "wide",
  id_column = "ParticipantID",
  long = list(
    outcome_name_column = "Measure",
    outcome_value_column = "Value"
  )
)
```

### Step 3: define factors

```r
factors = data.frame(
  code = c("F1", "F2", "F3"),
  column = c("InterfaceStyle", "FeedbackMode", "TaskDifficulty"),
  label = c("Interface Style", "Feedback Mode", "Task Difficulty"),
  short_label = c("Interface", "Feedback", "Difficulty"),
  enabled = c(TRUE, TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

For a two-factor design, disable one row:

```r
enabled = c(TRUE, TRUE, FALSE)
```

and ensure the enabled factors have matching level definitions.

### Step 4: define factor levels

```r
factor_levels = list(
  F1 = c("Minimal", "Immersive"),
  F2 = c("None", "Visual", "Multimodal"),
  F3 = c("Easy", "Hard")
)
```

### Step 5: define outcomes

```r
outcomes = data.frame(
  column = c(
    "AccuracyPct",
    "CompletionTimeSec",
    "MentalEffort",
    "SystemUsability"
  ),
  label = c(
    "Accuracy",
    "Completion Time",
    "Mental Effort",
    "System Usability"
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
)
```

### Step 6: set category order and colors

```r
plots = list(
  # Other fields omitted here.
  factor_colors = list(
    F1 = c(Minimal = "#66C2A5", Immersive = "#FC8D62"),
    F2 = c(None = "#F8766D", Visual = "#00BA38", Multimodal = "#619CFF"),
    F3 = c(Easy = "#8DA0CB", Hard = "#E78AC3")
  ),
  category_order = c("Task Performance", "Workload", "User Experience"),
  three_way_mapping = list(
    x = "F1",
    color = "F2",
    facet = "F3"
  )
)
```

Do not replace the complete `plots` list with only this abbreviated example. Edit the corresponding fields in the template.

### Step 7: validate configuration lengths

All columns in the `factors` data frame must have the same length. All columns in the `outcomes` data frame must also have the same length.

### Step 8: run the analysis

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_My_Study.R")
```

### Step 9: review diagnostics before reporting

At minimum, inspect:

- `04_Design_Cell_Counts`;
- `05_Conversion_Report`;
- `06_Missing_Summary`;
- `07_Assumption_Tests`;
- `09_Model_Summary`;
- `13_Omnibus_Effects`;
- relevant post-hoc sheets;
- `18_Correlation_Normality` when correlation is enabled; and
- `24_Warnings_Errors`.

## 13. Default TVCG-style example

The default synthetic workbook contains:

### Factors

- `Appearance-Fidelity`: `H`, `L`;
- `Speech-Fidelity`: `H`, `L`;
- `Character-Identity`: `1(M1)`, `2(M2)`, `3(F1)`, `4(F2)`.

The design contains 16 factorial cells and 160 synthetic rows.

### Outcomes

- Communication Efficiency;
- Communication Intention;
- Social Presence;
- Interpersonal Trust;
- Perceived Humanness;
- Eeriness;
- Attractiveness;
- Anthropomorphism;
- Animacy;
- Likeability;
- Perceived Intelligence;
- Perceived Safety;
- Perceived Appearance Realism;
- Perceived Speech Realism;
- Perceived Overall Realism.

The workbook contains only the analysis-ready `Sheet1`. It does not contain original participant data.

## 14. Troubleshooting

### Configuration file not found

Check the path passed to `run_analysis()`. Relative paths are interpreted from the current call when locating the configuration, while paths inside the configuration are interpreted from the configuration directory.

### Input file not found

Check `CONFIG$input$file`. For a configuration in `configs/`, an example file in `examples/` is normally referenced with:

```r
file = "../examples/FileName.xlsx"
```

### Excel worksheet not found

Verify `input$sheet` exactly matches the workbook sheet name. Sheet numbers can also be used.

### Input column is missing

Check exact spelling, capitalization, spaces, punctuation, and hyphens in:

- `input$id_column`;
- `factors$column`;
- `outcomes$column`; and
- long-format column settings.

### Unknown factor level

Add every observed value to the relevant `factor_levels` entry or correct the input value. Avoid invisible trailing spaces in spreadsheets.

### Duplicate IDs

The workflow is designed for between-subjects data. Duplicate IDs may indicate repeated measures or that multiple rows should first be aggregated or restructured.

### Outcome conversion failures

Inspect `05_Conversion_Report`. Text such as units, symbols, or non-numeric response labels cannot be analyzed directly as numeric outcomes.

### Empty cells or rank deficiency

Inspect `04_Design_Cell_Counts`, `09_Model_Summary`, and `24_Warnings_Errors`. Empty factorial cells can make Type III effects or follow-up contrasts non-estimable.

### ANOVA selected unexpectedly

Inspect both assumption *p* values in `07_Assumption_Tests` and confirm `analysis$method_selection = "automatic"`. ANOVA is selected only when both configured assumption decisions pass.

### ART-ANOVA selected unexpectedly

The automatic rule selects ART when either assumption fails or cannot be evaluated. Inspect the selection reason in `07_Assumption_Tests`.

### Main-effect brackets are missing

Inspect `15_Main_Posthoc`:

- confirm the adjusted `p.value` is below `analysis$alpha`;
- check `Group1` and `Group2`;
- check `Annotation_Eligible`;
- review `24_Warnings_Errors` for parsing or post-hoc failures.

### Interaction contrast unavailable

Sparse or non-estimable cells may prevent an interaction contrast. The error is recorded in `24_Warnings_Errors`, while other valid analyses continue.

### Correlation analysis uses Spearman

Inspect `18_Correlation_Normality`. Spearman is selected globally when any included variable fails or cannot be evaluated under the Pearson eligibility rule.

To exclude a problematic variable from the correlation matrix without disabling its factorial analysis, set its `include_in_correlation` value to `FALSE`.

### Correlation pair is `NA`

A variable pair may be unavailable because:

- it has fewer than `minimum_complete_pairs` shared finite observations;
- one variable is constant within the shared observations; or
- `cor.test()` returned an error.

Inspect `19_Correlation_Results` and `24_Warnings_Errors`.

### PDF is not created

Check:

```r
plots$create_pdf
```

and inspect `24_Warnings_Errors`. A PDF is not written when plotting is disabled or no plot can be generated.

### Font-family warning

The default script does not require Arial, Times New Roman, or another custom installed font. Adding a custom font family to the engine or themes can make the workflow dependent on local font availability.

### Excel reports repaired content

Do not manually rename a worksheet header inside an existing structured Excel table without updating the table metadata. The supplied Example 1 workbook has been rebuilt without an Excel table object and contains only `Sheet1`, avoiding stale `/xl/tables/table1.xml` metadata.

### Package built under another R version

A warning that a package was built under a different R version is usually a compatibility warning rather than an analysis result. Update R and reinstall packages when necessary.

## 15. Reproducibility notes

- The engine temporarily uses sum-to-zero contrasts and restores the caller's R options after completion.
- The configured random seed is used for reproducible internal sampling.
- The caller's random-number state is restored after analysis.
- Output paths are derived consistently from the input file unless overridden.
- When logs are enabled, the run records timing, configuration, engine, console output, and R session information.
- Synthetic example data are for software demonstration only.

## 16. Scope and limitations

- Exactly two or three enabled between-subject factors are supported.
- Repeated-measures, nested, hierarchical, and mixed-effects designs require a different model specification.
- Automatic ANOVA/ART-ANOVA selection is a fixed reproducible decision rule; it does not replace substantive statistical judgment.
- Shapiro–Wilk tests can be sensitive to sample size, and non-significance does not prove normality.
- Levene non-significance does not prove equal variance.
- Pairwise deletion can produce different sample sizes across correlations.
- Multiplicity corrections can substantially reduce power when many comparisons are tested.
- Researchers should inspect diagnostics, effect estimates, confidence intervals, cell sizes, and study design before reporting results.
