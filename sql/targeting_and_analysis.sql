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

-- 성과 측정
SELECT 
    group_type,
    COUNT(DISTINCT user_id) AS total_users,
    SUM(CASE WHEN is_applied = 1 THEN 1 ELSE 0 END) AS applied_cnt,
    ROUND(SUM(is_applied) * 1.0 / COUNT(user_id), 4) AS conversion_rate
FROM crm_exp_results
GROUP BY group_type;