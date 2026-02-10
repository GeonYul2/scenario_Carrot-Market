from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize
import math

# ------------------------------------------------------------------------------
# A/B 테스트 설계 변수 (이 값들을 수정하여 다른 시나리오를 테스트할 수 있습니다)
# ------------------------------------------------------------------------------

# 1. 기준 전환율 (Baseline Conversion Rate, p1)
# 현재 대조군의 예상 전환율입니다. (예: 2.0%)
baseline_rate = 0.02

# 2. 최소 탐지 효과 (Minimum Detectable Effect, MDE)
# 우리가 이 실험을 통해 유의미하게 잡아내고 싶은 최소 전환율 상승폭입니다.
# 여기서는 1.5%p 상승 (2.0% -> 3.5%)을 목표로 설정합니다.
mde = 0.015
target_rate = baseline_rate + mde # 목표 전환율 (p2)

# 3. 유의 수준 (Alpha)
# 1종 오류를 범할 확률. 즉, 실제로는 효과가 없는데 우연히 효과가 있다고 잘못 판단할 확률.
# 보통 0.05 (5%)를 사용합니다.
alpha = 0.05

# 4. 검정력 (Power, 1 - Beta)
# 2종 오류를 범하지 않을 확률. 즉, 실제로 효과가 있을 때 효과가 있다고 올바르게 탐지해낼 확률.
# 보통 0.8 (80%)를 사용합니다.
power = 0.8

# ------------------------------------------------------------------------------
# 표본 크기 계산
# ------------------------------------------------------------------------------

# 1. 효과 크기(Effect Size) 계산
# 두 비율(기준 전환율, 목표 전환율)의 차이를 표준화한 값입니다.
effect_size = proportion_effectsize(prop1=baseline_rate, prop2=target_rate)

# 2. 필요한 표본 크기 계산
# `solve_power` 함수를 사용하여, 위에서 정의한 변수들을 만족시키는 표본 크기(nobs1)를 계산합니다.
# `ratio=1.0`은 실험군과 대조군의 크기를 1:1로 설정한다는 의미입니다.
required_sample_size = NormalIndPower().solve_power(
    effect_size=effect_size,
    alpha=alpha,
    power=power,
    ratio=1.0, # 대조군 대비 실험군 비율
    alternative='two-sided' # 양측 검정
)

# 소수점 올림 처리
required_sample_size = math.ceil(required_sample_size)

# ------------------------------------------------------------------------------
# 결과 출력
# ------------------------------------------------------------------------------

print("--- A/B 테스트 표본 크기 계산 결과 ---")
print(f"  - 기준 전환율 (p1): {baseline_rate:.1%}")
print(f"  - 목표 전환율 (p2): {target_rate:.1%}")
print(f"  - 최소 탐지 효과 (MDE): {mde:.1%p}")
print(f"  - 유의 수준 (Alpha): {alpha}")
print(f"  - 검정력 (Power): {power}")
print("-" * 40)
print(f"요구되는 그룹별 최소 표본 크기: {required_sample_size} 명")
print(f"실험에 필요한 총 최소 표본 크기: {required_sample_size * 2} 명")
print("-" * 40)
print("\n결론: 이 실험이 통계적으로 유의미한 결과를 얻으려면,")
print(f"실험군과 대조군에 각각 최소 {required_sample_size}명의 유저를 참여시켜야 합니다.")
