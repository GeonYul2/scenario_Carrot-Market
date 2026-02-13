-- V2_step3_ab_test_performance.sql
-- STEP 3: 고위험군 + 실행 매칭 성립 유저 대상 3그룹 AB 성과 분석

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
-- [CTE] 실행 매칭 성립 유저 추출 (지역 + 시급 10%↑)
ExecutableMatchedUsers AS (
    SELECT DISTINCT ec.user_id
    FROM ExpandedCategory ec
    JOIN job_posts jp
      ON ec.category_to_match = jp.category_id
     AND ec.region_id = jp.region_id
     AND jp.hourly_rate >= (ec.last_final_hourly_rate * @min_wage_uplift_ratio)
),
-- [CTE] 사용자 단위 반응값(실행 매칭 유저만 포함)
UserLevelOutcome AS (
    SELECT
        cl.user_id,
        cl.ab_group,
        MAX(CASE WHEN cl.is_applied = 1 THEN 1 ELSE 0 END) AS is_applied
    FROM campaign_logs cl
    JOIN ExecutableMatchedUsers emu ON cl.user_id = emu.user_id
    WHERE cl.sent_at = @campaign_date
    GROUP BY cl.user_id, cl.ab_group
),
-- [CTE] 그룹별 집계
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
    '실행 매칭 유저 기준 결과. applications/non_applications로 카이제곱 또는 비율검정 수행' AS chi_square_guidance
FROM GroupPerformance gp
ORDER BY gp.ab_group;
