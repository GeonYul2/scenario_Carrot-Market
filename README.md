# Carrot Market CRM Reactivation Analysis

당근알바 사용자 데이터를 기반으로, 이탈 징후 유저를 조기 식별하고 CRM 액션의 효과를 검증한 분석 프로젝트입니다.  
핵심 목표는 단순 전환율 비교가 아니라, **타겟 정의 정확도 + 액션 효과 + 장기 유지 + 사용자 피로도**를 함께 관리하는 실무형 분석 체계를 제시하는 것입니다.

## 1. Project Objective

- 이탈 위험 사용자(High-Risk Candidate)를 데이터 기반으로 정의
- 개인화 타겟 추출 로직(SQL)으로 CRM 액션 설계
- A/B 성과를 사용자 단위로 측정하여 순효과(Uplift) 검증
- 코호트 리텐션 및 알림 차단율로 중장기 효과와 가드레일 점검

## 2. Data Architecture

본 프로젝트는 5개 핵심 테이블로 구성됩니다.

- `users`: 사용자 프로필 및 푸시 상태
- `settlements`: 사용자 활동(정산) 이력
- `job_posts`: 추천 가능 공고 데이터
- `category_map`: 원 카테고리-유사 카테고리 매핑
- `campaign_logs`: 캠페인 노출/반응 로그

데이터 관계는 아래와 같습니다.

```text
users (1) ────────< settlements (N)
  │                     │
  │                     └── category_id ──> category_map ──> job_posts
  │
  └───────< campaign_logs (N)
```

## 3. Analytical Flow (STEP 1~5)

### STEP 1. 고위험군 정의 (`sql/V2_step1_churn_definition.sql`)
- 사용자별 평균 이용주기(`avg_settle_cycle_days`)와 최근성(`recency_days`) 계산
- 이용량 기준 3개 티어(Light/Regular/Power) 분리
- 티어별 이용주기 Q3를 임계값으로 두고, `recency_days > Q3`인 유저를 고위험군으로 정의

### STEP 2. 개인화 타겟 추출 (`sql/V2_step2_personalization_matching.sql`)
- 사용자 최근 정산 업직종을 기준으로 추천 카테고리 후보 확장
- `category_map`을 통해 유사 업직종까지 매칭
- 최근 정산 시급보다 높은 공고만 선별해 실질적 유인 있는 타겟 풀 구성

### STEP 3. A/B 성과 측정 (`sql/V2_step3_ab_test_performance.sql`)
- 사용자 단위로 캠페인 반응 여부 집계(`is_applied`)
- 그룹별 `apply_rate`, `uplift_vs_control` 산출
- `applications`, `non_applications`를 함께 제공해 통계 검정(chi-square 등) 가능하도록 설계

### STEP 4. 코호트 리텐션 분석 (`sql/V2_step4_cohort_analysis.sql`)
- 캠페인 이후 코호트(Post)와 캠페인 비노출 비교 코호트(Pre) 구성
- 코호트 시작일 기준 Week1/Week2/Week4 리텐션 계산
- 단기 전환이 장기 이용으로 이어지는지 검증

### STEP 5. 가드레일 분석 (`sql/V2_step5_guardrail_metrics.sql`)
- 그룹별 알림 차단율(`notification_blocked_at`) 측정
- 성과 개선과 사용자 피로도 악화 간 트레이드오프 점검

## 4. KPI Framework

- 전환 성과: `apply_rate`, `uplift_vs_control`
- 장기 성과: `retention_rate_week1/2/4`
- 가드레일: `blocking_rate_pct`

의사결정 우선순위:
1. Uplift가 양(+)인지 확인
2. 리텐션 저하가 없는지 확인
3. 알림 차단율 악화 여부 확인

## 5. Reproducibility & Validation

직접 DB 검증이 제한되는 환경을 고려해, `CSV ↔ SQL` 정합성을 유지하는 방식으로 재현성을 확보했습니다.

- 데이터 경로 기준: `scripts/data/`
- 생성 스크립트: `scripts/data_generator.py`
- 스키마/적재: `sql/V2_full_schema_and_inserts.sql` 또는 `sql/V2_load_data.sql`
- 실행 가이드: `docs/how_to_run_analysis.md`

## 6. Tech Stack

- SQL (MySQL/MariaDB)
- Python (데이터 생성 및 전처리)
- CSV 기반 재현 환경

## 7. Business Contribution

- CRM 타겟 선정을 규칙 기반이 아닌 행동 데이터 기반으로 고도화
- 개인화 조건(업직종/시급)을 반영한 실행 가능한 액션 기준 제시
- 단기 전환 중심 평가를 넘어 리텐션/피로도까지 포함한 실무형 성과 해석 프레임 구축
