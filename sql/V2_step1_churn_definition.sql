-- V2_step1_churn_definition.sql
-- STEP 1: 세그먼트화된 IQR 기반의 재활성화 대상 정의

-- 가정:
-- 최근 활동(Recency) 계산을 위한 '현재 날짜'는 캠페인 발송일입니다 (2023-10-26).
-- 사용자 및 정산 데이터가 사용 가능하다고 가정합니다.

-- 캠페인 분석 기준일 설정
SET @campaign_date = '2023-10-26';

WITH UserLastSettlement AS (
    -- 사용자별 마지막 정산일을 계산합니다.
    SELECT
        u.user_id,             -- 사용자 고유 ID
        u.total_settle_cnt,    -- 사용자의 총 정산 횟수
        MAX(s.settled_at) AS last_settled_at -- 각 사용자의 가장 최근 정산일
    FROM
        users u
    JOIN
        settlements s ON u.user_id = s.user_id
    GROUP BY
        u.user_id, u.total_settle_cnt
),
UserRecency AS (
    -- 사용자별 Recency (캠페인 발송일로부터 마지막 정산일까지의 일수)를 계산합니다.
    SELECT
        user_id,
        total_settle_cnt,
        DATEDIFF(@campaign_date, last_settled_at) AS recency_days -- 캠페인 발송일로부터 마지막 정산일까지의 경과 일수
    FROM
        UserLastSettlement
),
RankedRecency AS (
    -- Recency 데이터를 total_settle_cnt별로 4분위수를 계산하여 순위를 매깁니다.
    SELECT
        user_id,
        total_settle_cnt,
        recency_days,
        NTILE(4) OVER (PARTITION BY total_settle_cnt ORDER BY recency_days) as quartile_rank -- total_settle_cnt 그룹 내 Recency 4분위 순위
    FROM
        UserRecency
),
SegmentedRecencyStats AS (
    -- total_settle_cnt 그룹별로 Recency의 Q1(25%)과 Q3(75%) 값을 계산합니다.
    SELECT
        total_settle_cnt,
        -- Q1: 25번째 백분위수 값 (두 번째 사분위수 그룹의 최소값)
        MIN(CASE WHEN quartile_rank = 2 THEN recency_days END) AS Q1,
        -- Q3: 75번째 백분위수 값 (네 번째 사분위수 그룹의 최소값)
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
        -- 여러 번 정산 이력이 있고, Recency가 Q3를 넘어섰지만 이탈 임계값 내에 있는 사용자: 재활성화 대상
        WHEN ur.total_settle_cnt > 1 AND ur.recency_days > srs.Q3 AND ur.recency_days <= (srs.Q3 + (1.5 * (srs.Q3 - srs.Q1))) THEN 'Re-engagement Candidate'
        -- 통계적 이탈 임계값을 넘어선 사용자: 이탈자
        WHEN ur.recency_days > (srs.Q3 + (1.5 * (srs.Q3 - srs.Q1))) THEN 'Churner'
        -- 그 외 일반 활동 사용자
        ELSE 'Active User'
    END AS User_Segment_Status
FROM
    UserRecency ur
JOIN
    SegmentedRecencyStats srs ON ur.total_settle_cnt = srs.total_settle_cnt
WHERE srs.Q1 IS NOT NULL AND srs.Q3 IS NOT NULL -- Exclude segments where Q1 or Q3 could not be determined
ORDER BY
    ur.total_settle_cnt, ur.recency_days;
