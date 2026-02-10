# [V2] 당근알바 미매칭 해소를 위한 CRM 성과 분석 프로젝트

## Executive Summary
본 프로젝트는 '당근알바' 서비스의 핵심 문제인 **'신규 공고 미매칭'** 현상을 데이터 분석을 통해 발견하고, 이를 해결하기 위한 개인화 CRM 캠페인을 설계, 실행, 측정하는 전 과정을 다룹니다. 특히, 실제 현업에서 사용하는 **데이터 웨어하우징(Star Schema) 설계**를 적용하여 데이터 모델을 구축했으며, A/B 테스트의 효과를 통계적으로 검증하여 캠페인의 비즈니스 임팩트를 증명하는 것을 목표로 합니다.

---

## 1. 데이터베이스 설계 (V2: Star Schema)

분석의 확장성과 효율성을 위해, 데이터의 성격에 따라 테이블을 **Dimension(정보성)**과 **Fact(사건)**으로 분리하는 스타 스키마 구조를 채택했습니다. 이는 Kaggle의 실제 E-commerce 로그 데이터셋 구조를 참고하여 '당근알바' 서비스에 맞게 재해석한 것입니다.

- **`dim_users`**: 유저의 고정적인 정보 (동네, 매너온도 등)
- **`dim_job_posts`**: 공고의 고정적인 정보 (카테고리, 급여 등)
- **`fct_user_event_logs`**: 유저가 남기는 모든 행동 로그 (시간에 따라 계속 쌓임)
- **`fct_crm_campaign_logs`**: CRM 캠페인 발송 및 결과 로그 (시간에 따라 계속 쌓임)

![Star Schema Diagram](https://i.imgur.com/gNzY1G6.png)
*(위 이미지는 스타 스키마의 개념을 설명하기 위한 예시입니다.)*

---

## 2. 문제 발견 및 가설 수립 (Problem Discovery)

### 2.1. 현황 분석: "사장님들이 떠나고 있다"
플랫폼의 건강도를 파악하기 위해, 먼저 '공고 게시 후 24시간 내 첫 지원 발생률'을 확인했습니다.

**[문제 발견 SQL]**
```sql
-- 24시간 내에 'submit_application' 이벤트가 없는 공고의 비율 계산
SELECT
    COUNT(CASE
        WHEN first_app.first_app_timestamp IS NULL OR first_app.first_app_timestamp > p.created_at + INTERVAL 24 HOUR THEN p.post_uuid
    END) * 100.0 / COUNT(p.post_uuid) AS unmatched_rate_24h
FROM
    dim_job_posts p
LEFT JOIN (
    SELECT post_uuid, MIN(event_timestamp) as first_app_timestamp
    FROM fct_user_event_logs
    WHERE event_name = 'submit_application'
    GROUP BY post_uuid
) AS first_app ON p.post_uuid = first_app.post_uuid;
```
**분석 결과, 신규 공고의 약 30%가 24시간 내에 단 한 명의 지원자도 받지 못하는 '미매칭 상태'임을 발견했습니다.** 이는 사장님의 이탈을 유발하는 심각한 문제로 판단했습니다.

### 2.2. 가설 수립
> "공고에 관심은 보였으나(view, stay) 지원은 망설이는(no-apply) 유저들에게 적절한 시점에 리마인드 메시지를 보내준다면, 첫 지원을 유도하여 미매칭 문제를 개선할 수 있을 것이다."

---

## 3. 분석 설계 (Analysis Design)

### 3.1. 타겟 세그먼트 정의: '고관여 망설임 유저'
가설을 검증하기 위해, 아래 조건을 모두 만족하는 유저를 CRM 캠페인 타겟으로 정의했습니다.

**[타겟팅 SQL]**
```sql
-- 최근 7일간 활동 로그를 기반으로 '고관여 망설임 유저' 추출
SELECT
    logs.user_uuid
FROM fct_user_event_logs AS logs
JOIN dim_users AS users ON logs.user_uuid = users.user_uuid
WHERE
    logs.event_timestamp >= NOW() - INTERVAL 7 DAY
    AND users.is_push_agreed = 1 -- 푸시 알림 동의 유저
GROUP BY
    logs.user_uuid
HAVING
    -- 'view' 또는 'stay' 이벤트가 3회 이상 발생하고
    COUNT(CASE WHEN logs.event_name IN ('view', 'stay') THEN logs.event_uuid END) >= 3
    AND
    -- 체류시간의 합이 상위 20% 이상인 '고관여' 유저 중에서
    SUM(logs.stay_duration_ms) >= (
        SELECT PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY total_stay)
        FROM (
            SELECT SUM(stay_duration_ms) as total_stay
            FROM fct_user_event_logs
            WHERE event_timestamp >= NOW() - INTERVAL 7 DAY AND stay_duration_ms IS NOT NULL
            GROUP BY user_uuid
        ) AS stay_sums
    )
    AND
    -- 'submit_application' 이벤트는 한 번도 발생하지 않은 '망설임' 유저
    COUNT(CASE WHEN logs.event_name = 'submit_application' THEN logs.event_uuid END) = 0;
```

### 3.2. A/B 테스트 설계
- **실험군 (Treatment):** 타겟 유저 중 80%에게 개인화 푸시 메시지 발송.
- **대조군 (Control):** 나머지 20%에게는 아무런 액션을 취하지 않음 (순수 자연 전환율 측정).
- **핵심 지표:** 캠페인 발송 후 48시간 내 `submit_application` 전환율.

---

## 4. 성과 분석 및 통계적 검증

### 4.1. 캠페인 성과 측정
캠페인 그룹별 전환율을 계산하여, 캠페인의 직접적인 효과(Lift)를 측정합니다.

**[성과 측정 SQL]**
```sql
-- 캠페인 그룹별 최종 지원 전환율 계산
SELECT
    crm.test_group,
    COUNT(DISTINCT crm.user_uuid) AS total_users,
    COUNT(DISTINCT final_app.user_uuid) AS converted_users,
    (COUNT(DISTINCT final_app.user_uuid) * 100.0 / COUNT(DISTINCT crm.user_uuid)) AS conversion_rate
FROM
    fct_crm_campaign_logs AS crm
LEFT JOIN
    fct_user_event_logs AS final_app ON crm.user_uuid = final_app.user_uuid
    AND final_app.event_name = 'submit_application'
    -- 캠페인 로그가 쌓인 시점 이후의 지원만 유효
    AND final_app.event_timestamp > crm.created_at
    -- 캠페인 발송 후 48시간 내의 지원만 카운트
    AND final_app.event_timestamp <= crm.created_at + INTERVAL 48 HOUR
GROUP BY
    crm.test_group;
```

### 4.2. 통계적 유의성 검증
실험군과 대조군의 전환율 차이가 단순한 우연이 아님을 통계적으로 증명하기 위해 **카이제곱 검정(Chi-squared Test)**을 수행합니다. 검정 결과 **p-value**가 유의수준(0.05)보다 낮게 나타나면, 캠페인 효과가 통계적으로 유의미하다고 판단합니다.

---

## 5. 고도화 분석 방안 (Future Work)

본 프로젝트의 분석을 더 깊이 있게 확장하기 위한 추가 분석 아이디어를 제안합니다.

- **퍼널 분석 (Funnel Analysis):** `view` -> `stay` -> `click_apply` -> `submit_application` 각 단계의 전환율을 측정하여, 유저가 가장 많이 이탈하는 병목 지점을 구체적으로 식별합니다.
- **코호트 분석 (Cohort Analysis):** 캠페인으로 유입된 유저 그룹과 자연적으로 유입된 유저 그룹의 장기 재지원율(Retention)을 비교하여, 캠페인이 진성 유저 확보에 기여했는지 평가합니다.
- **비용-편익 분석 (Cost-Benefit Analysis):** 캠페인에 소요된 비용(서버, 인력 등)과, 캠페인을 통해 얻은 이익(사장님 이탈 방지로 인한 손실 감소)을 비교하여 최종 ROI를 산출합니다.