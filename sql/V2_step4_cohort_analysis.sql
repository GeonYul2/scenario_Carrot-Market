-- V2_step4_cohort_analysis.sql
-- STEP 4: 장기 코호트 분석

-- 이 쿼리는 캠페인 발송일(0주차) 이후 사용자 활동(정산 또는 재지원)을 기반으로
-- 사용자 잔존율을 추적하는 장기 코호트 분석을 수행합니다.

-- 가정:
-- 캠페인 발송일 (0주차 시작일)은 '2023-10-26'입니다.
-- 사용자는 명시된 주차에 정산 활동이 있거나 재지원(is_applied = 1)하면 '복귀(returned)'한 것으로 간주합니다.

-- 캠페인 분석 기준일 설정
SET @campaign_date = '2023-10-26';

WITH InitialCohort AS (
    -- 캠페인을 수신한 모든 사용자를 식별합니다. (개인화 이후 코호트)
    SELECT DISTINCT
        user_id,
        sent_at AS cohort_start_date
    FROM
        campaign_logs
    WHERE
        sent_at = @campaign_date
),
PreCampaignMultiSettleCohort AS (
    -- 캠페인 발송일 이전에 여러 번 정산 이력이 있고, 캠페인 발송일에 캠페인을 받지 않은 사용자 코호트 (개인화 이전 기준선/대조군)
    SELECT
        u.user_id,
        MAX(s.settled_at) AS cohort_start_date -- 마지막 정산일을 코호트 시작일로 간주
    FROM
        users u
    JOIN
        settlements s ON u.user_id = s.user_id
    LEFT JOIN
        campaign_logs cl ON u.user_id = cl.user_id AND cl.sent_at = @campaign_date
    WHERE
        u.total_settle_cnt > 1
        AND s.settled_at < @campaign_date
        AND cl.user_id IS NULL -- 캠페인을 받지 않은 사용자
    GROUP BY
        u.user_id
),
UserActivity AS (
    -- 잔존율 추적을 위한 모든 관련 사용자 활동을 결합합니다.
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
        is_applied = 1 -- 실제 지원 활동만 고려
),
CampaignCohortRetention AS (
    -- 캠페인 수신 코호트 (InitialCohort, 개인화 이후 코호트)에 대한 주차별 잔존 여부를 확인합니다.
    SELECT
        'Post-Personalization Cohort' AS cohort_type, -- 코호트 유형 지정
        ic.user_id,
        ic.cohort_start_date,
        MAX(CASE WHEN ua.activity_date BETWEEN (@campaign_date + INTERVAL 1 DAY) AND (@campaign_date + INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS returned_week1, -- 1주차
        MAX(CASE WHEN ua.activity_date BETWEEN (@campaign_date + INTERVAL 8 DAY) AND (@campaign_date + INTERVAL 14 DAY) THEN 1 ELSE 0 END) AS returned_week2, -- 2주차
        MAX(CASE WHEN ua.activity_date BETWEEN (@campaign_date + INTERVAL 22 DAY) AND (@campaign_date + INTERVAL 28 DAY) THEN 1 ELSE 0 END) AS returned_week4  -- 4주차
    FROM
        InitialCohort ic
    LEFT JOIN
        UserActivity ua ON ic.user_id = ua.user_id AND ua.activity_date > ic.cohort_start_date
    GROUP BY
        ic.user_id, ic.cohort_start_date
),
PreCampaignCohortRetention AS (
    -- 캠페인 이전 다중 정산 코호트 (PreCampaignMultiSettleCohort, 개인화 이전 기준선/대조군)에 대한 주차별 잔존 여부를 확인합니다.
    SELECT
        'Pre-Personalization Cohort' AS cohort_type,
        pc.user_id,
        pc.cohort_start_date,
        MAX(CASE WHEN ua.activity_date BETWEEN (@campaign_date + INTERVAL 1 DAY) AND (@campaign_date + INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS returned_week1, -- 1주차
        MAX(CASE WHEN ua.activity_date BETWEEN (@campaign_date + INTERVAL 8 DAY) AND (@campaign_date + INTERVAL 14 DAY) THEN 1 ELSE 0 END) AS returned_week2, -- 2주차
        MAX(CASE WHEN ua.activity_date BETWEEN (@campaign_date + INTERVAL 22 DAY) AND (@campaign_date + INTERVAL 28 DAY) THEN 1 ELSE 0 END) AS returned_week4  -- 4주차
    FROM
        PreCampaignMultiSettleCohort pc
    LEFT JOIN
        UserActivity ua ON pc.user_id = ua.user_id AND ua.activity_date > pc.cohort_start_date
    GROUP BY
        pc.user_id, pc.cohort_start_date
)
CombinedCohortRetention AS (
    -- 캠페인 수신 코호트와 캠페인 이전 다중 정산 코호트를 통합합니다.
    SELECT cohort_type, user_id, cohort_start_date, returned_week1, returned_week2, returned_week4 FROM CampaignCohortRetention
    UNION ALL
    SELECT cohort_type, user_id, cohort_start_date, returned_week1, returned_week2, returned_week4 FROM PreCampaignCohortRetention
)
SELECT
    ccr.cohort_type, -- 코호트 유형
    COUNT(DISTINCT ccr.user_id) AS total_cohort_users, -- 총 코호트 사용자 수
    SUM(ccr.returned_week1) AS total_returned_week1,   -- 1주차 복귀 사용자 수
    (SUM(ccr.returned_week1) * 1.0 / COUNT(DISTINCT ccr.user_id)) AS retention_rate_week1, -- 1주차 잔존율
    SUM(ccr.returned_week2) AS total_returned_week2,   -- 2주차 복귀 사용자 수
    (SUM(ccr.returned_week2) * 1.0 / COUNT(DISTINCT ccr.user_id)) AS retention_rate_week2, -- 2주차 잔존율
    SUM(ccr.returned_week4) AS total_returned_week4,   -- 4주차 복귀 사용자 수
    (SUM(ccr.returned_week4) * 1.0 / COUNT(DISTINCT ccr.user_id)) AS retention_rate_week4  -- 4주차 잔존율
FROM
    CombinedCohortRetention ccr
GROUP BY
    ccr.cohort_type
ORDER BY
    ccr.cohort_type;
