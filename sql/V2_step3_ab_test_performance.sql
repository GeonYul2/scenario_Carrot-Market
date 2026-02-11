-- V2_step3_ab_test_performance.sql
-- STEP 3: 3-Arm AB Test 성과 측정 (Performance Measurement)

-- This query calculates the Apply Rate for each AB group and provides
-- necessary data for uplift measurement and statistical significance testing.

-- Assumptions:
-- The campaign sent date is '2023-10-26'.
-- 'is_applied' column indicates application (1) or not (0).

WITH GroupPerformance AS (
    SELECT
        ab_group,
        COUNT(DISTINCT user_id) AS total_users,
        SUM(CASE WHEN is_applied = 1 THEN 1 ELSE 0 END) AS applications,
        SUM(CASE WHEN is_applied = 0 THEN 1 ELSE 0 END) AS non_applications
    FROM
        campaign_logs
    WHERE
        sent_at = '2023-10-26' -- Filter for the specific campaign
    GROUP BY
        ab_group
)
SELECT
    gp.ab_group,
    gp.total_users,
    gp.applications,
    gp.non_applications,
    (gp.applications * 1.0 / gp.total_users) AS apply_rate,
    -- Calculate Uplift against Control group
    -- Note: This subquery assumes there is always a 'Control' group.
    (
        (gp.applications * 1.0 / gp.total_users) -
        (SELECT (applications * 1.0 / total_users) FROM GroupPerformance WHERE ab_group = 'Control')
    ) AS uplift_vs_control,
    -- Provide data for Chi-square test (Chi-square test typically performed in external tools)
    'For statistical significance, export these counts (applications, non_applications for each group) and perform a Chi-square test in a statistical software (e.g., Python with SciPy, R).' AS chi_square_guidance
FROM
    GroupPerformance gp
ORDER BY
    gp.ab_group;
