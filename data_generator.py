import pandas as pd
import numpy as np
from faker import Faker
from datetime import datetime, timedelta
import random

# --- Configuration ---
NUM_USERS = 5000
NUM_BUSINESSES = 500
NUM_POSTINGS = 1000
START_DATE = datetime(2024, 1, 1)
END_DATE = datetime(2024, 1, 31)
LOG_DAYS = 30

DONG_IDS = [f'dong_{i:03d}' for i in range(1, 21)]
CATEGORIES = ['서빙', '편의점', '매장관리', '주방', '배달', '사무보조']
PLATFORMS = ['android', 'ios', 'web']
EVENT_TYPES = ['view_details', 'click_apply', 'submit_application']

# --- Persona Configuration ---
# (session_prob, events_per_session, funnel_conv_rate)
PERSONAS = {
    'active_seeker': {'session_prob': 0.8, 'events_per_session': 5, 'funnel_conv_rate': {'view_details': 0.9, 'click_apply': 0.5, 'submit_application': 0.8}},
    'casual_browser': {'session_prob': 0.3, 'events_per_session': 3, 'funnel_conv_rate': {'view_details': 0.7, 'click_apply': 0.1, 'submit_application': 0.2}},
    'hesitator': {'session_prob': 0.6, 'events_per_session': 6, 'funnel_conv_rate': {'view_details': 0.95, 'click_apply': 0.05, 'submit_application': 0.1}}
}
USER_PERSONA_DIST = {'active_seeker': 0.1, 'casual_browser': 0.6, 'hesitator': 0.3}

# A/B Test Config
TREATMENT_CONV_RATE = 0.055
CONTROL_CONV_RATE = 0.020

fake = Faker('ko_KR')

def generate_job_postings(business_ids):
    """Generates a DataFrame of job postings."""
    postings = []
    for i in range(NUM_POSTINGS):
        created_at = START_DATE + timedelta(days=random.randint(0, LOG_DAYS - 2))
        postings.append({
            'posting_id': f'post_{i:04d}',
            'business_id': random.choice(business_ids),
            'dong_id': random.choice(DONG_IDS),
            'category': random.choice(CATEGORIES),
            'status': '모집중',
            'hourly_wage': random.randint(900, 1500) * 10,
            'created_at': created_at
        })
    return pd.DataFrame(postings)

def generate_alba_logs(users, postings_df):
    """Generates a DataFrame of user activity logs based on personas."""
    logs = []
    log_id_counter = 0

    # Ensure ~30% of postings have no applications in the first 24h
    postings_with_early_apps = postings_df.sample(frac=0.7).index
    
    for user_id, persona_name in users.items():
        persona = PERSONAS[persona_name]
        for day in range(LOG_DAYS):
            if random.random() > persona['session_prob']:
                continue

            current_date = START_DATE + timedelta(days=day)
            num_events = random.randint(1, persona['events_per_session'])
            session_id = f'sess_{user_id}_{current_date.strftime("%Y%m%d")}'

            for _ in range(num_events):
                # Select a posting that was created before the event
                available_postings = postings_df[postings_df['created_at'].dt.date <= current_date.date()]
                if available_postings.empty: continue
                
                posting = available_postings.sample(1).iloc[0]
                
                # Funnel simulation
                event_timestamp = current_date + timedelta(hours=random.randint(0,23), minutes=random.randint(0,59))

                # 1. View Details
                if random.random() < persona['funnel_conv_rate']['view_details']:
                    logs.append({
                        'log_id': log_id_counter, 'user_id': user_id, 'event_type': 'view_details',
                        'event_timestamp': event_timestamp, 'posting_id': posting['posting_id'],
                        'dong_id': posting['dong_id'], 'session_id': session_id,
                        'platform': random.choice(PLATFORMS), 'stay_duration_seconds': max(10, int(np.random.normal(120, 60)))
                    })
                    log_id_counter += 1
                else: continue

                # 2. Click Apply
                if random.random() < persona['funnel_conv_rate']['click_apply']:
                     logs.append({
                        'log_id': log_id_counter, 'user_id': user_id, 'event_type': 'click_apply',
                        'event_timestamp': event_timestamp + timedelta(minutes=1), 'posting_id': posting['posting_id'],
                        'dong_id': posting['dong_id'], 'session_id': session_id,
                        'platform': random.choice(PLATFORMS), 'stay_duration_seconds': None
                    })
                     log_id_counter += 1
                else: continue

                # 3. Submit Application (respecting the 30% unmatched rule)
                time_since_posting = event_timestamp - posting['created_at']
                is_early_app_candidate = posting.name in postings_with_early_apps
                
                if not (time_since_posting.total_seconds() < 24 * 3600 and not is_early_app_candidate):
                    if random.random() < persona['funnel_conv_rate']['submit_application']:
                        logs.append({
                            'log_id': log_id_counter, 'user_id': user_id, 'event_type': 'submit_application',
                            'event_timestamp': event_timestamp + timedelta(minutes=2), 'posting_id': posting['posting_id'],
                            'dong_id': posting['dong_id'], 'session_id': session_id,
                            'platform': random.choice(PLATFORMS), 'stay_duration_seconds': None
                        })
                        log_id_counter += 1

    return pd.DataFrame(logs)


def run_ab_test_simulation(logs_df):
    """Simulates the A/B test by segmenting users and generating results."""
    # Mimic the SQL segmentation logic in pandas
    seven_days_ago = logs_df['event_timestamp'].max() - timedelta(days=7)
    recent_logs = logs_df[logs_df['event_timestamp'] >= seven_days_ago]

    # Get view counts and average stay times
    view_logs = recent_logs[recent_logs['event_type'] == 'view_details'].copy()
    user_agg = view_logs.groupby('user_id').agg(
        view_count=('log_id', 'count'),
        avg_stay_time=('stay_duration_seconds', 'mean')
    ).reset_index()

    # Get users who submitted applications recently
    recent_applicants = set(recent_logs[recent_logs['event_type'] == 'submit_application']['user_id'])
    
    # Find high-interest users (view_count >= 3)
    high_interest_users = user_agg[user_agg['view_count'] >= 3]
    
    # Exclude recent applicants
    non_applicants = high_interest_users[~high_interest_users['user_id'].isin(recent_applicants)]

    # Find users with stay time in the top 20%
    stay_time_threshold = non_applicants['avg_stay_time'].quantile(0.8)
    target_segment = non_applicants[non_applicants['avg_stay_time'] >= stay_time_threshold]

    target_users = target_segment['user_id'].tolist()
    
    # A/B split and result generation
    exp_results = []
    for user_id in target_users:
        if random.random() > 0.1: # 90% treatment
            group = 'treatment'
            is_applied = 1 if random.random() < TREATMENT_CONV_RATE else 0
        else: # 10% control
            group = 'control'
            is_applied = 1 if random.random() < CONTROL_CONV_RATE else 0
        
        exp_results.append({
            'user_id': user_id,
            'group_type': group,
            'is_applied': is_applied
        })
        
    return pd.DataFrame(exp_results)


def main():
    """Main function to generate and save all data."""
    print("데이터 생성을 시작합니다...")

    # 1. Generate users and businesses
    user_ids = [f'user_{i:04d}' for i in range(NUM_USERS)]
    business_ids = [fake.company() for _ in range(NUM_BUSINESSES)]
    
    # Assign personas to users
    user_personas = {}
    persona_names = list(PERSONAS.keys())
    dist = list(USER_PERSONA_DIST.values())
    for uid in user_ids:
        user_personas[uid] = random.choices(persona_names, weights=dist, k=1)[0]
    
    # 2. Generate job postings
    postings_df = generate_job_postings(business_ids)
    postings_df['created_at'] = pd.to_datetime(postings_df['created_at'])
    print(f"- `{len(postings_df)}` 건의 공고 정보 생성 완료.")

    # 3. Generate alba logs
    logs_df = generate_alba_logs(user_personas, postings_df)
    logs_df['event_timestamp'] = pd.to_datetime(logs_df['event_timestamp'])
    print(f"- `{len(logs_df)}` 건의 유저 행동 로그 생성 완료.")

    # 4. Simulate A/B test and generate results
    exp_results_df = run_ab_test_simulation(logs_df)
    print(f"- `{len(exp_results_df)}` 명의 타겟 유저에 대한 A/B 테스트 결과 생성 완료.")

    # 5. Save to CSV
    postings_df.to_csv('job_postings.csv', index=False)
    logs_df.to_csv('alba_logs.csv', index=False)
    exp_results_df.to_csv('crm_exp_results.csv', index=False)

    print("\nCSV 파일 3개(`job_postings.csv`, `alba_logs.csv`, `crm_exp_results.csv`)가 성공적으로 생성되었습니다.")


if __name__ == "__main__":
    main()
