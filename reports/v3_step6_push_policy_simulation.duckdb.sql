-- V3 STEP6 policy simulation (DuckDB)

WITH RECURSIVE
params AS (
    SELECT DATE '2023-10-26' AS campaign_date, 7 AS recent_active_exclude_days, 0.30 AS top_k_ratio
),
base_ab AS (
    SELECT user_id, ab_group
    FROM (
        SELECT
            cl.user_id,
            cl.ab_group,
            row_number() OVER (PARTITION BY cl.user_id ORDER BY cl.sent_at) AS rn
        FROM campaign_logs cl, params p
        WHERE cl.sent_at = p.campaign_date
    ) x
    WHERE rn = 1
),
user_cycle AS (
    SELECT
        s.user_id,
        u.total_settle_cnt,
        datediff('day', min(s.settled_at), max(s.settled_at)) AS active_days,
        count(*) AS settle_cnt,
        datediff('day', max(s.settled_at), (SELECT campaign_date FROM params)) AS recency_days
    FROM settlements s
    JOIN users u ON u.user_id = s.user_id
    GROUP BY s.user_id, u.total_settle_cnt
),
user_tier AS (
    SELECT
        user_id,
        recency_days,
        CASE WHEN settle_cnt > 1 THEN active_days * 1.0 / (settle_cnt - 1) END AS avg_cycle_days,
        CASE
            WHEN total_settle_cnt = 1 THEN 'Light User'
            WHEN total_settle_cnt BETWEEN 2 AND 5 THEN 'Regular User'
            ELSE 'Power User'
        END AS settle_tier
    FROM user_cycle
    WHERE settle_cnt > 1
),
tier_q3 AS (
    SELECT
        settle_tier,
        min(CASE WHEN q_rank = 3 THEN avg_cycle_days END) AS q3_cycle_days
    FROM (
        SELECT
            settle_tier,
            avg_cycle_days,
            ntile(4) OVER (PARTITION BY settle_tier ORDER BY avg_cycle_days) AS q_rank
        FROM user_tier
    ) t
    GROUP BY settle_tier
),
high_risk_users AS (
    SELECT
        ut.user_id,
        CASE WHEN ut.recency_days > tq.q3_cycle_days THEN 1 ELSE 0 END AS is_high_risk
    FROM user_tier ut
    JOIN tier_q3 tq ON tq.settle_tier = ut.settle_tier
),
last_settlement AS (
    SELECT
        s.user_id,
        s.category_id,
        s.final_hourly_rate,
        row_number() OVER (PARTITION BY s.user_id ORDER BY s.settled_at DESC) AS rn
    FROM settlements s, params p
    WHERE s.settled_at < p.campaign_date
),
target_category AS (
    SELECT user_id, category_id, final_hourly_rate
    FROM last_settlement
    WHERE rn = 1
),
expanded_category AS (
    SELECT tc.user_id, tc.final_hourly_rate, tc.category_id AS category_to_match
    FROM target_category tc
    UNION ALL
    SELECT tc.user_id, tc.final_hourly_rate, cm.similar_cat
    FROM target_category tc
    JOIN category_map cm ON cm.original_cat = tc.category_id
),
user_wage_uplift AS (
    SELECT
        ec.user_id,
        max(jp.hourly_rate - ec.final_hourly_rate) AS max_wage_uplift
    FROM expanded_category ec
    JOIN job_posts jp
      ON jp.category_id = ec.category_to_match
     AND jp.hourly_rate > ec.final_hourly_rate
    GROUP BY ec.user_id
),
candidate_users AS (
    SELECT
        u.user_id,
        ba.ab_group,
        u.push_on,
        u.notification_blocked_at,
        coalesce(hr.is_high_risk, 0) AS is_high_risk,
        coalesce(wu.max_wage_uplift, 0) AS max_wage_uplift,
        (CASE WHEN coalesce(hr.is_high_risk, 0) = 1 THEN 70 ELSE 0 END + least(coalesce(wu.max_wage_uplift, 0) / 200.0, 30)) AS priority_score,
        cume_dist() OVER (
            ORDER BY (CASE WHEN coalesce(hr.is_high_risk, 0) = 1 THEN 70 ELSE 0 END + least(coalesce(wu.max_wage_uplift, 0) / 200.0, 30)) DESC, u.user_id
        ) AS priority_cume
    FROM users u
    JOIN base_ab ba ON ba.user_id = u.user_id
    LEFT JOIN high_risk_users hr ON hr.user_id = u.user_id
    LEFT JOIN user_wage_uplift wu ON wu.user_id = u.user_id
),
scenario_users AS (
    SELECT 'ALL_ELIGIBLE' AS scenario_name, * FROM candidate_users
    UNION ALL
    SELECT 'TOP30_PRIORITY' AS scenario_name, *
    FROM candidate_users
    WHERE priority_cume <= (SELECT top_k_ratio FROM params)
),
policy_schedule AS (
    SELECT 'Policy_0_Baseline' AS policy_name, (SELECT campaign_date FROM params) AS planned_send_date, 1 AS send_order
    UNION ALL SELECT 'Policy_1_CooldownCap2', (SELECT campaign_date FROM params), 1
    UNION ALL SELECT 'Policy_1_CooldownCap2', (SELECT campaign_date FROM params) + INTERVAL 7 DAY, 2
    UNION ALL SELECT 'Policy_2_StopRule', (SELECT campaign_date FROM params), 1
    UNION ALL SELECT 'Policy_2_StopRule', (SELECT campaign_date FROM params) + INTERVAL 3 DAY, 2
    UNION ALL SELECT 'Policy_2_StopRule', (SELECT campaign_date FROM params) + INTERVAL 10 DAY, 3
),
event_base AS (
    SELECT
        su.scenario_name,
        ps.policy_name,
        ps.planned_send_date,
        ps.send_order,
        su.user_id,
        su.ab_group,
        su.priority_score,
        su.push_on,
        su.notification_blocked_at
    FROM scenario_users su
    CROSS JOIN policy_schedule ps
),
event_eligible AS (
    SELECT eb.*
    FROM event_base eb, params p
    WHERE eb.push_on = 1
      AND (eb.notification_blocked_at IS NULL OR eb.notification_blocked_at > eb.planned_send_date)
      AND NOT EXISTS (
            SELECT 1
            FROM settlements s
            WHERE s.user_id = eb.user_id
              AND s.settled_at >= eb.planned_send_date - (p.recent_active_exclude_days || ' days')::INTERVAL
              AND s.settled_at <  eb.planned_send_date
      )
),
event_with_seq AS (
    SELECT
        ee.*,
        row_number() OVER (PARTITION BY ee.scenario_name, ee.policy_name, ee.user_id ORDER BY ee.planned_send_date) AS seq
    FROM event_eligible ee
),
basic_gate AS (
    SELECT
        ews.*,
        CASE
            WHEN ews.policy_name = 'Policy_0_Baseline' AND ews.seq = 1 THEN 1
            WHEN ews.policy_name = 'Policy_1_CooldownCap2' AND ews.seq <= 2 THEN 1
            WHEN ews.policy_name = 'Policy_2_StopRule' AND ews.seq <= 3 THEN 1
            ELSE 0
        END AS pass_basic_gate
    FROM event_with_seq ews
),
treatment_seed AS (
    SELECT
        bg.scenario_name,
        bg.policy_name,
        bg.user_id,
        bg.ab_group,
        bg.seq,
        bg.planned_send_date,
        1 AS sent_flag,
        CASE WHEN EXISTS (
            SELECT 1
            FROM settlements s
            WHERE s.user_id = bg.user_id
              AND s.settled_at >= bg.planned_send_date
              AND s.settled_at <= bg.planned_send_date + INTERVAL 3 DAY
        ) THEN 1 ELSE 0 END AS reactivated_within_3d,
        CASE
            WHEN bg.policy_name = 'Policy_2_StopRule'
             AND NOT EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at >= bg.planned_send_date
                  AND s.settled_at <= bg.planned_send_date + INTERVAL 3 DAY
            ) THEN 1 ELSE 0
        END AS non_reactive_streak_after,
        CASE WHEN bg.notification_blocked_at IS NOT NULL
              AND bg.notification_blocked_at >= bg.planned_send_date
              AND bg.notification_blocked_at <= bg.planned_send_date + INTERVAL 7 DAY
             THEN 1 ELSE 0 END AS blocked_after_send
    FROM basic_gate bg
    WHERE bg.ab_group <> 'Control'
      AND bg.pass_basic_gate = 1
      AND bg.seq = 1
),
treatment_sim AS (
    SELECT * FROM treatment_seed

    UNION ALL

    SELECT
        bg.scenario_name,
        bg.policy_name,
        bg.user_id,
        bg.ab_group,
        bg.seq,
        bg.planned_send_date,
        CASE WHEN bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2 THEN 0 ELSE 1 END AS sent_flag,
        CASE
            WHEN bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2 THEN 0
            WHEN EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at >= bg.planned_send_date
                  AND s.settled_at <= bg.planned_send_date + INTERVAL 3 DAY
            ) THEN 1 ELSE 0
        END AS reactivated_within_3d,
        CASE
            WHEN bg.policy_name <> 'Policy_2_StopRule' THEN 0
            WHEN bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2 THEN ts.non_reactive_streak_after
            WHEN EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at >= bg.planned_send_date
                  AND s.settled_at <= bg.planned_send_date + INTERVAL 3 DAY
            ) THEN 0
            ELSE ts.non_reactive_streak_after + 1
        END AS non_reactive_streak_after,
        CASE
            WHEN bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2 THEN 0
            WHEN bg.notification_blocked_at IS NOT NULL
              AND bg.notification_blocked_at >= bg.planned_send_date
              AND bg.notification_blocked_at <= bg.planned_send_date + INTERVAL 7 DAY
            THEN 1 ELSE 0
        END AS blocked_after_send
    FROM treatment_sim ts
    JOIN basic_gate bg
      ON bg.scenario_name = ts.scenario_name
     AND bg.policy_name = ts.policy_name
     AND bg.user_id = ts.user_id
     AND bg.seq = ts.seq + 1
    WHERE bg.ab_group <> 'Control'
      AND bg.pass_basic_gate = 1
),
treatment_user_outcome AS (
    SELECT
        scenario_name,
        policy_name,
        ab_group,
        user_id,
        max(reactivated_within_3d) AS user_reactivated_within_3d,
        max(blocked_after_send) AS user_blocked
    FROM treatment_sim
    WHERE sent_flag = 1
    GROUP BY scenario_name, policy_name, ab_group, user_id
),
control_windows AS (
    SELECT
        bg.scenario_name,
        bg.policy_name,
        bg.user_id,
        bg.ab_group,
        bg.planned_send_date,
        CASE WHEN EXISTS (
            SELECT 1
            FROM settlements s
            WHERE s.user_id = bg.user_id
              AND s.settled_at >= bg.planned_send_date
              AND s.settled_at <= bg.planned_send_date + INTERVAL 3 DAY
        ) THEN 1 ELSE 0 END AS reactivated_within_3d,
        CASE WHEN bg.notification_blocked_at IS NOT NULL
              AND bg.notification_blocked_at >= bg.planned_send_date
              AND bg.notification_blocked_at <= bg.planned_send_date + INTERVAL 7 DAY
             THEN 1 ELSE 0 END AS blocked_in_window
    FROM basic_gate bg
    WHERE bg.ab_group = 'Control'
      AND bg.pass_basic_gate = 1
),
control_user_outcome AS (
    SELECT
        scenario_name,
        policy_name,
        ab_group,
        user_id,
        max(reactivated_within_3d) AS user_reactivated_within_3d,
        max(blocked_in_window) AS user_blocked
    FROM control_windows
    GROUP BY scenario_name, policy_name, ab_group, user_id
),
user_outcome AS (
    SELECT * FROM treatment_user_outcome
    UNION ALL
    SELECT * FROM control_user_outcome
),
policy_agg AS (
    SELECT
        scenario_name,
        policy_name,
        ab_group,
        count(*) AS sent_users,
        sum(user_reactivated_within_3d) AS reactivated_users,
        count(*) - sum(user_reactivated_within_3d) AS non_reactivated_users,
        sum(user_reactivated_within_3d) * 1.0 / count(*) AS reactivation_rate_3d,
        sum(user_blocked) * 1.0 / count(*) AS notification_block_rate
    FROM user_outcome
    GROUP BY scenario_name, policy_name, ab_group
),
control_rate AS (
    SELECT scenario_name, policy_name, reactivation_rate_3d AS control_reactivation_rate_3d
    FROM policy_agg
    WHERE ab_group = 'Control'
)
SELECT
    pa.scenario_name,
    pa.policy_name,
    pa.ab_group,
    pa.sent_users,
    pa.reactivated_users,
    pa.non_reactivated_users,
    pa.reactivation_rate_3d,
    pa.reactivation_rate_3d - cr.control_reactivation_rate_3d AS reactivation_uplift_vs_control,
    pa.notification_block_rate
FROM policy_agg pa
LEFT JOIN control_rate cr
  ON cr.scenario_name = pa.scenario_name
 AND cr.policy_name = pa.policy_name
ORDER BY
    pa.scenario_name,
    pa.policy_name,
    CASE pa.ab_group WHEN 'Control' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 9 END;
