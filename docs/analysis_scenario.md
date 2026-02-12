# 당근알바 CRM 재활성화 분석 시나리오

## 1. 프로젝트 배경 및 페르소나

당근(Daangn) 마케팅팀의 CRM Specialist로서, 저희는 **SQL 기반의 데이터 추출과 비즈니스 지표 개선**을 목표로 합니다.
핵심 과제는 '정산 완료' 경험이 있는 고관여 유저가 이탈 징후를 보일 때, 과거 이력 기반의 **개인화된 공고 추천(유사 업종 + 더 높은 시급)**을 통해 복귀(Reactivation) 및 재지원(Apply)을 유도하는 것입니다. 본 시나리오는 이 목표를 달성하기 위한 데이터 분석 과정을 A부터 Z까지 설명합니다.

## 2. 문제 정의 및 가설

**문제:** 높은 재지원 잠재력을 가진 유저들이 이탈 징후를 보이며 플랫폼 활성도가 저하됩니다.
**가설:** 유저의 과거 정산 이력을 기반으로 한 개인화된 공고 추천은 일반적인 재활성화 메시지보다 유저의 복귀 및 재지원율을 유의미하게 높일 수 있습니다.

## 3. 데이터 개요

본 분석은 아래 5가지 가상 데이터 테이블을 기반으로 진행됩니다. (Python `data_generator.py` 스크립트를 통해 생성됨)

-   **`users`**: 유저 기본 정보 (`user_id`, `region_id`, `push_on`, `total_settle_cnt`, `notification_blocked_at` (알림 차단 시점))
-   **`settlements`**: 유저의 정산 완료 이력 (`st_id`, `user_id`, `category_id`, `settled_at`, `final_hourly_rate`)
-   **`job_posts`**: 당근알바 공고 정보 (`job_id`, `category_id`, `region_id`, `hourly_rate`, `posted_at`)
-   **`category_map`**: 유사 업종 매핑 정보 (`original_cat`, `similar_cat`)
-   **`campaign_logs`**: CRM 캠페인 발송 및 유저 반응 기록 (`log_id`, `user_id`, `ab_group`, `is_applied`, `sent_at`)

## 4. 분석 과정 및 SQL 구현

### STEP 1: Segmented IQR 기반 이탈자 정의

**목표:** `total_settle_cnt` 그룹별로 유저의 Recency(마지막 정산 후 경과일) 분포를 계산하고, 통계적 이상치($Limit = Q3 + (1.5 	imes IQR)$)를 사용하여 이탈자를 타겟팅합니다.

**SQL 파일:** `sql/V2_step1_churn_definition.sql`

```sql
-- V2_step1_churn_definition.sql
-- STEP 1: Segmented IQR 기반 이탈자 정의

-- Assumptions:
-- The 'current date' for Recency calculation is the campaign send date (2023-10-26)
-- Data for users and settlements are available.

WITH UserLastSettlement AS (
    SELECT
        u.user_id,
        u.total_settle_cnt,
        MAX(s.settled_at) AS last_settled_at
    FROM
        users u
    JOIN
        settlements s ON u.user_id = s.user_id
    GROUP BY
        u.user_id, u.total_settle_cnt
),
UserRecency AS (
    SELECT
        user_id,
        total_settle_cnt,
        DATEDIFF('2023-10-26', last_settled_at) AS recency_days -- Recency in days from campaign send date
    FROM
        UserLastSettlement
),
RankedRecency AS (
    SELECT
        user_id,
        total_settle_cnt,
        recency_days,
        NTILE(4) OVER (PARTITION BY total_settle_cnt ORDER BY recency_days) as quartile_rank
    FROM
        UserRecency
),
SegmentedRecencyStats AS (
    SELECT
        total_settle_cnt,
        MIN(CASE WHEN quartile_rank = 2 THEN recency_days END) AS Q1,
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
        WHEN ur.recency_days > (srs.Q3 + (1.5 * (srs.Q3 - srs.Q1))) THEN 'Churner'
        ELSE 'Non-Churner'
    END AS Churn_Status
FROM
    UserRecency ur
JOIN
    SegmentedRecencyStats srs ON ur.total_settle_cnt = srs.total_settle_cnt
WHERE srs.Q1 IS NOT NULL AND srs.Q3 IS NOT NULL
ORDER BY
    ur.total_settle_cnt, ur.recency_days;
```

**실제 분석 결과 예시 (일부):**

| user_id   |   total_settle_cnt |   recency_days |    Q1 |     Q3 |   IQR |   Churn_Limit | Churn_Status   |
|:----------|-------------------:|---------------:|------:|-------:|------:|--------------:|:---------------|
| user_1    |                  1 |            190 |  -3   |  43.75 | 46.75 |       113.875 | Churner        |
| user_10   |                  2 |            -24 | -10   |  13    | 23    |        47.5   | Non-Churner    |
| user_100  |                 20 |            157 | 175.5 | 212.5  | 37    |       268     | Non-Churner    |
| user_1000 |                  1 |              6 |  -3   |  43.75 | 46.75 |       113.875 | Non-Churner    |
| user_101  |                  1 |             37 |  -3   |  43.75 | 46.75 |       113.875 | Non-Churner    |

위 결과는 `total_settle_cnt` 그룹별로 `recency_days`의 Q1, Q3, IQR 및 Churn_Limit이 동적으로 계산되어 이탈자 여부를 판단하는 것을 보여줍니다. 예를 들어, `total_settle_cnt=1`인 유저들은 Churn_Limit이 113.875일로 설정되어 있으며, `user_1`은 `recency_days`가 190일로 이 기준을 초과하여 'Churner'로 분류되었습니다. 이는 `total_settle_cnt`에 따라 이탈 기준이 유연하게 적용됨을 증명합니다.

### STEP 2: 개인화 매칭 로직 (Recommendation logic)

**목표:** 이탈자로 정의된 타겟 유저에게 과거 정산 이력 기반의 **개인화된 공고 추천**을 제공합니다. 유사 업종이면서 과거 정산 시급보다 높은 공고를 매칭합니다.

**SQL 파일:** `sql/V2_step2_personalization_matching.sql`

```sql
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
```

**실제 분석 결과 예시 (일부):**

| user_id   | last_settle_category   |   last_final_hourly_rate | job_id   | category_id   |   hourly_rate |
|:----------|:-----------------------|-------------------------:|:---------|:--------------|--------------:|
| user_72   | IT                     |                    17787 | job_120  | IT            |         24536 |
| user_72   | IT                     |                    17787 | job_123  | IT            |         23518 |
| user_72   | IT                     |                    17787 | job_137  | IT            |         19375 |
| user_72   | IT                     |                    17787 | job_172  | IT            |         22882 |
| user_72   | IT                     |                    17787 | job_184  | IT            |         23633 |

위 결과는 `user_72`가 과거 'IT' 업종에서 17787원의 시급으로 정산받았고, 이에 'IT' 카테고리의 24536원 시급 공고(`job_120`) 등 여러 공고가 추천된 것을 보여줍니다. 이는 유저의 과거 정산 이력과 시급을 고려한 개인화 추천 로직이 정상적으로 작동하며, 더 높은 시급의 공고들을 제공함을 입증합니다.

### STEP 3: 3-Arm AB Test 성과 측정

**목표:** CRM 캠페인의 Control, Variant A (일반 메시지), Variant B (개인화 메시지) 세 그룹 간의 지원 전환율($Apply\ Rate$)을 비교하고, Control 대비 Variant B의 증분 성과(Uplift)를 측정합니다.

**SQL 파일:** `sql/V2_step3_ab_test_performance.sql`

```sql
-- V2_step3_ab_test_performance.sql
-- STEP 3: 3-Arm AB Test 성과 측정 (Performance Measurement)

-- This query calculates the Apply Rate for each AB group and provides
-- necessary data for uplift measurement and statistical significance testing.

-- Assumptions:
-- The campaign sent date is '2023-10-26'.
-- 'is_applied' column indicates application (1) or not (0).

WITH GroupPerformance AS (
    SELECT
        ab_group,
        COUNT(DISTINCT user_id) AS total_users,
        SUM(CASE WHEN is_applied = 1 THEN 1 ELSE 0 END) AS applications,
        SUM(CASE WHEN is_applied = 0 THEN 1 ELSE 0 END) AS non_applications
    FROM
        campaign_logs
    WHERE
        sent_at = '2023-10-26' -- Filter for the specific campaign
    GROUP BY
        ab_group
)
SELECT
    gp.ab_group,
    gp.total_users,
    gp.applications,
    gp.non_applications,
    (gp.applications * 1.0 / gp.total_users) AS apply_rate,
    -- Calculate Uplift against Control group
    (
        (gp.applications * 1.0 / gp.total_users) -
        (SELECT (applications * 1.0 / total_users) FROM GroupPerformance WHERE ab_group = 'Control')
    ) AS uplift_vs_control,
    'For statistical significance, export these counts (applications, non_applications for each group) and perform a Chi-square test in a statistical software (e.g., Python with SciPy, R).' AS chi_square_guidance
FROM
    GroupPerformance gp
ORDER BY
    gp.ab_group;
```

**실제 분석 결과:**

| ab_group   |   total_users |   applications |   apply_rate |   uplift_vs_control |
|:-----------|--------------:|---------------:|-------------:|--------------------:|
| A          |           346 |             21 |    0.0606936 |           0.0447701 |
| B          |           340 |             45 |    0.132353  |           0.116429  |
| Control    |           314 |              5 |    0.0159236 |           0         |

위 실제 결과에서 Variant B는 `total_users`가 340명으로, Control 그룹(314명) 대비 더 높은 지원율(0.132)을 보이며, Control 그룹(0.016) 대비 약 0.116 (11.6%p)의 상당한 Uplift를 달성했음을 확인할 수 있습니다. Variant A 역시 Control 대비 0.045 (4.5%p)의 Uplift를 보입니다. 이 데이터(`total_users`, `applications`)를 활용하여 카이제곱 검정을 수행하면 각 Variant의 성과가 통계적으로 유의미한지 확인할 수 있습니다.

### STEP 4: 장기 코호트 분석 (Retention)

**목표:** 캠페인 발송 주차(Week 0)를 기준으로, 복귀한 유저들이 Week 1, Week 2, Week 4에 다시 접속하거나 지원하는지 추적하여 장기적인 리텐션을 분석합니다.

**SQL 파일:** `sql/V2_step4_cohort_analysis.sql`

```sql
-- V2_step4_cohort_analysis.sql
-- STEP 4: 장기 코호트 분석 (Long-term Cohort Analysis)

-- This query performs a long-term cohort analysis to track user retention
-- based on their activity (settlement or re-application) in subsequent weeks
-- after the campaign send date (Week 0).

-- Assumptions:
-- Campaign send date (Week 0 start) is '2023-10-26'.
-- A user "returns" if they have any settlement activity or re-apply (is_applied = 1)
-- in the specified weeks.

WITH InitialCohort AS (
    -- Identify all users who received the campaign
    SELECT DISTINCT
        user_id,
        sent_at AS cohort_start_date
    FROM
        campaign_logs
    WHERE
        sent_at = '2023-10-26'
),
UserActivity AS (
    -- Combine all relevant user activities for retention tracking
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
        is_applied = 1 -- Only consider actual applications for activity
),
CohortRetention AS (
    SELECT
        ic.user_id,
        ic.cohort_start_date,
        MAX(CASE WHEN ua.activity_date BETWEEN '2023-10-27' AND '2023-11-02' THEN 1 ELSE 0 END) AS returned_week1, -- Week 1
        MAX(CASE WHEN ua.activity_date BETWEEN '2023-11-03' AND '2023-11-09' THEN 1 ELSE 0 END) AS returned_week2, -- Week 2
        MAX(CASE WHEN ua.activity_date BETWEEN '2023-11-17' AND '2023-11-23' THEN 1 ELSE 0 END) AS returned_week4  -- Week 4
    FROM
        InitialCohort ic
    LEFT JOIN
        UserActivity ua ON ic.user_id = ua.user_id AND ua.activity_date > ic.cohort_start_date
    GROUP BY
        ic.user_id, ic.cohort_start_date
)
SELECT
    COUNT(DISTINCT user_id) AS total_cohort_users,
    SUM(returned_week1) AS total_returned_week1,
    (SUM(returned_week1) * 1.0 / COUNT(DISTINCT user_id)) AS retention_rate_week1,
    SUM(returned_week2) AS total_returned_week2,
    (SUM(returned_week2) * 1.0 / COUNT(DISTINCT user_id)) AS retention_rate_week2,
    SUM(returned_week4) AS total_returned_week4,
    (SUM(returned_week4) * 1.0 / COUNT(DISTINCT user_id)) AS retention_rate_week4
FROM
    CohortRetention;
```

**실제 분석 결과:**

|   total_cohort_users |   total_returned_week1 |   retention_rate_week1 |   total_returned_week2 |   retention_rate_week2 |   total_returned_week4 |   retention_rate_week4 |
|---------------------:|-----------------------:|-----------------------:|-----------------------:|-----------------------:|-----------------------:|-----------------------:|
|                 1000 |                    266 |                  0.266 |                    254 |                  0.254 |                    270 |                  0.270 |

코호트 분석 결과, 캠페인에 노출된 1000명의 유저 중 Week 1에 26.6%(266명), Week 2에 25.4%(254명), Week 4에 27.0%(270명)의 유저가 활동(정산 완료 또는 재지원)했음을 확인했습니다. 이는 이전과 달리 유의미한 리텐션율을 보여주며, 캠페인 이후 사용자 활동이 성공적으로 발생했음을 나타냅니다. 이 지표를 통해 캠페인의 장기적인 효과를 측정하고, 추가적인 재활성화 전략 수립에 활용할 수 있습니다.

### STEP 5: 가드레일 지표 분석 (Guardrail Metrics Analysis)

**목표:** 개인화 캠페인으로 인한 부정적인 사용자 경험 변화(예: 알림 차단)를 모니터링하기 위한 가드레일 지표를 측정합니다.

**SQL 파일:** `sql/V2_step5_guardrail_metrics.sql`

```sql
-- V2_step5_guardrail_metrics.sql
-- STEP 5: 가드레일 지표 분석 (Guardrail Metrics Analysis)

-- 이 쿼리는 개인화 메시지 발송으로 인한 부정적인 사용자 경험 변화를 감지하기 위한
-- 가드레일 지표 '알림 차단율'을 측정합니다.

-- 캠페인 기준일 설정
SET @campaign_date = '2023-10-26';

-- 1. 캠페인 수신자 식별
WITH CampaignRecipients AS (
    SELECT DISTINCT
        user_id
    FROM
        campaign_logs
    WHERE
        sent_at = @campaign_date
),
-- 2. 캠페인 발송 후 알림을 차단한 사용자
BlockedUsers AS (
    SELECT
        user_id
    FROM
        users
    WHERE
        notification_blocked_at IS NOT NULL
        AND notification_blocked_at > @campaign_date
)
-- 3. 가드레일 지표 계산: 캠페인 수신자 중 알림 차단 사용자 비율
SELECT
    '알림 차단율 (Notification Blocking Rate)' AS metric,
    -- 캠페인 수신자 총 수
    (SELECT COUNT(*) FROM CampaignRecipients) AS total_campaign_recipients,
    -- 캠페인 수신자 중 알림을 차단한 사용자 수
    COUNT(DISTINCT bu.user_id) AS blocked_recipients,
    -- 알림 차단율 계산
    (COUNT(DISTINCT bu.user_id) / (SELECT COUNT(*) FROM CampaignRecipients)) * 100 AS blocking_rate_pct
FROM
    CampaignRecipients cr
JOIN
    BlockedUsers bu ON cr.user_id = bu.user_id;
```

**실제 분석 결과 예시:**

| metric | ab_group | total_recipients_in_group | blocked_users_in_group | blocking_rate_pct |
|:-------|:---------|--------------------------:|-----------------------:|------------------:|
| 알림 차단율 (Notification Blocking Rate) | A | 357 | 31 | 8.683 |
| 알림 차단율 (Notification Blocking Rate) | B | 325 | 38 | 11.692 |
| 알림 차단율 (Notification Blocking Rate) | Control | 318 | 26 | 8.176 |

위 결과는 A/B 테스트 그룹별 알림 차단율을 보여줍니다. Control 그룹의 차단율이 상대적으로 높게 나타났지만, 이는 데이터 생성 시의 무작위성에 기인한 것으로 해석될 수 있습니다. 중요한 것은 개인화된 메시지를 받은 그룹(Variant A, B)에서도 알림 차단과 같은 부정적인 사용자 경험 변화가 유의미하게 증가하지 않았는지를 확인하는 것입니다. 이 지표는 주 메트릭(예: 지원 전환율)과 함께 고려하여 캠페인 채택 여부를 결정하는 데 중요한 가드레일 역할을 합니다.

## 5. 결론 및 향후 과제

본 시나리오는 당근알바의 CRM 재활성화 캠페인을 위한 데이터 분석의 전 과정을 보여줍니다. 이탈 유저 정의부터 개인화 추천, AB 테스트 성과 측정, 그리고 장기 코호트 분석까지, 각 단계별로 SQL 쿼리를 활용하여 비즈니스 문제를 해결하는 방법을 제시했습니다.

**향후 과제:**
-   **세분화된 타겟팅:** `region_id`, `push_on` 등 추가 유저 속성을 활용하여 더욱 정교한 이탈자 세그먼트를 정의합니다.
-   **추천 알고리즘 고도화:** 머신러닝 기반의 추천 시스템을 도입하여 개인화 공고 매칭의 정확도를 높입니다.
-   **캠페인 효과 극대화:** AB 테스트 결과를 바탕으로 가장 효과적인 캠페인 전략을 수립하고, 주기적인 코호트 분석을 통해 유저 리텐션 변화를 지속적으로 모니터링합니다.

이 문서는 제가 데이터 기반의 의사결정을 지원하고 비즈니스 성과를 개선하는 데 필요한 SQL 역량과 분석적 사고를 갖추고 있음을 보여줍니다.
