-- V2_step2_personalization_matching.sql
-- STEP 2: Personalization Potential Matching (High-Risk Universe)
-- Note: This query is for diagnostic potential pool.
--       Executable A/B send pool is in `V2_step2b_personalization_matching_executable.sql`.

SET @campaign_date = '2023-10-26';
SET @min_wage_uplift_ratio = 1.10; -- >= 10% wage uplift vs last settled wage

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
UserLastSettlementInfo AS (
    SELECT
        s.user_id,
        s.category_id AS last_settle_category,
        s.final_hourly_rate AS last_final_hourly_rate,
        ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY s.settled_at DESC) AS rn
    FROM settlements s
    WHERE s.settled_at < @campaign_date
),
CurrentTargetUsers AS (
    SELECT
        u.user_id,
        u.region_id,
        lsi.last_settle_category,
        lsi.last_final_hourly_rate
    FROM users u
    JOIN UserLastSettlementInfo lsi
      ON u.user_id = lsi.user_id
     AND lsi.rn = 1
    JOIN HighRiskUsers hr
      ON u.user_id = hr.user_id
),
ExpandedCategory AS (
    SELECT
        ctu.user_id,
        ctu.region_id,
        ctu.last_settle_category,
        ctu.last_final_hourly_rate,
        ctu.last_settle_category AS category_to_match,
        'same_category' AS match_basis
    FROM CurrentTargetUsers ctu
    UNION ALL
    SELECT
        ctu.user_id,
        ctu.region_id,
        ctu.last_settle_category,
        ctu.last_final_hourly_rate,
        cm.similar_cat AS category_to_match,
        'similar_category' AS match_basis
    FROM CurrentTargetUsers ctu
    JOIN category_map cm
      ON ctu.last_settle_category = cm.original_cat
),
MatchedCandidates AS (
    SELECT DISTINCT
        ec.user_id,
        ec.region_id,
        ec.last_settle_category,
        ec.last_final_hourly_rate,
        ec.match_basis,
        jp.job_id,
        jp.category_id AS recommended_job_category,
        jp.hourly_rate AS recommended_hourly_rate,
        (jp.hourly_rate - ec.last_final_hourly_rate) AS wage_uplift
    FROM ExpandedCategory ec
    JOIN job_posts jp
      ON ec.category_to_match = jp.category_id
     AND ec.region_id = jp.region_id
     AND jp.hourly_rate >= (ec.last_final_hourly_rate * @min_wage_uplift_ratio)
),
DeduplicatedCandidates AS (
    SELECT
        mc.*,
        ROW_NUMBER() OVER (
            PARTITION BY mc.user_id, mc.job_id
            ORDER BY CASE WHEN mc.match_basis = 'same_category' THEN 1 ELSE 2 END, mc.wage_uplift DESC
        ) AS rn
    FROM MatchedCandidates mc
)
SELECT
    user_id,
    region_id,
    last_settle_category,
    last_final_hourly_rate,
    match_basis,
    job_id,
    recommended_job_category,
    recommended_hourly_rate,
    wage_uplift
FROM DeduplicatedCandidates
WHERE rn = 1
ORDER BY user_id, wage_uplift DESC, job_id;
