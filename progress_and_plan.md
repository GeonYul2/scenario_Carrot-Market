# Progress and Plan for CRM Re-activation Analysis Refactoring

This document summarizes the current progress and outlines the next steps for refactoring the CRM re-activation analysis pipeline, specifically focusing on the "high-risk user" definition.

## Current Status:

*   **SQL Logic (`sql/V2_step1_churn_definition.sql`):**
    *   The SQL script has been updated with the refined "활동 빈도 기반 고위험군(재활성화 대상) 정의" logic. This new logic segments users by `total_settle_cnt` tiers, calculates each user's average settlement cycle, and defines "High-Risk Candidates" based on their current `Recency` exceeding the Q3 of their segment's average settlement cycle distribution.
*   **Python Simulation Script (`scripts/get_high_risk_output.py`):**
    *   A Python script (`scripts/get_high_risk_output.py`) was created to simulate the new SQL logic using Pandas on the CSV data. Its purpose is to generate the "실제 분석 결과 예시" for the documentation.
    *   **Current Issue:** This script is currently experiencing a `TypeError` during date subtraction (`TypeError: unsupported operand type(s) for -: 'DatetimeArray' and 'datetime.date'`). This is due to a mismatch between Pandas `Timestamp` objects and Python's native `datetime.date` objects during calculation of `recency_days`.
*   **Documentation (`docs/analysis_scenario.md`, `docs/how_to_run_analysis.md`):**
    *   STEP 1 in both documents *still needs to be fully updated* with the new SQL snippet and the corrected "실제 분석 결과 예시" output, once the Python simulation script is debugged and provides valid output.

## Next Steps:

1.  **Debug `scripts/get_high_risk_output.py`:**
    *   **Problem:** The `TypeError` occurs because `CAMPAIGN_DATE` (currently a Python `datetime.date` object) is being subtracted from `user_avg_settle_cycle['last_settled_at']` (a Pandas `Timestamp` Series). Pandas does not implicitly handle this mix of types as expected.
    *   **Fix:** The `CAMPAIGN_DATE` variable in the Python script needs to be explicitly converted to a Pandas `Timestamp` object (`pd.to_datetime(CAMPAIGN_DATE_STR)`) to ensure compatibility with other Pandas datetime operations.
2.  **Run Debugged `scripts/get_high_risk_output.py`:**
    *   Execute the corrected Python script to get the accurate "실제 분석 결과 예시" (actual analysis example) output for the new high-risk definition logic.
3.  **Update `docs/analysis_scenario.md` (STEP 1):**
    *   Replace the old SQL snippet (currently in the Markdown file) with the new SQL logic (which is now in `sql/V2_step1_churn_definition.sql`).
    *   Update the "실제 분석 결과 예시" section with the output obtained from step 2.
    *   Refine the interpretation of the results to clearly explain the new high-risk definition and its implications.
4.  **Update `docs/how_to_run_analysis.md` (STEP 1):**
    *   Replace the old SQL snippet (currently in the Markdown file) with the new SQL logic.
    *   Update the "결과 해석" section with the output from step 2 and a refined interpretation.
5.  **Clean up:**
    *   Remove the temporary Python script `scripts/get_high_risk_output.py`.

This plan ensures that all components (SQL, simulation, and documentation) are fully synchronized and correctly reflect the user's refined business logic for identifying high-risk users.
