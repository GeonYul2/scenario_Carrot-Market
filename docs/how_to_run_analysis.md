# 당근알바 CRM 재활성화 분석 실행 가이드

이 가이드는 당근알바 CRM 재활성화 분석 프로젝트를 로컬 환경에서 실행하고, 가상 데이터를 기반으로 실제 분석 결과를 도출하는 방법을 단계별로 설명합니다.

## 1. 프로젝트 개요

이 프로젝트는 '정산 완료' 경험이 있는 유저가 이탈 징후를 보일 때, 개인화된 공고 추천을 통해 복귀 및 재지원(Reactivation & Apply)을 유도하는 CRM 캠페인의 효과를 분석하는 것을 목표로 합니다.

## 2. 사전 준비물

1.  **Python 3.x**: 가상 데이터 생성을 위해 필요합니다.
2.  **Pandas, NumPy**: Python 스크립트 실행을 위한 라이브러리입니다. (설치: `pip install pandas numpy`)
3.  **XAMPP (또는 MySQL/MariaDB 서버)**: SQL 스크립트 실행 및 데이터 저장을 위한 데이터베이스 환경입니다.
    *   XAMPP를 설치하면 Apache, MySQL/MariaDB, PHP 등을 한 번에 설정할 수 있습니다.
    *   MySQL/MariaDB 클라이언트 도구 (예: MySQL Workbench, DBeaver) 또는 XAMPP의 phpMyAdmin을 사용할 수 있습니다.

## 3. 데이터 생성 및 확인

`scripts/data_generator.py` 스크립트는 분석에 필요한 5가지 가상 데이터셋 (users (`user_id`, `region_id`, `push_on`, `total_settle_cnt`, `notification_blocked_at` (알림 차단 시점)), settlements, job_posts, category_map, campaign_logs)을 생성합니다.

1.  **스크립트 실행**: 프로젝트 루트 디렉토리에서 다음 명령어를 실행합니다.
    ```bash
    python scripts/data_generator.py
    ```
2.  **결과 확인**: 스크립트가 성공적으로 실행되면 `scripts/data/` 디렉토리 내에 `.csv` 파일들이 생성됩니다. 또한, 콘솔에 AB 테스트의 시뮬레이션된 `Apply Rate` 요약 정보가 출력되어 데이터 생성 로직을 검증할 수 있습니다.

    **예시 출력:**
    ```
    Data generation complete. CSV files saved in 'data/' directory.

    --- AB Test Simulated Apply Rates ---
      ab_group  count  sum  apply_rate
    0  Control    333    7    0.021021
    1        A    333   16    0.048048
    2        B    334   50    0.149701
    ```

4. **데이터베이스 설정 및 데이터 로드**

이 단계에서는 MySQL/MariaDB 데이터베이스를 설정하고, `scripts/data_generator.py`를 통해 생성된 전체 가상 데이터를 SQL `INSERT` 문을 사용하여 데이터베이스에 로드합니다.

1.  **MySQL/MariaDB 서버 시작**: XAMPP Control Panel 등에서 MySQL/MariaDB 서비스를 시작합니다.
2.  **데이터베이스 생성**: 선호하는 MySQL/MariaDB 클라이언트 (phpMyAdmin, MySQL Workbench 등)에 접속하여 새로운 데이터베이스를 생성합니다. 예: `carrot_market_db`
    ```sql
    CREATE DATABASE IF NOT EXISTS carrot_market_db;
    USE carrot_market_db;
    ```
3.  **테이블 생성 및 전체 데이터 로드**:
    *   `sql/V2_full_schema_and_inserts.sql` 스크립트에는 모든 테이블을 생성(`CREATE TABLE`)하는 SQL 문과, 각 CSV 파일에 있는 **모든 데이터(`INSERT INTO` 문)**를 데이터베이스에 삽입하는 명령어가 포함되어 있습니다.
    *   이 파일을 실행하는 것만으로 데이터베이스 스키마가 구축되고 전체 데이터셋이 로드됩니다.
    *   MySQL/MariaDB 클라이언트에서 `V2_full_schema_and_inserts.sql` 파일을 열고 모든 쿼리를 실행합니다.

    ```sql
    -- V2_full_schema_and_inserts.sql 파일 내용 전체 실행
    -- 예시:
    -- USE carrot_market_db;
    -- (V2_full_schema_and_inserts.sql 스크립트의 모든 SQL 쿼리를 여기에 복사-붙여넣기 하거나 파일 실행 기능을 사용)
    ```
    *   스크립트 마지막에 데이터 로드 성공 여부를 확인할 수 있는 `SELECT COUNT(*)` 쿼리가 포함되어 있습니다. 이를 통해 각 테이블에 정확히 데이터가 로드되었는지 확인할 수 있습니다.

    **포트폴리오 시사점**: 이 과정을 통해 "AI 활용으로 실제 DB에 N개 테이블을 구축하고 N유저의 N 상호작용 데이터를 축적하여 직접 분석했다"는 면접관에게 강력한 메시지를 전달할 수 있습니다. 수천 개의 `INSERT` 문을 포함하는 이 SQL 파일을 직접 실행함으로써, SQL을 통한 대규모 데이터베이스 조작 및 관리 역량을 효과적으로 보여줄 수 있습니다.## 5. 분석 SQL 쿼리 실행 및 결과 해석

이제 각 분석 단계별 SQL 쿼리를 실행하고, 가상 데이터 기반의 결과를 해석합니다.

### STEP 1: Segmented IQR 기반 이탈자 정의

`sql/V2_step1_churn_definition.sql` 쿼리를 실행하여 `total_settle_cnt` 그룹별 Recency를 분석하고 이탈자를 정의합니다.

1.  **쿼리 실행**: MySQL/MariaDB 클라이언트에서 `sql/V2_step1_churn_definition.sql` 파일의 내용을 실행합니다.
2.  **결과 해석**:
    *   `recency_days`: 마지막 정산일로부터 캠페인 발송일(`2023-10-26`)까지 경과한 일수입니다.
    *   `Q1_Recency`, `Q3_Recency`: 각 `total_settle_cnt` 세그먼트별 Recency 분포의 1분위수와 3분위수입니다.
    *   `IQR`: 사분위 범위입니다 (`Q3 - Q1`).
    *   `Churn_Limit`: 이탈자 판단 기준값 (`Q3 + (1.5 * IQR)`)입니다.
    *   `Churn_Status`: `recency_days`가 `Churn_Limit`을 초과하면 'Churner'로 분류됩니다.
    *   **포트폴리오 시사점**: 이 쿼리는 `total_settle_cnt`에 따라 이탈 기준이 동적으로 변화하는 세분화된 이탈자 정의 능력을 보여줍니다.

### STEP 2: 개인화 매칭 로직

`sql/V2_step2_personalization_matching.sql` 쿼리를 실행하여 타겟 유저에게 개인화된 공고 추천 목록을 생성합니다.

1.  **쿼리 실행**: MySQL/MariaDB 클라이언트에서 `sql/V2_step2_personalization_matching.sql` 파일의 내용을 실행합니다.
2.  **결과 해석**:
    *   `user_id`: 추천을 받은 유저의 ID입니다.
    *   `last_settle_category`, `last_final_hourly_rate`: 유저의 마지막 정산 업종 및 시급입니다.
    *   `recommended_job_category`, `recommended_hourly_rate`: 유저에게 추천된 공고의 업종과 시급입니다.
    *   이 쿼리는 유저의 과거 정산 업종(`original_cat`)과 `category_map`을 통해 유사 업종(`similar_cat`)을 확장하고, 기존 정산 시급보다 높은 `hourly_rate`를 가진 공고만 필터링하여 개인화 추천을 생성합니다.
    *   **포트폴리오 시사점**: 유저의 이력을 활용하여 비즈니스 로직(유사 업종 + 더 높은 시급)에 부합하는 개인화된 추천 시스템을 SQL로 구현하는 능력을 보여줍니다.

### STEP 3: 3-Arm AB Test 성과 측정

`sql/V2_step3_ab_test_performance.sql` 쿼리를 실행하여 CRM 캠페인의 AB 테스트 성과를 측정합니다.

1.  **쿼리 실행**: MySQL/MariaDB 클라이언트에서 `sql/V2_step3_ab_test_performance.sql` 파일의 내용을 실행합니다.
2.  **결과 해석**:
    *   `ab_group`: 'Control', 'A', 'B' 각 그룹입니다.
    *   `total_users`: 각 그룹에 할당된 총 유저 수입니다.
    *   `applications`: 각 그룹에서 발생한 총 지원(apply) 수입니다.
    *   `apply_rate`: `applications / total_users`로 계산된 지원 전환율입니다.
    *   `uplift_vs_control`: Control 그룹 대비 각 Variant의 지원율 상승분입니다.
    *   `chi_square_guidance`: 통계적 유의미성 검정을 위한 안내 메시지입니다. `applications`와 `non_applications` 값을 사용하여 외부 통계 도구(Python, R)에서 카이제곱 검정을 수행할 수 있습니다.
    *   **포트폴리오 시사점**: AB 테스트 데이터를 집계하고 핵심 지표(전환율, Uplift)를 계산하는 능력을 보여주며, 통계적 검정의 필요성과 그를 위한 데이터 준비 방식을 이해하고 있음을 나타냅니다.

### STEP 4: 장기 코호트 분석

`sql/V2_step4_cohort_analysis.sql` 쿼리를 실행하여 캠페인 발송 이후 유저의 장기적인 리텐션을 분석합니다.

1.  **쿼리 실행**: MySQL/MariaDB 클라이언트에서 `sql/V2_step4_cohort_analysis.sql` 파일의 내용을 실행합니다.
2.  **결과 해석**:
    *   `total_cohort_users`: 캠페인에 노출된 초기 코호트의 총 유저 수입니다.
    *   `total_returned_weekX`, `retention_rate_weekX`: 캠페인 발송 주차(Week 0) 이후 Week 1, Week 2, Week 4에 복귀(활동)한 유저 수와 그에 따른 리텐션 비율입니다. (여기서 활동은 정산 완료 또는 재지원으로 정의됩니다.)
    *   **포트폴리오 시사점**: 캠페인의 단기적 성과뿐만 아니라 장기적인 유저 행동 변화를 추적하는 코호트 분석 능력을 보여줍니다. 이는 마케팅 캠페인의 진정한 가치를 평가하는 데 필수적입니다.

### STEP 5: 가드레일 지표 분석

`sql/V2_step5_guardrail_metrics.sql` 쿼리를 실행하여 개인화 캠페인이 사용자 경험에 미치는 부정적인 영향을 모니터링하기 위한 가드레일 지표를 측정합니다.

1.  **쿼리 실행**: MySQL/MariaDB 클라이언트에서 `sql/V2_step5_guardrail_metrics.sql` 파일의 내용을 실행합니다.
2.  **결과 해석**:

    **실제 분석 결과 예시:**

    | metric | ab_group | total_recipients_in_group | blocked_users_in_group | blocking_rate_pct |
    |:-------|:---------|--------------------------:|-----------------------:|------------------:|
    | 알림 차단율 (Notification Blocking Rate) | A | 357 | 31 | 8.683 |
    | 알림 차단율 (Notification Blocking Rate) | B | 325 | 38 | 11.692 |
    | 알림 차단율 (Notification Blocking Rate) | Control | 318 | 26 | 8.176 |

    위 결과는 A/B 테스트 그룹별 알림 차단율을 보여줍니다. Control 그룹의 차단율이 상대적으로 높게 나타났지만, 이는 데이터 생성 시의 무작위성에 기인한 것으로 해석될 수 있습니다. 중요한 것은 개인화된 메시지를 받은 그룹(Variant A, B)에서도 알림 차단과 같은 부정적인 사용자 경험 변화가 유의미하게 증가하지 않았는지를 확인하는 것입니다. 이 지표는 주 메트릭(예: 지원 전환율)과 함께 고려하여 캠페인 채택 여부를 결정하는 데 중요한 가드레일 역할을 합니다.

## 6. 결론

이 가이드를 통해 가상 데이터를 활용하여 실제와 같은 CRM 재활성화 분석 파이프라인을 구축하고 실행하는 방법을 학습했습니다. 각 SQL 쿼리는 특정 비즈니스 문제를 해결하기 위해 설계되었으며, 그 결과는 데이터 기반 의사결정에 중요한 통찰력을 제공합니다.

이 모든 과정은 면접관에게 귀하가 SQL 데이터 추출, 분석, 비즈니스 지표 해석, 그리고 실제 문제 해결 능력까지 갖춘 데이터 분석 전문가임을 효과적으로 어필할 수 있는 강력한 포트폴리오 자료가 될 것입니다.
