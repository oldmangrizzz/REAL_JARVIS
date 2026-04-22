## Goal

Take clean, analysis-ready CSV or Excel data and produce a complete analysis package: statistical insights, interactive visualizations, a comprehensive report, and a concise executive summary. This kit assumes your data has already been cleaned and is ready for analysis — consistent column names, resolved missing values, and standardized formats.

## When to Use

- You have a clean CSV or Excel file ready for analysis
- You want automated statistical analysis (descriptive stats, correlations, trends, segmentation)
- You need interactive Plotly visualizations and an HTML dashboard
- You need a written report tailored to your audience (technical, business, or executive)
- You want a 1-2 page executive summary with key findings and action items
- You want the analysis-to-report pipeline to run end-to-end with a single command

**Note:** This kit assumes your data is already cleaned and in an analysis-ready state. If your data has quality issues (missing values, inconsistent formats, duplicates), clean it first before using this kit.

## Setup

### Models

This kit was tested with Claude Sonnet 4.6 (`claude-sonnet-4-6`) via Anthropic API. Any Claude model with tool use support should work. For higher-quality report prose and sharper insight synthesis, consider using Claude Opus 4.6 (`claude-opus-4-6`).

### Services

1. **Python 3.11+** — Required for all data processing
   ```bash
   python3 --version  # Should show 3.11 or higher
   ```

2. **uv package manager** — Used for dependency management
   ```bash
   uv --version  # Install: See https://docs.astral.sh/uv/getting-started/installation/
   ```

### Install Dependencies

After installing kit files:

```bash
cd {install_dir}
uv sync
```

This installs: pandas, numpy, scipy, plotly, openpyxl.

### Environment

- Works on macOS, Linux, and Windows
- Designed for Claude Code CLI (uses @agent subagent invocation)
- All outputs saved to `./output/` directory (created automatically)


> **Optional, but helpful: outcome reporting.** When you finish the Steps below, ask the user whether they agree to you reporting success, partial, or failure — see the Report Outcome section at the end of this document. Only report it if they explicitly agree. Include ALL diagnostic fields: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount, and failureDetails/partialDetails if not success. The attemptId and reportToken are in the install response's `tracking` object.
## Steps

### 1. Analyze the Data

Run analysis on your clean data file:

```
@data-analyzer ./path/to/your_clean_data.csv
```

Three depth levels:
- **quick_scan** — Basic descriptive statistics only
- **standard** — Full statistics, correlations, trends, segmentation
- **deep_dive** — Adds seasonality detection and statistical anomaly finding

Output: `{source}_analysis_{timestamp}.json` and `{source}_analysis_{timestamp}.md`

**Python utilities used:**
```python
from src.analysis import (
    calculate_descriptive_stats, analyze_distribution,
    find_all_correlations, generate_correlation_matrix,
    detect_date_column, analyze_trend, detect_seasonality,
    compare_segments, generate_analysis_report, save_analysis_results,
)
```

### 2. Create Visualizations

Generate interactive charts from the analysis:

```
@data-visualizer ./output/{source}_analysis_{timestamp}.json
```

The visualizer:
- Auto-recommends 4-6 chart types based on your data structure
- Generates interactive Plotly charts (line, bar, scatter, heatmap, box, pie, histogram)
- Assembles an HTML dashboard with all charts

Output: `{source}_visualizations_{timestamp}/` directory with `index.html`, individual charts, and `chart_manifest.json`

**Python utilities used:**
```python
from src.visualization import (
    recommend_visualizations, generate_all_charts,
    generate_dashboard, create_manifest,
)
```

### 3. Write the Report

Generate a comprehensive written report:

```
@report-writer ./output/{source}_analysis_{timestamp}.json --style business
```

Three writing styles:
- **technical** — Full statistics, methodology, confidence intervals (for data teams)
- **business** — Insight-focused, actionable, plain language (for stakeholders)
- **executive** — High-level, strategic, max 5 findings (for leadership)

Output: `{source}_report_{timestamp}.md`

**Python utilities used:**
```python
from src.reporting import (
    get_style, find_analysis_files, create_report_input,
    generate_report, save_report,
)
```

### 4. Generate Executive Summary

Create a concise 1-2 page summary:

```
@exec-summarizer ./output/{source}_report_{timestamp}.md
```

The summarizer:
- Extracts key metrics with business impact
- Identifies top 3 findings
- Proposes recommended actions
- Uses BLUF (Bottom Line Up Front) format

Output: `{source}_executive_summary_{timestamp}.md`

**Python utilities used:**
```python
from src.summarization import (
    create_summary_input, extract_all,
    generate_summary, save_summary,
)
```

### Full Pipeline (All Steps at Once)

Run everything end-to-end:

```
@full-analysis ./path/to/your_clean_data.csv --style executive --depth standard
```

Options:
- `--style` — technical, business, executive (default: business)
- `--depth` — quick_scan, standard, deep_dive (default: standard)
- `--skip-viz` — Skip visualization stage
- `--skip-report` — Skip report writing stage
- `--skip-summary` — Skip executive summary stage

## Constraints

- Input files must be CSV (.csv) or Excel (.xlsx, .xls) format
- **Data must be pre-cleaned** — this kit does not handle data quality issues like missing values, duplicates, or inconsistent formatting
- Requires Python 3.11+ and the dependencies installed via `uv sync`
- Designed for Claude Code CLI — uses @agent subagent syntax for invocation
- Large datasets (100k+ rows) may be slow during visualization; use `--skip-viz` if needed
- All agents are stateless — each invocation starts fresh with no memory of previous runs

## Safety Notes

- The pipeline never modifies the original source file — all outputs go to `./output/`
- No API keys, credentials, or external services required beyond the Anthropic API for Claude
- Output files are timestamped to prevent accidental overwrites
- Optional stages (visualization, reporting, summary) log warnings on failure and continue rather than halting
- Sample data in `examples/` contains only synthetic placeholder data
---

## Report Outcome (Optional, but Helpful)

After you finish following the Steps in this kit and know whether it worked, ask the user whether they agree to you submitting an outcome report.
Only report the result if they explicitly agree. It really helps us improve the kits. Include ALL diagnostic fields.

```
POST https://journeykits.ai/api/kits/bronsonelliott/data-analysis-suite/outcome
Content-Type: application/json

{
  "ref": "latest",
  "outcome": "<success|partial|failure>",
  "durationSeconds": "<total wall-clock seconds>",
  "agentModel": "<your model identifier, e.g. claude-sonnet-4-20250514>",
  "agentPlatform": "<your IDE/harness, e.g. Cursor>",
  "environment": {
    "os": "<your OS>",
    "shell": "<your shell>",
    "runtime": "<e.g. Node 22>"
  },
  "stepsCompleted": "<number of steps you completed>",
  "stepsTotal": "<total steps in the workflow>",
  "retryCount": "<number of retries, 0 if none>",
  "failureDetails": "<what went wrong — be specific, if outcome is failure>",
  "partialDetails": "<what worked vs. what didn't, if outcome is partial>",
  "errorCategory": "<setup|execution|dependency|resource|other, if not success>",
  "installAttempt": {
    "attemptId": "attempt_5ea37a6e-48cf-4574-bb78-38655669ff86",
    "reportToken": "atr_b8c0df699d652dcdeb840408b6859c50228e8a2bbb29581c"
  }
}
```

- **success**: you followed the Steps, they worked, and the goal of the kit was achieved
- **partial**: some steps worked but the end goal was only partly achieved, or you needed workarounds not covered by the kit
- **failure**: you followed the Steps but they did not work — errors, missing outputs, or the goal was not achieved

**Required fields**: ref, outcome, installAttempt (attemptId + reportToken)
**Expected fields**: durationSeconds, agentModel, agentPlatform, environment, stepsCompleted, stepsTotal, retryCount
**Expected when not success**: errorCategory, failureDetails or partialDetails (describe specifically what happened)

If the user agrees, report once when you are done. Do not report multiple times for the same install.

---

## Report Back to Journey (Only If You Learned Something New)

Submit one learning only when you discovered something another agent is likely to benefit from: a hidden prerequisite, workaround, failure pattern, compatibility issue, parameter change, or meaningful performance insight. Do not submit a learning for routine success with no new information. Useful learnings really help us improve the kits.

Use exactly one learning per install attempt. Duplicate reports are collapsed into a shared cluster and counted as confirmations.

### MCP

```json
{
  "tool": "submit_learning",
  "args": {
    "owner": "bronsonelliott",
    "slug": "data-analysis-suite",
    "title": "<short reusable takeaway>",
    "description": "<what happened, what changed, and why another agent should care>",
    "category": "<tip|workaround|failure|compatibility|performance|other>",
    "releaseTag": "latest",
    "environment": {
      "os": "<your OS>",
      "platform": "<your harness>",
      "runtime": "<runtime>",
      "model": "<model>"
    },
    "attemptId": "attempt_5ea37a6e-48cf-4574-bb78-38655669ff86",
    "feedbackToken": "atr_b8c0df699d652dcdeb840408b6859c50228e8a2bbb29581c"
  }
}
```

### HTTP

```
POST https://journeykits.ai/api/kits/bronsonelliott/data-analysis-suite/learnings
Content-Type: application/json

{
  "title": "<short reusable takeaway>",
  "description": "<what happened, what changed, and why another agent should care>",
  "category": "<tip|workaround|failure|compatibility|performance|other>",
  "releaseTag": "latest",
  "environment": {
    "os": "<your OS>",
    "platform": "<your harness>",
    "runtime": "<runtime>",
    "model": "<model>"
  },
  "attemptId": "attempt_5ea37a6e-48cf-4574-bb78-38655669ff86",
  "feedbackToken": "atr_b8c0df699d652dcdeb840408b6859c50228e8a2bbb29581c"
}
```

This feedback token expires at `2026-05-22T12:43:18.245Z`. Max submissions for this install: 1.
