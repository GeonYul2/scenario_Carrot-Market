-- V3_step6_push_policy_simulation.sql
-- STEP6 V3: operational push policy simulation (holdout control + real send-based stop rule)

SET @campaign_date = '2023-10-26';
SET @cooldown_days = 7;
SET @recent_active_exclude_days = 7;
SET @top_k_ratio = 0.30;

WITH RECURSIVE
BaseAB AS (
    SELECT user_id, ab_group
    FROM (
        SELECT
            cl.user_id,
            cl.ab_group,
            ROW_NUMBER() OVER (PARTITION BY cl.user_id ORDER BY cl.sent_at) AS rn
        FROM campaign_logs cl
        WHERE cl.sent_at = @campaign_date
    ) x
    WHERE rn = 1
),
UserCycle AS (
    SELECT
        s.user_id,
        u.total_settle_cnt,
        DATEDIFF(MAX(s.settled_at), MIN(s.settled_at)) AS active_days,
        COUNT(*) AS settle_cnt,
        DATEDIFF(@campaign_date, MAX(s.settled_at)) AS recency_days
    FROM settlements s
    JOIN users u ON u.user_id = s.user_id
    GROUP BY s.user_id, u.total_settle_cnt
),
UserTier AS (
    SELECT
        user_id,
        recency_days,
        CASE WHEN settle_cnt > 1 THEN active_days * 1.0 / (settle_cnt - 1) END AS avg_cycle_days,
        CASE
            WHEN total_settle_cnt = 1 THEN 'Light User'
            WHEN total_settle_cnt BETWEEN 2 AND 5 THEN 'Regular User'
            ELSE 'Power User'
        END AS settle_tier
    FROM UserCycle
    WHERE settle_cnt > 1
),
TierQ3 AS (
    SELECT
        settle_tier,
        MIN(CASE WHEN q_rank = 3 THEN avg_cycle_days END) AS q3_cycle_days
    FROM (
        SELECT
            settle_tier,
            avg_cycle_days,
            NTILE(4) OVER (PARTITION BY settle_tier ORDER BY avg_cycle_days) AS q_rank
        FROM UserTier
    ) t
    GROUP BY settle_tier
),
HighRiskUsers AS (
    SELECT
        ut.user_id,
        CASE WHEN ut.recency_days > tq.q3_cycle_days THEN 1 ELSE 0 END AS is_high_risk
    FROM UserTier ut
    JOIN TierQ3 tq ON tq.settle_tier = ut.settle_tier
),
LastSettlement AS (
    SELECT
        s.user_id,
        s.category_id,
        s.final_hourly_rate,
        ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY s.settled_at DESC) AS rn
    FROM settlements s
    WHERE s.settled_at < @campaign_date
),
TargetCategory AS (
    SELECT user_id, category_id, final_hourly_rate
    FROM LastSettlement
    WHERE rn = 1
),
ExpandedCategory AS (
    SELECT tc.user_id, tc.final_hourly_rate, tc.category_id AS category_to_match
    FROM TargetCategory tc
    UNION ALL
    SELECT tc.user_id, tc.final_hourly_rate, cm.similar_cat
    FROM TargetCategory tc
    JOIN category_map cm ON cm.original_cat = tc.category_id
),
UserWageUplift AS (
    SELECT
        ec.user_id,
        MAX(jp.hourly_rate - ec.final_hourly_rate) AS max_wage_uplift
    FROM ExpandedCategory ec
    JOIN job_posts jp
      ON jp.category_id = ec.category_to_match
     AND jp.hourly_rate > ec.final_hourly_rate
    GROUP BY ec.user_id
),
CandidateUsers AS (
    SELECT
        u.user_id,
        ba.ab_group,
        u.push_on,
        u.notification_blocked_at,
        COALESCE(hr.is_high_risk, 0) AS is_high_risk,
        COALESCE(wu.max_wage_uplift, 0) AS max_wage_uplift,
        (
            CASE WHEN COALESCE(hr.is_high_risk, 0) = 1 THEN 70 ELSE 0 END
            + LEAST(COALESCE(wu.max_wage_uplift, 0) / 200, 30)
        ) AS priority_score,
        CUME_DIST() OVER (
            ORDER BY
                (
                    CASE WHEN COALESCE(hr.is_high_risk, 0) = 1 THEN 70 ELSE 0 END
                    + LEAST(COALESCE(wu.max_wage_uplift, 0) / 200, 30)
                ) DESC,
                u.user_id
        ) AS priority_cume
    FROM users u
    JOIN BaseAB ba ON ba.user_id = u.user_id
    LEFT JOIN HighRiskUsers hr ON hr.user_id = u.user_id
    LEFT JOIN UserWageUplift wu ON wu.user_id = u.user_id
),
ScenarioUsers AS (
    SELECT 'ALL_ELIGIBLE' AS scenario_name, cu.*
    FROM CandidateUsers cu
    UNION ALL
    SELECT 'TOP30_PRIORITY' AS scenario_name, cu.*
    FROM CandidateUsers cu
    WHERE cu.priority_cume <= @top_k_ratio
),
PolicySchedule AS (
    SELECT 'Policy_0_Baseline' AS policy_name, @campaign_date AS planned_send_date, 1 AS send_order
    UNION ALL SELECT 'Policy_1_CooldownCap2', @campaign_date, 1
    UNION ALL SELECT 'Policy_1_CooldownCap2', DATE_ADD(@campaign_date, INTERVAL 7 DAY), 2
    UNION ALL SELECT 'Policy_2_StopRule', @campaign_date, 1
    UNION ALL SELECT 'Policy_2_StopRule', DATE_ADD(@campaign_date, INTERVAL 3 DAY), 2
    UNION ALL SELECT 'Policy_2_StopRule', DATE_ADD(@campaign_date, INTERVAL 10 DAY), 3
),
EventBase AS (
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
    FROM ScenarioUsers su
    JOIN PolicySchedule ps ON 1 = 1
),
EventEligible AS (
    SELECT eb.*
    FROM EventBase eb
    WHERE eb.push_on = 1
      AND (eb.notification_blocked_at IS NULL OR eb.notification_blocked_at > eb.planned_send_date)
      AND NOT EXISTS (
            SELECT 1
            FROM settlements s
            WHERE s.user_id = eb.user_id
              AND s.settled_at BETWEEN DATE_SUB(eb.planned_send_date, INTERVAL @recent_active_exclude_days DAY)
                                  AND DATE_SUB(eb.planned_send_date, INTERVAL 1 DAY)
      )
),
EventWithSeq AS (
    SELECT
        ee.*,
        ROW_NUMBER() OVER (
            PARTITION BY ee.scenario_name, ee.policy_name, ee.user_id
            ORDER BY ee.planned_send_date
        ) AS seq
    FROM EventEligible ee
),
BasicGate AS (
    SELECT
        ews.*,
        CASE
            WHEN ews.policy_name = 'Policy_0_Baseline' AND ews.seq = 1 THEN 1
            WHEN ews.policy_name = 'Policy_1_CooldownCap2' AND ews.seq <= 2 THEN 1
            WHEN ews.policy_name = 'Policy_2_StopRule' AND ews.seq <= 3 THEN 1
            ELSE 0
        END AS pass_basic_gate
    FROM EventWithSeq ews
),
TreatmentSeed AS (
    SELECT
        bg.scenario_name,
        bg.policy_name,
        bg.user_id,
        bg.ab_group,
        bg.seq,
        bg.planned_send_date,
        1 AS sent_flag,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 3 DAY)
            ) THEN 1 ELSE 0
        END AS reactivated_within_3d,
        CASE
            WHEN bg.policy_name = 'Policy_2_StopRule'
             AND NOT EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 3 DAY)
            ) THEN 1 ELSE 0
        END AS non_reactive_streak_after,
        CASE
            WHEN bg.notification_blocked_at IS NOT NULL
             AND bg.notification_blocked_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 7 DAY)
            THEN 1 ELSE 0
        END AS blocked_after_send
    FROM BasicGate bg
    WHERE bg.ab_group <> 'Control'
      AND bg.pass_basic_gate = 1
      AND bg.seq = 1
),
TreatmentSim AS (
    SELECT *
    FROM TreatmentSeed

    UNION ALL

    SELECT
        bg.scenario_name,
        bg.policy_name,
        bg.user_id,
        bg.ab_group,
        bg.seq,
        bg.planned_send_date,
        CASE
            WHEN bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2 THEN 0
            ELSE 1
        END AS sent_flag,
        CASE
            WHEN (bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2) THEN 0
            WHEN EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 3 DAY)
            ) THEN 1 ELSE 0
        END AS reactivated_within_3d,
        CASE
            WHEN bg.policy_name <> 'Policy_2_StopRule' THEN 0
            WHEN (bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2) THEN ts.non_reactive_streak_after
            WHEN EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 3 DAY)
            ) THEN 0
            ELSE ts.non_reactive_streak_after + 1
        END AS non_reactive_streak_after,
        CASE
            WHEN (bg.policy_name = 'Policy_2_StopRule' AND ts.non_reactive_streak_after >= 2) THEN 0
            WHEN bg.notification_blocked_at IS NOT NULL
             AND bg.notification_blocked_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 7 DAY)
            THEN 1 ELSE 0
        END AS blocked_after_send
    FROM TreatmentSim ts
    JOIN BasicGate bg
      ON bg.scenario_name = ts.scenario_name
     AND bg.policy_name = ts.policy_name
     AND bg.user_id = ts.user_id
     AND bg.seq = ts.seq + 1
    WHERE bg.ab_group <> 'Control'
      AND bg.pass_basic_gate = 1
),
TreatmentUserOutcome AS (
    SELECT
        scenario_name,
        policy_name,
        ab_group,
        user_id,
        MAX(reactivated_within_3d) AS user_reactivated_within_3d,
        MAX(blocked_after_send) AS user_blocked
    FROM TreatmentSim
    WHERE sent_flag = 1
    GROUP BY scenario_name, policy_name, ab_group, user_id
),
ControlWindows AS (
    SELECT
        bg.scenario_name,
        bg.policy_name,
        bg.user_id,
        bg.ab_group,
        bg.planned_send_date,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM settlements s
                WHERE s.user_id = bg.user_id
                  AND s.settled_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 3 DAY)
            ) THEN 1 ELSE 0
        END AS reactivated_within_3d,
        CASE
            WHEN bg.notification_blocked_at IS NOT NULL
             AND bg.notification_blocked_at BETWEEN bg.planned_send_date AND DATE_ADD(bg.planned_send_date, INTERVAL 7 DAY)
            THEN 1 ELSE 0
        END AS blocked_in_window
    FROM BasicGate bg
    WHERE bg.ab_group = 'Control'
      AND bg.pass_basic_gate = 1
),
ControlUserOutcome AS (
    SELECT
        scenario_name,
        policy_name,
        ab_group,
        user_id,
        MAX(reactivated_within_3d) AS user_reactivated_within_3d,
        MAX(blocked_in_window) AS user_blocked
    FROM ControlWindows
    GROUP BY scenario_name, policy_name, ab_group, user_id
),
UserOutcome AS (
    SELECT * FROM TreatmentUserOutcome
    UNION ALL
    SELECT * FROM ControlUserOutcome
),
PolicyAgg AS (
    SELECT
        scenario_name,
        policy_name,
        ab_group,
        COUNT(*) AS sent_users,
        SUM(user_reactivated_within_3d) AS reactivated_users,
        COUNT(*) - SUM(user_reactivated_within_3d) AS non_reactivated_users,
        SUM(user_reactivated_within_3d) * 1.0 / COUNT(*) AS reactivation_rate_3d,
        SUM(user_blocked) * 1.0 / COUNT(*) AS notification_block_rate
    FROM UserOutcome
    GROUP BY scenario_name, policy_name, ab_group
),
ControlRate AS (
    SELECT
        scenario_name,
        policy_name,
        reactivation_rate_3d AS control_reactivation_rate_3d
    FROM PolicyAgg
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
FROM PolicyAgg pa
LEFT JOIN ControlRate cr
  ON cr.scenario_name = pa.scenario_name
 AND cr.policy_name = pa.policy_name
ORDER BY
    pa.scenario_name,
    pa.policy_name,
    FIELD(pa.ab_group, 'Control', 'A', 'B');
