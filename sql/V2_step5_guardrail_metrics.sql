-- V2_step5_guardrail_metrics.sql
-- STEP 5: 가드레일 분석 (고위험군 대상 알림 차단율)

SET @campaign_date = '2023-10-26';

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
-- [CTE] 고위험군
HighRiskUsers AS (
    SELECT ust.user_id
    FROM UserSettleTiers ust
    JOIN SegmentedAvgCycleStats sas ON ust.settle_tier = sas.settle_tier
    WHERE ust.recency_days > sas.q3_avg_settle_cycle
),
-- [CTE] 기준일 고위험군 수신자
CampaignRecipientsWithGroup AS (
    SELECT DISTINCT
        cl.user_id,
        cl.ab_group
    FROM campaign_logs cl
    JOIN HighRiskUsers hr ON cl.user_id = hr.user_id
    WHERE cl.sent_at = @campaign_date
),
-- [CTE] 기준일 이후 차단 사용자
BlockedUsers AS (
    SELECT
        user_id,
        notification_blocked_at
    FROM users
    WHERE notification_blocked_at IS NOT NULL
      AND notification_blocked_at > @campaign_date
)
SELECT
    'Notification Blocking Rate (High-Risk Target)' AS metric,
    cr.ab_group,
    COUNT(DISTINCT cr.user_id) AS total_recipients_in_group,
    COUNT(DISTINCT bu.user_id) AS blocked_users_in_group,
    (COUNT(DISTINCT bu.user_id) * 1.0 / COUNT(DISTINCT cr.user_id)) * 100 AS blocking_rate_pct
FROM CampaignRecipientsWithGroup cr
LEFT JOIN BlockedUsers bu ON cr.user_id = bu.user_id
GROUP BY cr.ab_group
ORDER BY cr.ab_group;
