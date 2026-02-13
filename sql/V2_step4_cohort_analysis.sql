-- V2_step4_cohort_analysis.sql
-- STEP 4: 코호트 리텐션 분석 (Week1/2/4)

SET @campaign_date = '2023-10-26';

WITH
-- [CTE] 캠페인 수신자 코호트
InitialCohort AS (
    SELECT DISTINCT
        user_id,
        sent_at AS cohort_start_date
    FROM campaign_logs
    WHERE sent_at = @campaign_date
),
-- [CTE] 비교용 선행 코호트(캠페인 비수신 + 다회 정산 이력)
PreCampaignMultiSettleCohort AS (
    SELECT
        u.user_id,
        MAX(s.settled_at) AS cohort_start_date
    FROM users u
    JOIN settlements s ON u.user_id = s.user_id
    LEFT JOIN campaign_logs cl ON u.user_id = cl.user_id AND cl.sent_at = @campaign_date
    WHERE u.total_settle_cnt > 1
      AND s.settled_at < @campaign_date
      AND cl.user_id IS NULL
    GROUP BY u.user_id
),
-- [CTE] 활동 이벤트 통합 (정산 + 지원)
UserActivity AS (
    SELECT user_id, settled_at AS activity_date
    FROM settlements
    UNION ALL
    SELECT user_id, sent_at AS activity_date
    FROM campaign_logs
    WHERE is_applied = 1
),
-- [CTE] 캠페인 코호트 리텐션 플래그
CampaignCohortRetention AS (
    SELECT
        'Post-Personalization Cohort' AS cohort_type,
        ic.user_id,
        ic.cohort_start_date,
        MAX(CASE WHEN ua.activity_date BETWEEN (ic.cohort_start_date + INTERVAL 1 DAY) AND (ic.cohort_start_date + INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS returned_week1,
        MAX(CASE WHEN ua.activity_date BETWEEN (ic.cohort_start_date + INTERVAL 8 DAY) AND (ic.cohort_start_date + INTERVAL 14 DAY) THEN 1 ELSE 0 END) AS returned_week2,
        MAX(CASE WHEN ua.activity_date BETWEEN (ic.cohort_start_date + INTERVAL 22 DAY) AND (ic.cohort_start_date + INTERVAL 28 DAY) THEN 1 ELSE 0 END) AS returned_week4
    FROM InitialCohort ic
    LEFT JOIN UserActivity ua ON ic.user_id = ua.user_id AND ua.activity_date > ic.cohort_start_date
    GROUP BY ic.user_id, ic.cohort_start_date
),
-- [CTE] 선행 코호트 리텐션 플래그
PreCampaignCohortRetention AS (
    SELECT
        'Pre-Personalization Cohort' AS cohort_type,
        pc.user_id,
        pc.cohort_start_date,
        MAX(CASE WHEN ua.activity_date BETWEEN (pc.cohort_start_date + INTERVAL 1 DAY) AND (pc.cohort_start_date + INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS returned_week1,
        MAX(CASE WHEN ua.activity_date BETWEEN (pc.cohort_start_date + INTERVAL 8 DAY) AND (pc.cohort_start_date + INTERVAL 14 DAY) THEN 1 ELSE 0 END) AS returned_week2,
        MAX(CASE WHEN ua.activity_date BETWEEN (pc.cohort_start_date + INTERVAL 22 DAY) AND (pc.cohort_start_date + INTERVAL 28 DAY) THEN 1 ELSE 0 END) AS returned_week4
    FROM PreCampaignMultiSettleCohort pc
    LEFT JOIN UserActivity ua ON pc.user_id = ua.user_id AND ua.activity_date > pc.cohort_start_date
    GROUP BY pc.user_id, pc.cohort_start_date
),
-- [CTE] 코호트 통합
CombinedCohortRetention AS (
    SELECT cohort_type, user_id, cohort_start_date, returned_week1, returned_week2, returned_week4
    FROM CampaignCohortRetention
    UNION ALL
    SELECT cohort_type, user_id, cohort_start_date, returned_week1, returned_week2, returned_week4
    FROM PreCampaignCohortRetention
)
SELECT
    ccr.cohort_type,
    COUNT(DISTINCT ccr.user_id) AS total_cohort_users,
    SUM(ccr.returned_week1) AS total_returned_week1,
    (SUM(ccr.returned_week1) * 1.0 / COUNT(DISTINCT ccr.user_id)) AS retention_rate_week1,
    SUM(ccr.returned_week2) AS total_returned_week2,
    (SUM(ccr.returned_week2) * 1.0 / COUNT(DISTINCT ccr.user_id)) AS retention_rate_week2,
    SUM(ccr.returned_week4) AS total_returned_week4,
    (SUM(ccr.returned_week4) * 1.0 / COUNT(DISTINCT ccr.user_id)) AS retention_rate_week4
FROM CombinedCohortRetention ccr
GROUP BY ccr.cohort_type
ORDER BY ccr.cohort_type;
