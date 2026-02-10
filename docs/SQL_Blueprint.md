당근의 채용 요건인 **"직접 데이터를 추출하고 가공하는 역량"**을 보여주는 핵심 문서입니다 .

Markdown
# [SQL] 당근알바 CRM 타겟팅 및 성과 측정 쿼리 설계서

## 1. 개요
본 문서는 당근알바 미매칭 해소를 위해 유저 행동 로그에서 가망 고객을 추출하고, 캠페인 성과를 측정하기 위한 SQL 로직을 정의한다.

## 2. 타겟 세그먼트 추출 (Advanced Targeting)
- **로직**: 최근 7일간 특정 카테고리 공고를 3회 이상 조회했으나 지원 이력이 없는 유저 중, 체류 시간이 상위 20%인 '고관여 망설임 유저'를 추출한다.
- **특이사항**: 개인별 방문 주기를 반영한 타겟팅으로 피로도를 최소화한다.

```sql
WITH user_activity AS (
    SELECT 
        user_id,
        dong_id,
        COUNT(log_id) AS view_count,
        AVG(stay_duration) AS avg_stay_time,
        MAX(event_time) AS last_interaction
    FROM alba_logs
    WHERE event_type = 'view'
      AND event_time >= DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    GROUP BY user_id, dong_id
),
high_engagement_non_applicants AS (
    SELECT v.*
    FROM user_activity v
    LEFT JOIN (
        SELECT DISTINCT user_id 
        FROM alba_logs 
        WHERE event_type = 'click_apply'
          AND event_time >= DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    ) a ON v.user_id = a.user_id
    WHERE a.user_id IS NULL -- 최근 7일간 지원 이력 없음
      AND v.view_count >= 3   -- 3회 이상 조회한 관심 유저
)
SELECT 
    user_id, 
    dong_id,
    'high_interest_hesitator' AS segment_tag
FROM high_engagement_non_applicants
WHERE avg_stay_time >= (
    SELECT PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY stay_duration) 
    FROM alba_logs
);
3. 성과 측정 (Holdout Lift Analysis)
목적: 푸시를 받지 않은 홀드아웃 그룹 대비 실험군의 순증 효과(Lift) 산출.

SQL
SELECT 
    group_type,
    COUNT(DISTINCT user_id) AS total_users,
    SUM(CASE WHEN is_applied = 1 THEN 1 ELSE 0 END) AS applied_cnt,
    ROUND(SUM(is_applied) * 1.0 / COUNT(user_id), 4) AS conversion_rate
FROM crm_exp_results
GROUP BY group_type;