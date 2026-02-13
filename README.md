# Carrot Market CRM Reactivation Analysis

고위험군 CRM 타겟팅을 위해, 사용자 활동주기 기반 이탈 위험군을 정의하고 개인화 메시지 실험(A/B/C)의 성과를 검증한 프로젝트입니다.

## 데이터 구성
- `users` (10000), `settlements` (49715), `job_posts` (3000), `category_map` (16), `campaign_logs` (13046)

## 분석 흐름
1. STEP1 고위험군 정의: `sql/V2_step1_churn_definition.sql`
2. STEP2 잠재 매칭(진단): `sql/V2_step2_personalization_matching.sql`
3. STEP2b 실행 매칭(A/B 발송): `sql/V2_step2b_personalization_matching_executable.sql`
4. STEP3 AB 성과: `sql/V2_step3_ab_test_performance.sql`
5. STEP4 코호트 리텐션: `sql/V2_step4_cohort_analysis.sql`
6. STEP5 가드레일: `sql/V2_step5_guardrail_metrics.sql`

## 핵심 결과 (현재 데이터 기준)
- 고위험군 규모: `2536`
- 실행 매칭 유저(A/B): `1411`
- AB apply_rate:
  - Control `0.023641`
  - A `0.053191`
  - B `0.143365`
- 통계 검정(chi-square): `chi2=96.692068`, `p=1.008e-21`
- 차단율:
  - Control `8.274232%`
  - A `10.756501%`
  - B `10.308057%`

## 상세 분석 시나리오
- `docs/analysis_scenario.md`
