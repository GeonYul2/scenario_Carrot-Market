-- V2_step4_cohort_analysis.sql
-- STEP 4: 코호트 리텐션 분석 (Week1/2/4)
-- NOTE: Post 코호트는 실행 매칭 성립 유저 기준으로 제한한다.

SET @campaign_date = '2023-10-26';
SET @min_wage_uplift_ratio = 1.10;

WITH
-- [CTE] 사용자별 정산 히스토리
UserSettlementHistory AS (
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
-- [CTE] 평균 이용주기/최근성
UserAvgSettleCycle AS (
    SELECT
        user_id,
        total_settle_cnt,
        CASE WHEN actual_settle_count > 1 THEN total_active_days / (actual_settle_count - 1) ELSE NULL END AS avg_settle_cycle_days,
        DATEDIFF(@campaign_date, last_settled_at) AS recency_days
    FROM UserSettlementHistory
),
-- [CTE] 세그먼트 부여
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
-- [CTE] 세그먼트별 Q3
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
-- [CTE] 고위험군 추출
HighRiskUsers AS (
    SELECT ust.user_id
    FROM UserSettleTiers ust
    JOIN SegmentedAvgCycleStats sas ON ust.settle_tier = sas.settle_tier
    WHERE ust.recency_days > sas.q3_avg_settle_cycle
),
-- [CTE] 사용자 최근 정산 1건
UserLastSettlementInfo AS (
    SELECT
        s.user_id,
        s.category_id AS last_settle_category,
        s.final_hourly_rate AS last_final_hourly_rate,
        ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY s.settled_at DESC) AS rn
    FROM settlements s
    WHERE s.settled_at < @campaign_date
),
-- [CTE] 고위험군 기본 프로필
CurrentTargetUsers AS (
    SELECT
        u.user_id,
        u.region_id,
        lsi.last_settle_category,
        lsi.last_final_hourly_rate
    FROM users u
    JOIN UserLastSettlementInfo lsi ON u.user_id = lsi.user_id AND lsi.rn = 1
    JOIN HighRiskUsers hr ON u.user_id = hr.user_id
),
-- [CTE] 동일/유사 업종 확장
ExpandedCategory AS (
    SELECT
        ctu.user_id,
        ctu.region_id,
        ctu.last_settle_category,
        ctu.last_final_hourly_rate,
        ctu.last_settle_category AS category_to_match
    FROM CurrentTargetUsers ctu
    UNION ALL
    SELECT
        ctu.user_id,
        ctu.region_id,
        ctu.last_settle_category,
        ctu.last_final_hourly_rate,
        cm.similar_cat AS category_to_match
    FROM CurrentTargetUsers ctu
    JOIN category_map cm ON ctu.last_settle_category = cm.original_cat
),
-- [CTE] 실행 매칭 성립 유저 (Step3과 동일 기준)
ExecutableMatchedUsers AS (
    SELECT DISTINCT ec.user_id
    FROM ExpandedCategory ec
    JOIN job_posts jp
      ON ec.category_to_match = jp.category_id
     AND ec.region_id = jp.region_id
     AND jp.hourly_rate >= (ec.last_final_hourly_rate * @min_wage_uplift_ratio)
),
-- [CTE] Post 코호트: 발송일 수신자 중 실행 매칭 성립 유저
InitialCohort AS (
    SELECT DISTINCT
        cl.user_id,
        cl.sent_at AS cohort_start_date
    FROM campaign_logs cl
    JOIN ExecutableMatchedUsers emu ON cl.user_id = emu.user_id
    WHERE cl.sent_at = @campaign_date
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
-- [CTE] Post 코호트 리텐션 플래그
CampaignCohortRetention AS (
    SELECT
        'Post-Experiment Cohort' AS cohort_type,
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
