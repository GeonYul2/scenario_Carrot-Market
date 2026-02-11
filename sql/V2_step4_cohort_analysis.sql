-- V2_step4_cohort_analysis.sql
-- STEP 4: 장기 코호트 분석 (Long-term Cohort Analysis)

-- This query performs a long-term cohort analysis to track user retention
-- based on their activity (settlement or re-application) in subsequent weeks
-- after the campaign send date (Week 0).

-- Assumptions:
-- Campaign send date (Week 0 start) is '2023-10-26'.
-- A user "returns" if they have any settlement activity or re-apply (is_applied = 1)
-- in the specified weeks.

WITH InitialCohort AS (
    -- Identify all users who received the campaign
    SELECT DISTINCT
        user_id,
        sent_at AS cohort_start_date
    FROM
        campaign_logs
    WHERE
        sent_at = '2023-10-26'
),
UserActivity AS (
    -- Combine all relevant user activities for retention tracking
    SELECT
        user_id,
        settled_at AS activity_date
    FROM
        settlements
    UNION ALL
    SELECT
        user_id,
        sent_at AS activity_date
    FROM
        campaign_logs
    WHERE
        is_applied = 1 -- Only consider actual applications for activity
),
CohortRetention AS (
    SELECT
        ic.user_id,
        ic.cohort_start_date,
        MAX(CASE WHEN ua.activity_date BETWEEN '2023-10-27' AND '2023-11-02' THEN 1 ELSE 0 END) AS returned_week1, -- Week 1
        MAX(CASE WHEN ua.activity_date BETWEEN '2023-11-03' AND '2023-11-09' THEN 1 ELSE 0 END) AS returned_week2, -- Week 2
        MAX(CASE WHEN ua.activity_date BETWEEN '2023-11-17' AND '2023-11-23' THEN 1 ELSE 0 END) AS returned_week4  -- Week 4
    FROM
        InitialCohort ic
    LEFT JOIN
        UserActivity ua ON ic.user_id = ua.user_id AND ua.activity_date > ic.cohort_start_date
    GROUP BY
        ic.user_id, ic.cohort_start_date
)
SELECT
    COUNT(DISTINCT user_id) AS total_cohort_users,
    SUM(returned_week1) AS total_returned_week1,
    (SUM(returned_week1) * 1.0 / COUNT(DISTINCT user_id)) AS retention_rate_week1,
    SUM(returned_week2) AS total_returned_week2,
    (SUM(returned_week2) * 1.0 / COUNT(DISTINCT user_id)) AS retention_rate_week2,
    SUM(returned_week4) AS total_returned_week4,
    (SUM(returned_week4) * 1.0 / COUNT(DISTINCT user_id)) AS retention_rate_week4
FROM
    CohortRetention;
