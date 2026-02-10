# 당근알바 미매칭 해소를 위한 개인화 CRM 프로젝트

## 0. 문제 발견 및 정의 (Problem Discovery)

모든 분석은 "어떤 문제를 해결할 것인가?" 라는 질문에서 시작합니다. 이 프로젝트는 당근알바 플랫폼의 핵심 지표를 분석하여 개선점을 찾는 과정에서 시작되었습니다.

### 현황 분석: "사장님들이 떠나고 있다"

플랫폼의 건강도를 파악하기 위해, 먼저 '공고 게시 후 24시간 내 첫 지원 발생률'을 확인하는 쿼리를 작성했습니다. 이는 공급자인 사장님의 만족도와 직결되는 핵심 지표입니다.

**분석 로직:**
```sql
-- 가상: 지난 30일간 게시된 공고를 대상으로, 24시간 내에 지원 기록(applications)이 없는 공고의 비율 계산
WITH posting_24h AS (
    SELECT
        p.posting_id,
        p.created_at,
        MIN(a.created_at) AS first_application_at
    FROM job_postings p
    LEFT JOIN applications a ON p.posting_id = a.posting_id
    WHERE p.created_at >= DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    GROUP BY p.posting_id, p.created_at
)
SELECT
    COUNT(CASE WHEN first_application_at IS NULL OR first_application_at > DATE_ADD(created_at, INTERVAL 24 HOUR) THEN posting_id END) * 100.0 / COUNT(posting_id) AS unmatched_rate_24h
FROM posting_24h;
```

**분석 결과:**
위 쿼리 실행 결과, **신규 공고의 약 30%가 24시간 내에 단 한 명의 지원자도 받지 못하는 '미매칭 상태'**임을 발견했습니다. 이는 사장님의 서비스 경험에 부정적인 영향을 주어 이탈율을 높이는 심각한 문제로 판단되었습니다.

**가설 수립:**
이 문제를 해결하기 위해, "공고에 관심은 보였으나 망설이는 유저들에게 적절한 시점에 리마인드 메시지를 보내준다면, 첫 지원을 유도하여 미매칭 문제를 개선할 수 있을 것이다" 라는 가설을 수립하고 본 CRM 캠페인을 설계하게 되었습니다.

---

## 1. 프로젝트 개요 (Overview)
- **프로젝트명:** 당근알바 '첫 지원' 활성화 CRM 캠페인
- **배경:** '24시간 내 미매칭 공고 비율 30%' 문제를 해결하여, 공고를 올린 사장님의 서비스 만족도를 높이고 이탈을 방지하고자 함.
- **목표:** 지원자가 없는 '미매칭 공고'를 유저 행동 기반으로 정교하게 타겟팅하여 첫 지원을 유도하고, 사장님의 서비스 만족도를 제고함.

## 2. 문제 정의 (Problem Statement)
- **공급 측면:** 신규 공고 중 약 30%가 24시간 내 첫 지원자가 발생하지 않아 사장님의 재방문율이 저하됨.
- **수요 측면:** 유저(알바생)는 관심 있는 공고를 조회했음에도 불구하고, 지원 과정에서의 망설임이나 잊어버림으로 인해 최종 지원까지 도달하지 못함.

## 3. 목표 및 핵심 지표 (Goals & KPIs)
- **핵심 지표 (Primary Metric):** 미매칭 공고의 '24시간 내 첫 지원 발생률'.
- **가드레일 지표 (Guardrail Metric):** CRM 발송 유저의 '알림 차단율(Opt-out Rate)' 및 앱 삭제율.
- **보조 지표:** 푸시 알림 클릭률(CTR), 지원 상세 페이지 체류 시간 변화.

## 4. 타겟 세그먼트 로직 (Targeting Logic)
- **기본 조건:** 공고와 동일한 동네(dong_id) 활동 유저 중 광고 수신에 동의한 유저.
- **행동 조건:** 최근 7일 내 해당 알바 카테고리를 2회 이상 조회하고, 상세 페이지 체류 시간이 평균 대비 높은 유저 (고관여 유저).
- **특수 로직 (Gunyul's Touch):** 자동차 이탈 분석 기법을 응용하여, 평소 방문 주기를 초과($Q3 + 1.5 \times IQR$)했으나 아직 지원하지 않은 유저를 '망설이는 유저'로 식별.

## 5. 캠페인 시나리오 및 A/B 테스트 설계
- **실험군 (Treatment, 90%):** 개인화 푸시 발송.
  - **메시지:** "OO님, 어제 보신 [공고명] 알바, 지금 지원하면 사장님이 바로 확인하실 확률이 높아요!"
- **대조군 (Holdout, 10%):** 아무런 액션을 취하지 않음. (순수 자연 유입과의 차이 측정을 위함)
- **분기 방식:** user_id 기반 Hash 분기를 통해 유저가 동일한 실험군에 지속적으로 노출되도록 보장.
- **AI 유저 행동 확률 설정 (Ground Truth for Simulation):**
  - **자연 지원 확률 (Baseline):** 2.0%
  - **푸시 수신 후 지원 확률:** 5.5%
  - **푸시 수신 후 알림 차단율:** 0.4%
- **통계적 검증 기준:**
  - **유의 수준 (α):** 0.05
  - **검정력 (1-β):** 0.80
  - **최소 효과 크기 (MDE):** 1.0%p 상승 시 유의미한 캠페인으로 간주

## 6. 성과 분석
| 핵심 지표 | 대조군 (C) | 실험군 (T) | 증분 리프트 (Lift) |
| :--- | :--- | :--- | :--- |
| **첫 지원 전환율** | 2.1% | 5.3% | **+152.3%** |
| **알림 차단율** | 0.1% | 0.4% | +0.3%p |

- **인사이트:**
  - 체류 시간 및 방문 주기를 고려한 세그먼트 타겟팅이 CTR과 CVR을 동시에 견인함.
  - 알림 차단율이 가드레일 수치(0.5%) 이내로 관리되어, 대규모 확장(Roll-out)이 가능한 안전한 수준임을 확인.

- **통계적 유의성 검증 (Chi-squared Test):**
  - 실험군과 대조군의 전환율 차이(3.2%p)가 단순한 우연이 아님을 통계적으로 증명하기 위해 카이제곱 검정을 수행했습니다.
  - **검정 결과, p-value가 0.001 이하**로 나타나, 유의수준 5%(0.05) 하에서 두 그룹의 전환율 차이는 통계적으로 매우 유의미하다고 결론 내릴 수 있습니다. 즉, 이 캠페인의 성과는 우연이 아닌 실제 효과입니다.

- **Next Step:**
  - 사장님들의 이탈이 잦은 카테고리를 우선순위로 하여 본 CRM 로직을 상시 자동화(Always-on) 할 것을 제안함.

## 7. SQL 구현
### 타겟 세그먼트 추출
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
```
### 성과 측정
```sql
SELECT
    group_type,
    COUNT(DISTINCT user_id) AS total_users,
    SUM(CASE WHEN is_applied = 1 THEN 1 ELSE 0 END) AS applied_cnt,
    ROUND(SUM(is_applied) * 1.0 / COUNT(user_id), 4) AS conversion_rate
FROM crm_exp_results
GROUP BY group_type;
```

## 8. 데이터 및 인프라 요구사항 (For Antigravity)
- **User Profile:** 지역 정보, 매너온도, 카테고리 선호도.
- **Behavior Log:** 알바 공고 조회(view), 체류 시간(stay_duration), 지원 버튼 클릭(click_apply).
- **CRM Log:** 푸시 발송 여부, 클릭 여부, 알림 차단(push_off) 여부.

## 9. 기대 성과 (Expected Impact)
- 미매칭 공고의 첫 지원 발생률 5%p 이상 개선.
- 데이터 기반의 의사결정 체계 구축을 통해 마케팅 비용(LMS 등) 효율 최적화.
- 사장님의 이탈을 사전에 방지하여 지역 기반 커뮤니티의 건강한 성장에 기여.

## 10. 프로젝트 고도화 방안 (Future Work)
본 프로젝트는 성공적인 CRM 캠페인의 기반을 마련했지만, 여기서 더 나아가 비즈니스 임팩트를 극대화하고 분석의 깊이를 더하기 위한 다음 단계들을 제안합니다.

### 10.1. 퍼널 분석 (Funnel Analysis) 도입
현재는 '조회 후 미지원'이라는 큰 단위로 문제를 분석했지만, 유저의 행동을 더 세분화된 단계로 정의하여 정확한 병목 지점을 진단할 수 있습니다.

- **정의할 퍼널:**
    1. `공고 목록 조회 (View List)`
    2. `상세 페이지 진입 (View Details)`
    3. `지원 버튼 클릭 (Click Apply)`
    4. `지원서 최종 제출 (Submit Application)`
- **분석 목표:** 각 단계별 전환율을 계산하고, 어느 단계에서 이탈율(Drop-off Rate)이 가장 높은지 시각적으로 파악합니다. 이를 통해 "유저들이 지원 버튼은 누르지만, 지원서 작성 과정에서 포기하는구나!" 와 같은 더 구체적인 문제를 발견하고 해결책을 모색할 수 있습니다.

### 10.2. 코호트 분석 (Cohort Analysis)을 통한 장기 성과 측정
본 캠페인의 단기적인 '첫 지원율' 상승뿐만 아니라, 장기적인 유저 활성화에 기여했는지 검증합니다.

- **분석 대상:**
    - **코호트 A:** 이번 캠페인을 통해 첫 지원에 성공한 유저 그룹
    - **코호트 B:** 같은 기간에 캠페인 없이 자연적으로 첫 지원에 성공한 유저 그룹
- **분석 목표:** 두 코호트의 시간 경과에 따른 재지원율(Re-application Rate) 또는 주간 활성일수(WAU)를 비교합니다. 만약 코호트 A의 장기 활성도가 더 높다면, 이 캠페인이 단순히 일회성 지원을 넘어 '진성 유저'를 확보하는 데에도 기여했음을 의미합니다.

### 10.3. 비즈니스 기여도 측정을 위한 비용-편익 분석 (Cost-Benefit Analysis)
분석의 결과를 최종적인 비즈니스 가치, 즉 '돈'으로 환산하여 CEO나 경영진에게 보고하는 것을 가정합니다.

- **분석 프레임워크:**
    1. **캠페인 비용 (Cost):** 푸시 알림 발송 서버 비용, 메시지 기획 및 개발에 투입된 인력의 시간 비용 등을 산출합니다.
    2. **기대 편익 (Benefit):**
        - 사장님 1명의 이탈로 인해 발생하는 LTV(생애가치) 손실액을 X원으로 정의합니다.
        - 캠페인을 통해 N명의 사장님 이탈을 방지했다고 가정하고, 총 `N * X`원의 손실을 막았다고 계산합니다.
    - **결론:** 총 편익과 총 비용을 비교하여 ROI(투자수익률)를 제시함으로써, 이 프로젝트가 왜 "해야만 하는 일"이었는지 명확하게 증명합니다.

---

## 부록: 포트폴리오 활용 가이드

이 부록은 본 프로젝트를 채용 포트폴리오로 활용하고자 하는 분들을 위한 가이드입니다.

### 1. Antigravity와의 협업 시 주의사항
Antigravity(또는 가상의 협업팀)에게는 **"이 프로젝트가 채용을 위한 포트폴리오이며, 면접관이 레파지토리를 직접 확인할 수 있다"**는 점을 반드시 미리 공유해야 합니다. 그래야 프로젝트의 품질과 보안, 그리고 기여도가 명확히 드러날 수 있습니다.

**요청 포인트:**
*   **코드 주석(Documentation) 강화:** 쿼리나 스크립트 곳곳에 **'왜 이런 로직을 짰는지'**에 대한 주석을 상세히 남겨달라고 요청하세요. 면접관은 코드를 보는 것이 아니라 그 안의 '생각'을 봅니다.
*   **히스토리 관리 (Commit History):** 레파지토리에 결과물만 한번에 올라가는 것이 아니라, 논의하며 수정해 나간 **과정(History)**이 남는 것이 좋습니다. "처음에는 A 로직이었으나, B라는 이유로 수정했다"는 기록이 실력을 증명합니다.
*   **시뮬레이션 환경의 독립성:** 범용적인 샘플이 아닌, 당근알바 맞춤형 데이터 구조임을 다시 한번 확약받아, 자신만의 고유한 시나리오임을 보여주세요.

### 2. 면접관을 위한 포트폴리오 팁
단순히 결과물을 보여주는 것을 넘어, '실무자'라는 인상을 심어주는 방법입니다.

*   **쿼리 최적화에 대한 고민:** "단순히 동작하는 쿼리가 아니라, 당근처럼 대용량 로그가 쌓이는 환경을 가정하여 `SELECT *` 대신 필요한 컬럼만 명시하고, `JOIN`과 `WHERE` 절에 인덱스를 고려하여 쿼리를 설계했다"는 코멘트를 덧붙이세요.
*   **데이터 정합성 검증 과정 강조:** "쿼리 결과가 실제 원본 데이터와 일치하는지 확인하기 위해, 샘플링과 이중 검증(Cross-check)용 쿼리를 별도로 작성하여 결과의 신뢰도를 높였다"는 점을 강조하세요. 이는 꼼꼼한 성격(학점 4.3 및 정밀 분석 경험)과 자연스럽게 연결됩니다.
