-- V2_step3_ab_test_performance.sql
-- STEP 3: 3-Arm AB Test Performance (High-Risk Target Only)

SET @campaign_date = '2023-10-26';

WITH UserSettlementHistory AS (
    SELECT
        s.user_id,
        u.total_settle_cnt,
        MAX(s.settled_at) AS last_settled_at,
        COUNT(s.st_id) AS actual_settle_count,
        DATEDIFF(MAX(s.settled_at), MIN(s.settled_at)) AS total_active_days
    FROM settlements s
    JOIN users u ON s.user_id = u.user_id
    GROUP BY s.user_id, u.total_settle_cnt
),
UserAvgSettleCycle AS (
    SELECT
        user_id,
        total_settle_cnt,
        CASE WHEN actual_settle_count > 1 THEN total_active_days / (actual_settle_count - 1) ELSE NULL END AS avg_settle_cycle_days,
        DATEDIFF(@campaign_date, last_settled_at) AS recency_days
    FROM UserSettlementHistory
),
UserSettleTiers AS (
    SELECT
        user_id,
        total_settle_cnt,
        avg_settle_cycle_days,
        recency_days,
        CASE
            WHEN total_settle_cnt = 1 THEN 'Light User'
            WHEN total_settle_cnt BETWEEN 2 AND 5 THEN 'Regular User'
            WHEN total_settle_cnt >= 6 THEN 'Power User'
            ELSE 'Undefined'
        END AS settle_tier
    FROM UserAvgSettleCycle
    WHERE avg_settle_cycle_days IS NOT NULL
),
SegmentedAvgCycleStats AS (
    SELECT
        settle_tier,
        MIN(CASE WHEN quartile_rank = 3 THEN avg_settle_cycle_days END) AS q3_avg_settle_cycle
    FROM (
        SELECT
            settle_tier,
            avg_settle_cycle_days,
            NTILE(4) OVER (PARTITION BY settle_tier ORDER BY avg_settle_cycle_days) AS quartile_rank
        FROM UserSettleTiers
    ) x
    GROUP BY settle_tier
),
HighRiskUsers AS (
    SELECT ust.user_id
    FROM UserSettleTiers ust
    JOIN SegmentedAvgCycleStats sas
      ON ust.settle_tier = sas.settle_tier
    WHERE ust.recency_days > sas.q3_avg_settle_cycle
),
UserLevelOutcome AS (
    SELECT
        cl.user_id,
        cl.ab_group,
        MAX(CASE WHEN cl.is_applied = 1 THEN 1 ELSE 0 END) AS is_applied
    FROM campaign_logs cl
    JOIN HighRiskUsers hr ON cl.user_id = hr.user_id
    WHERE cl.sent_at = @campaign_date
    GROUP BY cl.user_id, cl.ab_group
),
GroupPerformance AS (
    SELECT
        ab_group,
        COUNT(*) AS total_users,
        SUM(is_applied) AS applications,
        COUNT(*) - SUM(is_applied) AS non_applications
    FROM UserLevelOutcome
    GROUP BY ab_group
)
SELECT
    gp.ab_group,
    gp.total_users,
    gp.applications,
    gp.non_applications,
    (gp.applications * 1.0 / gp.total_users) AS apply_rate,
    (
        (gp.applications * 1.0 / gp.total_users) -
        (SELECT (applications * 1.0 / total_users) FROM GroupPerformance WHERE ab_group = 'Control')
    ) AS uplift_vs_control,
    'High-Risk filtered result. Use applications/non_applications for chi-square test.' AS chi_square_guidance
FROM GroupPerformance gp
ORDER BY gp.ab_group;
