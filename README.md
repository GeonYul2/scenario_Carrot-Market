# Carrot Market CRM Reactivation Analysis Scenario

STEP6는 V3에서 '타이밍 추정'이 아닌 '운영 정책 비교' 중심으로 재설계했습니다.
목표는 정책별 발송 성과(재활성화/Uplift)와 가드레일(알림 차단)을 함께 보고 실제 운영 의사결정을 지원하는 것입니다.

- Policy_0_Baseline: 기준일 1회 발송(현행 베이스라인)
- Policy_1_CooldownCap2: 7일 쿨다운 + 30일 내 최대 2회 발송
- Policy_2_StopRule: 직전 2회 연속 미재활성화면 다음 발송 중단(hold)
- Control 정의: holdout(미발송)으로 처리하고, 동일 발송 예정일 기준 3일 자연 재활성화율을 비교군으로 사용
- Eligible: push_on=1, 차단 상태 아님(발송 시점 기준), 중복 발송 방지, 최근 활동 유저 제외
- Priority: 고위험군 + 시급 상승폭을 결합한 priority_score, 상위 비율(top_k_ratio) 시나리오 비교
- 반응 정의: 발송 후 3일 내 settlements 발생을 재활성화 proxy로 사용
- Stop rule 구현: 실제 발송된 이벤트 이력 기준(재귀 시뮬레이션)으로 다음 발송 여부 결정
- 핵심 지표: sent_users, reactivated_users, non_reactivated_users, reactivation_rate_3d, reactivation_uplift_vs_control, notification_block_rate

V2의 expected_next_active_date + timing_segment(Early/On-Time/Late) 방식은 프로젝트에서 제거했습니다.
해당 방식은 휴리스틱 가정 의존이 커서 민감도가 높고, 빈도/쿨다운/스톱룰 같은 운영 정책 의사결정과 직접 연결이 약했습니다.
따라서 STEP6 기본 분석 흐름은 V3 정책 시뮬레이션으로 전환했습니다.
