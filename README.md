# 📊 TVCG Analysis Code Package

Statistical analysis code for the TVCG manuscript **“Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”**

The repository provides a reusable R workflow for configurable one-, two-, or three-factor between-subjects experiments. For each dependent variable, the workflow can automatically select between ANOVA and aligned rank transform ANOVA (ART-ANOVA), run follow-up comparisons, calculate effect sizes, generate a structured Excel workbook and multi-page PDF, and optionally conduct a unified Pearson or Spearman correlation analysis.

> **Synthetic-data notice:** The example workbooks contain synthetic data only. They do not contain original participant data and are not intended to reproduce the numerical results reported in the manuscript.

## Features

- Configurable **one-, two-, or three-factor between-subjects designs**.
- Wide- and long-format input support.
- Input files: `.xlsx`, `.xls`, `.csv`, `.tsv`, `.txt`, and `.rds`.
- Automatic per-outcome selection between:
  - Type III ANOVA; and
  - ART-ANOVA.
- Complete models containing every enabled main effect and all interactions that exist for multi-factor designs.
- Residual Shapiro–Wilk and Levene assumption tests.
- Partial eta-squared, Cohen's *f*, and qualitative effect-size labels.
- Main-effect pairwise comparisons, interaction-cell comparisons, and interaction contrasts.
- Configurable multiplicity adjustment, including Bonferroni correction.
- Overall, main-effect, and interaction-cell descriptive statistics.
- Optional correlation analysis using one method for the complete matrix:
  - Pearson only when every included variable satisfies the configured eligibility rule;
  - Spearman otherwise.
- One Excel workbook with analysis results, diagnostics, and column definitions.
- One multi-page PDF with main-effect plots, interaction plots, significance annotations, and a correlation heatmap.
- Optional logs, configuration snapshots, engine copies, session information, and ART diagnostic files.

## Key repository files

```text
TVCG_Analysis_Code_Package/
├── README.md
├── TVCG_Factorial_ANOVA_ART_Analysis.R
├── run_example_1.R
├── run_example_2.R
├── run_example_3.R
├── configs/
│   ├── Config_Example_1_Default_TVCG.R
│   ├── Config_Example_2_Single_Factor.R
│   ├── Config_Example_3_Two_Factor.R
│   └── Config_Template.R
├── docs/
│   └── USAGE_GUIDE.md
└── examples/
    ├── Example_Data_1_Default_TVCG_Format.xlsx
    ├── Example_Data_2_Single_Factor.xlsx
    └── Example_Data_3_Two_Factor.xlsx
```

Additional version-specific audit and update notes may also be retained in the code package.

The workflow is separated into two layers:

1. `TVCG_Factorial_ANOVA_ART_Analysis.R` is the fixed analysis engine.
2. Files in `configs/` contain the user-editable settings in an object named `CONFIG`.

For normal use, copy and edit a configuration file rather than modifying the analysis engine.

## Requirements

The complete analysis workflow was tested successfully with R version 4.5.3. A recent installation of R is required, and RStudio is optional.

The analysis uses these R packages:

```r
c(
  "readxl", "readr", "dplyr", "tidyr", "purrr", "stringr", "tibble",
  "car", "ARTool", "emmeans", "ggplot2", "openxlsx", "fs", "rlang",
  "patchwork"
)
```

The supplied configurations install missing CRAN packages automatically:

```r
packages = list(
  auto_install = TRUE,
  repository = "https://cloud.r-project.org"
)
```

Set `auto_install = FALSE` to manage packages manually.

## Quick start

Clone or download the repository, then open the repository folder in RStudio or an R console.

### Example 1: default TVCG-style synthetic data

```r
source("run_example_1.R")
```

Equivalent direct call:

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_Example_1_Default_TVCG.R")
```

Command-line alternative:

```bash
Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
```

### Example 2: single-factor synthetic data

```r
source("run_example_2.R")
```

This example uses one three-level between-subjects factor and demonstrates that the engine automatically fits a one-factor model with no interaction analysis.

### Example 3: two-factor synthetic data

```r
source("run_example_3.R")
```

This example uses a 2 × 3 between-subjects design and demonstrates automatic main-effect and two-way interaction analysis with factor and outcome names unrelated to the TVCG study.

## Using your own data

1. Copy `configs/Config_Template.R`.
2. Rename the copy, for example `configs/Config_My_Study.R`.
3. Update the input path, factors, level order, dependent variables, categories, and plotting settings.
4. Keep the object name `CONFIG` unchanged.
5. Run:

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_My_Study.R")
```

Relative paths are resolved relative to the configuration file, not the current working directory.

A minimal outcome definition is:

```r
outcomes = data.frame(
  column = c("Outcome1", "Outcome2"),
  label = c("Outcome 1", "Outcome 2"),
  category = c("Performance", "Experience"),
  enabled = c(TRUE, TRUE),
  include_in_correlation = c(TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

- `enabled` controls ANOVA/ART-ANOVA analysis.
- `include_in_correlation` independently controls inclusion in the correlation matrix.

See the [complete usage guide](docs/USAGE_GUIDE.md) for the input formats and full configuration reference.

## Statistical workflow

For each enabled dependent variable, the engine:

1. validates the configured factors, levels, columns, and design cells;
2. converts the outcome to numeric and reports conversion issues;
3. removes rows missing the outcome or an enabled factor for that outcome analysis;
4. fits the complete model implied by the enabled factors;
5. tests residual normality using Shapiro–Wilk;
6. tests variance homogeneity using Levene's test;
7. selects ANOVA or ART-ANOVA according to the configuration;
8. exports all main effects and every interaction available for the enabled factor count;
9. calculates effect sizes;
10. runs main-effect follow-up analyses and, for multi-factor designs, interaction follow-up analyses;
11. calculates descriptive statistics;
12. optionally conducts the unified correlation analysis; and
13. writes the Excel workbook, figures PDF, logs, and diagnostics.

### Automatic ANOVA/ART-ANOVA selection

With the default setting:

```r
method_selection = "automatic"
```

ANOVA is selected when both assumption tests have `p >= alpha`. ART-ANOVA is selected when either assumption test has `p < alpha` or the parametric assumptions cannot be established.

The method can be forced with:

```r
method_selection = "anova"
```

or:

```r
method_selection = "art"
```

### Complete model for one to three factors

The engine always fits the complete model implied by all enabled factors:

```r
# One factor
Y ~ X1

# Two factors
Y ~ X1 * X2

# Three factors
Y ~ X1 * X2 * X3
```

A one-factor model contains the single main effect only. Two- and three-factor models additionally contain all possible interactions. The script does not suppress higher-order terms; the analyst decides which effects to emphasize in a manuscript.

### Correlation analysis

Correlation analysis is enabled by default. One common method is used for the complete matrix.

Pearson is selected only when every included variable:

- has at least the configured number of finite observations;
- has at least three unique finite values; and
- has a Shapiro–Wilk `p` value at or above `normality_alpha`.

If any included variable fails or cannot be evaluated, the complete matrix uses Spearman. Correlations are calculated from pairwise-complete observations, and the correlation *p* values are adjusted together using the configured correction.

In the heatmap:

- the lower triangle shows correlation coefficients;
- the upper triangle shows adjusted-*p* significance symbols; and
- diagonal cells are blank.

## Outputs

Unless `output$directory` is set, outputs are created next to the input file in:

```text
<input_file_stem>_analysis_results/
```

The main files are:

```text
<input_file_stem>_statistical_results.xlsx
<input_file_stem>_figures.pdf
```

Optional reproducibility files are stored in:

```text
logs/
art_diagnostics/
```

### Excel workbook

The workbook contains 25 logically ordered worksheets covering:

- run information and configuration;
- factor and outcome specifications;
- design-cell counts, conversion checks, and missing data;
- assumption tests and model summaries;
- descriptive statistics;
- omnibus effects and follow-up comparisons;
- correlation diagnostics, results, and matrices;
- PDF page indexing; and
- captured warnings and errors.

Every worksheet includes a right-side column-definition section. In one-factor analyses, interaction-specific worksheets are retained for a consistent workbook structure and report that no interaction results were generated.

### Figures PDF

For each dependent variable, the PDF contains:

- a main-effects page;
- an interaction-effects page when at least two factors are enabled;
- the method used for that dependent variable in the page title;
- mean ± SD or mean ± SE plots;
- omnibus *F*, *p*, and partial eta-squared annotations;
- significant main-effect comparison brackets; and
- captions summarizing interaction-contrast availability.

Each category begins with a title page and significance key. One-factor analyses contain main-effect pages only; interaction pages are created only for two- or three-factor designs. When correlation analysis is enabled, the correlation heatmap is appended to the PDF.

## Documentation

The full configuration reference, data-format requirements, output-sheet descriptions, adaptation walkthrough, and troubleshooting guidance are provided in:

**[docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md)**

## Scope and limitations

- The current engine supports one, two, or three enabled between-subject factors.
- It does not automatically fit repeated-measures or mixed-effects models.
- Automatic method selection is a predefined reproducible rule, not a substitute for inspecting distributions, residuals, sparse cells, and model appropriateness.
- ART effect sizes are calculated on aligned-rank responses and are labeled accordingly.
- The example datasets demonstrate the software workflow only.

## Citation

This repository accompanies the manuscript:

> *Yu Han, Hao Sha, Tongtai Cao, Xin Wang, Yu Miao, Yue Liu, Huyen Nguyen, and Christian Sandor, “Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”*

Complete bibliographic and BibTeX information can be added here after publication.
