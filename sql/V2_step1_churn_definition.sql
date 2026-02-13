-- V2_step1_churn_definition.sql
-- STEP 1: 고위험군 정의 (세그먼트별 Q3 임계값)

SET @campaign_date = '2023-10-26';

WITH
-- [CTE] 사용자별 정산 히스토리 집계
UserSettlementHistory AS (
    SELECT
        s.user_id,
        u.total_settle_cnt,
        MIN(s.settled_at) AS first_settled_at,
        MAX(s.settled_at) AS last_settled_at,
        COUNT(s.st_id) AS actual_settle_count,
        DATEDIFF(MAX(s.settled_at), MIN(s.settled_at)) AS total_active_days
    FROM settlements s
    JOIN users u ON s.user_id = u.user_id
    GROUP BY s.user_id, u.total_settle_cnt
),
-- [CTE] 평균 이용주기/최근성 계산
UserAvgSettleCycle AS (
    SELECT
        user_id,
        total_settle_cnt,
        last_settled_at,
        CASE WHEN actual_settle_count > 1 THEN total_active_days / (actual_settle_count - 1) ELSE NULL END AS avg_settle_cycle_days,
        DATEDIFF(@campaign_date, last_settled_at) AS recency_days
    FROM UserSettlementHistory
),
-- [CTE] 이용횟수 기반 세그먼트 부여
UserSettleTiers AS (
    SELECT
        user_id,
        total_settle_cnt,
        last_settled_at,
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
-- [CTE] 세그먼트별 평균 주기 Q3 산출
SegmentedAvgCycleStats AS (
    SELECT
        settle_tier,
        MIN(CASE WHEN quartile_rank = 3 THEN avg_settle_cycle_days END) AS Q3_avg_settle_cycle
    FROM (
        SELECT
            settle_tier,
            avg_settle_cycle_days,
            NTILE(4) OVER (PARTITION BY settle_tier ORDER BY avg_settle_cycle_days) AS quartile_rank
        FROM UserSettleTiers
    ) RankedAvgCycle
    GROUP BY settle_tier
)
-- [최종] recency > Q3면 고위험군
SELECT
    ust.user_id,
    ust.total_settle_cnt,
    ust.settle_tier,
    ust.last_settled_at,
    ust.recency_days,
    ust.avg_settle_cycle_days,
    sas.Q3_avg_settle_cycle,
    CASE WHEN ust.recency_days > sas.Q3_avg_settle_cycle THEN 'High-Risk Candidate' ELSE 'Normal User' END AS user_segment_status
FROM UserSettleTiers ust
JOIN SegmentedAvgCycleStats sas ON ust.settle_tier = sas.settle_tier
ORDER BY ust.total_settle_cnt, ust.recency_days;
