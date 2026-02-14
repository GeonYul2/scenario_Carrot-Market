# Portfolio Capture Sheet (Slide 2)

> 본 문서는 **포트폴리오 캡처용**으로, 프로젝트 핵심 특징(좌/우 2분할)과 증빙 스니펫(SQL/결과표/룰)을 한 파일에 모아둔 자료입니다.  
> 데이터/로그는 **가상 데이터 기반 시나리오 검증**입니다.

---

## 좌측: 타겟 설계(세그먼트·고위험군·실행가능 모집단)

- 세그먼트(Light/Regular/Power) 및 **Q3 기반 고위험군** 기준을 정의했음
- 개인화 매칭 조건(지역/시급/유사 업종)으로 **실행 가능한 모집단**만 확정했음
- 타겟 추출/매칭 조건을 **SQL 스텝으로 분리**해 재현 가능하게 구성했음

### 증빙 1) 타겟 추출 SQL 스텝 캡처

파일:
- `sql/V2_step1_churn_definition.sql`

캡처 포인트(핵심 로직):
```sql
-- 세그먼트별 Q3 산출
SegmentedAvgCycleStats AS (
  SELECT
    settle_tier,
    MIN(CASE WHEN quartile_rank = 3 THEN avg_settle_cycle_days END) AS Q3_avg_settle_cycle
  FROM (
    SELECT
      settle_tier,
      avg_settle_cycle_days,
      NTILE(4) OVER (PARTITION BY settle_tier ORDER BY avg_settle_cycle_days) AS quartile_rank
    FROM UserSettleTiers
  ) RankedAvgCycle
  GROUP BY settle_tier
)

-- recency > Q3면 고위험군
SELECT
  ust.user_id,
  ust.settle_tier,
  ust.recency_days,
  sas.Q3_avg_settle_cycle,
  CASE WHEN ust.recency_days > sas.Q3_avg_settle_cycle THEN 'High-Risk Candidate' ELSE 'Normal User' END AS user_segment_status
FROM UserSettleTiers ust
JOIN SegmentedAvgCycleStats sas ON ust.settle_tier = sas.settle_tier;
```

### 증빙 2) 매칭 조건 요약 + 실행 매칭 스텝 캡처

매칭 조건 요약(한 줄):
- `지역 일치` + `시급 10% 이상 상승` + `동일/유사 업종(category_map)` 충족 시 “실행 가능”으로 확정

파일:
- `sql/V2_step2b_personalization_matching_executable.sql`

캡처 포인트(핵심 JOIN/WHERE):
```sql
SET @min_wage_uplift_ratio = 1.10;

-- 동일/유사 업종 확장
ExpandedCategory AS (
  SELECT
    ctu.user_id,
    ctu.region_id,
    ctu.last_final_hourly_rate,
    ctu.last_settle_category AS category_to_match
  FROM CurrentTargetUsers ctu
  UNION ALL
  SELECT
    ctu.user_id,
    ctu.region_id,
    ctu.last_final_hourly_rate,
    cm.similar_cat AS category_to_match
  FROM CurrentTargetUsers ctu
  JOIN category_map cm ON ctu.last_settle_category = cm.original_cat
),

-- 지역/시급 조건 적용(실행 매칭 성립)
MatchedCandidates AS (
  SELECT DISTINCT ec.user_id, jp.job_id
  FROM ExpandedCategory ec
  JOIN job_posts jp
    ON ec.category_to_match = jp.category_id
   AND ec.region_id = jp.region_id
   AND jp.hourly_rate >= (ec.last_final_hourly_rate * @min_wage_uplift_ratio)
)
```

보조 문장(가상 DB 구축):
- 가상 로그/테이블 기반으로 사전 검증했고, 재현 가능한 SQL 스텝으로 구성했음

---

## 우측: 성과관리(OEC+가드레일+롤아웃/중단)

- OEC를 `apply_rate`로 고정하고 Control/A/B로 uplift를 비교했음
- 가드레일(`notification_blocking_rate`, 코호트 리텐션)을 함께 설계해 효과/피로도를 동시 평가했음
- 롤아웃 단계(%)와 중단/롤백 기준을 시나리오로 문서화했음

### 증빙 1) AB 결과표(OEC) + 가드레일

출처:
- `docs/analysis_scenario.md` (I 섹션)

AB 성과(실행 매칭 성립 유저 `n=2103`):
| 그룹 | 지원/전체 | apply_rate | uplift vs Control(기준 메시지) |
|---|---:|---:|---:|
| Control(기준 메시지) | `17/693` | `0.024531` | `-` |
| A(유사업종 강조) | `36/713` | `0.050491` | `+0.025960` |
| B(시급 상승 강조) | `114/697` | `0.163558` | `+0.139027` |

가드레일(동일 모집단):
| 그룹 | notification_blocking_rate |
|---|---:|
| Control(기준 메시지) | `8.658009%` |
| A(유사업종 강조) | `10.098177%` |
| B(시급 상승 강조) | `10.043041%` |

각주:
- *가상 데이터 기반 시나리오 검증 결과*

### 증빙 2) 롤아웃/중단(롤백) 기준 박스

출처:
- `docs/analysis_scenario.md` (L 섹션)

```text
[Rollout]
Week1: 10% → Week2: 30% → Week3+: 100%

[Stop / Rollback]
1) notification_blocking_rate > 10.658% (Control 8.658% + 2.0%p)
2) uplift vs Control < +5.0%p (2회 연속)
```

