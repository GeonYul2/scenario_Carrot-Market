-- V2_step3_ab_test_performance.sql
-- STEP 3: 3-Arm AB 테스트 성과 측정

-- 이 쿼리는 각 AB 그룹별 적용률(Apply Rate)을 계산하고,
-- 상승(Uplift) 측정 및 통계적 유의성 테스트에 필요한 데이터를 제공합니다.

-- 가정:
-- 캠페인 발송일은 '2023-10-26'입니다.
-- 'is_applied' 컬럼은 공고 지원 여부를 나타냅니다 (1: 지원함, 0: 지원 안 함).

-- 캠페인 분석 기준일 설정
SET @campaign_date = '2023-10-26';

WITH GroupPerformance AS (
    -- 각 AB 그룹별 총 사용자 수, 지원 수, 미지원 수를 집계하여 성과를 측정합니다.
    SELECT
        ab_group,                           -- A/B 테스트 그룹
        COUNT(DISTINCT user_id) AS total_users, -- 그룹 내 총 사용자 수
        SUM(CASE WHEN is_applied = 1 THEN 1 ELSE 0 END) AS applications, -- 공고 지원 수
        SUM(CASE WHEN is_applied = 0 THEN 1 ELSE 0 END) AS non_applications -- 공고 미지원 수
    FROM
        campaign_logs
    WHERE
        sent_at = @campaign_date -- 특정 캠페인 발송일에 해당하는 로그만 필터링
    GROUP BY
        ab_group
)
SELECT
    gp.ab_group,        -- A/B 테스트 그룹
    gp.total_users,     -- 총 사용자 수
    gp.applications,    -- 지원 건수
    gp.non_applications, -- 미지원 건수
    (gp.applications * 1.0 / gp.total_users) AS apply_rate, -- 적용률 (Apply Rate)
    -- Control 그룹 대비 상승률(Uplift) 계산
    -- 참고: 이 서브쿼리는 항상 'Control' 그룹이 존재한다고 가정합니다.
    (
        (gp.applications * 1.0 / gp.total_users) -
        (SELECT (applications * 1.0 / total_users) FROM GroupPerformance WHERE ab_group = 'Control')
    ) AS uplift_vs_control,
    -- 카이제곱 검정을 위한 데이터 제공 (카이제곱 검정은 일반적으로 외부 도구에서 수행됩니다)
    '통계적 유의성 검정을 위해 이 값들(각 그룹의 지원/미지원 수)을 내보내고 통계 소프트웨어(예: Python SciPy, R)에서 카이제곱 검정을 수행하십시오.' AS chi_square_guidance
FROM
    GroupPerformance gp
ORDER BY
    gp.ab_group;
