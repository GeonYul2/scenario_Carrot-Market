-- V2_step2_personalization_matching.sql
-- STEP 2: 개인화 매칭 로직 (Recommendation logic)

-- This query identifies personalized job recommendations for target users
-- based on their past settlement history and job post criteria.

-- Assumptions:
-- 'Target users' are those identified as potential churners or users to be reactivated.
-- For simplicity, this query will consider all users who have at least one settlement
-- as potential targets for personalized matching.
-- Campaign send date is '2023-10-26'.

WITH UserLastSettlementInfo AS (
    SELECT
        s.user_id,
        s.category_id AS last_settle_category,
        s.final_hourly_rate AS last_final_hourly_rate,
        ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY s.settled_at DESC) as rn
    FROM
        settlements s
    WHERE
        s.settled_at < '2023-10-26' -- Consider settlements before the campaign date
),
CurrentTargetUsers AS (
    SELECT
        user_id,
        last_settle_category,
        last_final_hourly_rate
    FROM
        UserLastSettlementInfo
    WHERE rn = 1 -- Get the most recent settlement info for each user
),
UserCategoryPreferences AS (
    SELECT
        ctu.user_id,
        ctu.last_settle_category,
        ctu.last_final_hourly_rate,
        cm.similar_cat AS preferred_job_category
    FROM
        CurrentTargetUsers ctu
    LEFT JOIN
        category_map cm ON ctu.last_settle_category = cm.original_cat
),
ExpandedUserCategoryPreferences AS (
    -- Combine original last settled category and similar categories
    SELECT user_id, last_settle_category, last_final_hourly_rate, last_settle_category AS category_to_match FROM UserCategoryPreferences
    UNION ALL
    SELECT user_id, last_settle_category, last_final_hourly_rate, preferred_job_category AS category_to_match FROM UserCategoryPreferences WHERE preferred_job_category IS NOT NULL
)
SELECT DISTINCT
    eucp.user_id,
    eucp.last_settle_category,
    eucp.last_final_hourly_rate,
    jp.job_id,
    jp.category_id AS recommended_job_category,
    jp.hourly_rate AS recommended_hourly_rate,
    jp.region_id,
    jp.posted_at
FROM
    ExpandedUserCategoryPreferences eucp
JOIN
    job_posts jp ON eucp.category_to_match = jp.category_id
WHERE
    jp.hourly_rate > eucp.last_final_hourly_rate
ORDER BY
    eucp.user_id, jp.hourly_rate DESC;
