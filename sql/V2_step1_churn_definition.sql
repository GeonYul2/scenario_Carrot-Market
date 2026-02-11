-- V2_step1_churn_definition.sql
-- STEP 1: Segmented IQR 기반 이탈자 정의

-- Assumptions:
-- The 'current date' for Recency calculation is the campaign send date (2023-10-26)
-- Data for users and settlements are available.

WITH UserLastSettlement AS (
    SELECT
        u.user_id,
        u.total_settle_cnt,
        MAX(s.settled_at) AS last_settled_at
    FROM
        users u
    JOIN
        settlements s ON u.user_id = s.user_id
    GROUP BY
        u.user_id, u.total_settle_cnt
),
UserRecency AS (
    SELECT
        user_id,
        total_settle_cnt,
        DATEDIFF('2023-10-26', last_settled_at) AS recency_days -- Recency in days from campaign send date
    FROM
        UserLastSettlement
),
RankedRecency AS (
    SELECT
        user_id,
        total_settle_cnt,
        recency_days,
        NTILE(4) OVER (PARTITION BY total_settle_cnt ORDER BY recency_days) as quartile_rank
    FROM
        UserRecency
),
SegmentedRecencyStats AS (
    SELECT
        total_settle_cnt,
        -- Q1: The value at the 25th percentile (minimum of the second quartile group)
        MIN(CASE WHEN quartile_rank = 2 THEN recency_days END) AS Q1,
        -- Q3: The value at the 75th percentile (minimum of the fourth quartile group)
        MIN(CASE WHEN quartile_rank = 4 THEN recency_days END) AS Q3
    FROM
        RankedRecency
    GROUP BY
        total_settle_cnt
)
SELECT
    ur.user_id,
    ur.total_settle_cnt,
    ur.recency_days,
    srs.Q1 AS Q1_Recency,
    srs.Q3 AS Q3_Recency,
    (srs.Q3 - srs.Q1) AS IQR,
    (srs.Q3 + (1.5 * (srs.Q3 - srs.Q1))) AS Churn_Limit,
    CASE
        WHEN ur.recency_days > (srs.Q3 + (1.5 * (srs.Q3 - srs.Q1))) THEN 'Churner'
        ELSE 'Non-Churner'
    END AS Churn_Status
FROM
    UserRecency ur
JOIN
    SegmentedRecencyStats srs ON ur.total_settle_cnt = srs.total_settle_cnt
WHERE srs.Q1 IS NOT NULL AND srs.Q3 IS NOT NULL -- Exclude segments where Q1 or Q3 could not be determined
ORDER BY
    ur.total_settle_cnt, ur.recency_days;
