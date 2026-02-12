-- V2_step1_churn_definition.sql
-- STEP 1: 활동 빈도 기반 고위험군(재활성화 대상) 정의

-- 이 쿼리는 사용자의 총 정산 횟수(total_settle_cnt)를 기반으로 세그먼트를 나누고,
-- 각 사용자별 '평균 정산 주기' 분포를 분석하여 '평소보다 비활동적인 상태'인 고위험군을 정의합니다.

-- 캠페인 분석 기준일 설정
SET @campaign_date = '2023-10-26';

-- 1. 사용자별 정산 이력 및 활동 기간 계산
WITH UserSettlementHistory AS (
    SELECT
        s.user_id,
        u.total_settle_cnt,
        MIN(s.settled_at) AS first_settled_at,
        MAX(s.settled_at) AS last_settled_at,
        COUNT(s.st_id) AS actual_settle_count,
        DATEDIFF(MAX(s.settled_at), MIN(s.settled_at)) AS total_active_days -- 첫 정산부터 마지막 정산까지의 기간
    FROM
        settlements s
    JOIN
        users u ON s.user_id = u.user_id
    GROUP BY
        s.user_id, u.total_settle_cnt
),
-- 2. 사용자별 '평균 정산 주기' 계산
-- (총 활동 기간 / (실제 정산 횟수 - 1)). 정산 횟수가 1인 경우는 주기를 계산할 수 없음.
UserAvgSettleCycle AS (
    SELECT
        user_id,
        total_settle_cnt,
        last_settled_at,
        CASE
            WHEN actual_settle_count > 1 THEN total_active_days / (actual_settle_count - 1)
            ELSE NULL -- 정산 횟수가 1회인 사용자는 평균 주기 계산 불가
        END AS avg_settle_cycle_days,
        DATEDIFF(@campaign_date, last_settled_at) AS recency_days -- 현재 Recency 계산
    FROM
        UserSettlementHistory
),
-- 3. 'total_settle_cnt' 분포를 기반으로 사용자 세그먼트 (티어) 정의
-- 예시: 1회 정산 사용자는 'Light', 2-5회는 'Regular', 6회 이상은 'Power'
-- 실제 분포에 따라 기준 조정 필요. 여기서는 예시로 나눔.
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
            ELSE 'Undefined' -- 혹시 모를 경우를 대비
        END AS settle_tier
    FROM
        UserAvgSettleCycle
    WHERE
        avg_settle_cycle_days IS NOT NULL -- 평균 주기 계산 가능한 사용자만 대상
),
-- 4. 각 'settle_tier'별 '평균 정산 주기' 분포의 Q3 계산
SegmentedAvgCycleStats AS (
    SELECT
        settle_tier,
        MIN(CASE WHEN quartile_rank = 3 THEN avg_settle_cycle_days END) AS Q3_avg_settle_cycle -- 3분위수
    FROM (
        SELECT
            settle_tier,
            avg_settle_cycle_days,
            NTILE(4) OVER (PARTITION BY settle_tier ORDER BY avg_settle_cycle_days) as quartile_rank
        FROM
            UserSettleTiers
    ) AS RankedAvgCycle
    GROUP BY
        settle_tier
)
-- 5. 고위험군 (재활성화 대상) 정의
SELECT
    ust.user_id,
    ust.total_settle_cnt,
    ust.settle_tier,
    ust.last_settled_at,
    ust.recency_days,
    ust.avg_settle_cycle_days,
    sas.Q3_avg_settle_cycle,
    CASE
        -- 현재 Recency가 해당 세그먼트의 Q3_avg_settle_cycle을 초과하면 고위험군
        WHEN ust.recency_days > sas.Q3_avg_settle_cycle THEN 'High-Risk Candidate'
        ELSE 'Normal User'
    END AS User_Segment_Status
FROM
    UserSettleTiers ust
JOIN
    SegmentedAvgCycleStats sas ON ust.settle_tier = sas.settle_tier
ORDER BY
    ust.total_settle_cnt, ust.recency_days;