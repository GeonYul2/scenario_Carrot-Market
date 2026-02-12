-- V2_step5_guardrail_metrics.sql
-- STEP 5: 가드레일 지표 분석 (Guardrail Metrics Analysis)

-- 이 쿼리는 개인화 메시지 발송으로 인한 부정적인 사용자 경험 변화를 감지하기 위한
-- 가드레일 지표 '알림 차단율'을 A/B 테스트 그룹별로 측정합니다.

-- 캠페인 기준일 설정
SET @campaign_date = '2023-10-26';

WITH CampaignRecipientsWithGroup AS (
    SELECT
        cl.user_id,
        cl.ab_group
    FROM
        campaign_logs cl
    WHERE
        cl.sent_at = @campaign_date
),
BlockedUsers AS (
    SELECT
        user_id,
        notification_blocked_at
    FROM
        users
    WHERE
        notification_blocked_at IS NOT NULL
        AND notification_blocked_at > @campaign_date
)
SELECT
    '알림 차단율 (Notification Blocking Rate)' AS metric,
    cr.ab_group,
    COUNT(DISTINCT cr.user_id) AS total_recipients_in_group,
    COUNT(DISTINCT bu.user_id) AS blocked_users_in_group,
    (COUNT(DISTINCT bu.user_id) * 1.0 / COUNT(DISTINCT cr.user_id)) * 100 AS blocking_rate_pct
FROM
    CampaignRecipientsWithGroup cr
LEFT JOIN
    BlockedUsers bu ON cr.user_id = bu.user_id
GROUP BY
    cr.ab_group
ORDER BY
    cr.ab_group;