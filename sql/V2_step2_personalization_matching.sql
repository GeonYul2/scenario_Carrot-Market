-- V2_step2_personalization_matching.sql
-- STEP 2: 개인화 매칭 로직 (Recommendation logic)

-- 이 쿼리는 사용자의 과거 정산 이력 및 구인 공고 기준에 따라 타겟 사용자에게 개인화된 구인 추천을 식별합니다.

-- 가정:
-- '타겟 사용자'는 잠재적 이탈자 또는 재활성화 대상자로 식별된 사용자입니다.
-- 단순화를 위해, 이 쿼리는 최소한 한 번이라도 정산 이력이 있는 모든 사용자를 개인화 매칭을 위한 잠재적 타겟으로 간주합니다.
-- 캠페인 발송일은 '2023-10-26'입니다.

-- 캠페인 분석 기준일 설정
SET @campaign_date = '2023-10-26';

WITH UserLastSettlementInfo AS (
    -- 사용자별 가장 최근 정산 정보를 가져옵니다. (캠페인 발송일 이전)
    SELECT
        s.user_id,                          -- 사용자 고유 ID
        s.category_id AS last_settle_category, -- 마지막 정산 카테고리
        s.final_hourly_rate AS last_final_hourly_rate, -- 마지막 정산 시의 시간당 최종 금액
        ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY s.settled_at DESC) as rn -- 사용자별 최신 정산 순위
    FROM
        settlements s
    WHERE
        s.settled_at < @campaign_date -- 캠페인 발송일 이전의 정산 내역만 고려
),
CurrentTargetUsers AS (
    -- 각 사용자의 가장 최근 정산 정보만 선택하여 현재 타겟 사용자를 정의합니다.
    SELECT
        user_id,
        last_settle_category,
        last_final_hourly_rate
    FROM
        UserLastSettlementInfo
    WHERE rn = 1 -- 각 사용자별 최신 정산 정보만 가져옵니다.
),
UserCategoryPreferences AS (
    -- 사용자의 마지막 정산 카테고리와 이에 매핑된 유사 카테고리를 추출하여 선호 카테고리 정보를 구성합니다.
    SELECT
        ctu.user_id,
        ctu.last_settle_category,
        ctu.last_final_hourly_rate,
        cm.similar_cat AS preferred_job_category -- 원본 카테고리에 매핑된 유사 직무 카테고리
    FROM
        CurrentTargetUsers ctu
    LEFT JOIN
        category_map cm ON ctu.last_settle_category = cm.original_cat
),
ExpandedUserCategoryPreferences AS (
    -- 사용자의 마지막 정산 카테고리와 그와 유사한 모든 카테고리를 포함하여 매칭할 카테고리 선호도를 확장합니다.
    -- (기존 마지막 정산 카테고리와 유사 카테고리를 모두 포함)
    SELECT user_id, last_settle_category, last_final_hourly_rate, last_settle_category AS category_to_match FROM UserCategoryPreferences
    UNION ALL
    SELECT user_id, last_settle_category, last_final_hourly_rate, preferred_job_category AS category_to_match FROM UserCategoryPreferences WHERE preferred_job_category IS NOT NULL
)
SELECT DISTINCT
    eucp.user_id,             -- 사용자 고유 ID
    eucp.last_settle_category,  -- 사용자의 마지막 정산 카테고리
    eucp.last_final_hourly_rate, -- 사용자의 마지막 정산 시간당 급여
    jp.job_id,                 -- 추천된 공고 ID
    jp.category_id AS recommended_job_category, -- 추천된 공고 카테고리
    jp.hourly_rate AS recommended_hourly_rate,   -- 추천된 공고의 시간당 급여
    jp.region_id,              -- 추천된 공고의 지역 ID
    jp.posted_at               -- 추천된 공고의 게시일
FROM
    ExpandedUserCategoryPreferences eucp
JOIN
    job_posts jp ON eucp.category_to_match = jp.category_id
WHERE
    jp.hourly_rate > eucp.last_final_hourly_rate -- 이전 정산보다 시간당 급여가 더 높은 공고만 추천
ORDER BY
    eucp.user_id, jp.hourly_rate DESC;
