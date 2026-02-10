import pandas as pd
import numpy as np
from faker import Faker
from datetime import datetime, timedelta
import random
import uuid

# --- Configuration ---
NUM_USERS = 10000
NUM_EMPLOYERS = 1000
NUM_POSTS = 2000
SIMULATION_DAYS = 7
START_DATE = datetime.now() - timedelta(days=SIMULATION_DAYS)

# --- Design Principles based Configuration ---
NEIGHBORHOOD_IDS = list(range(1, 51))
ACQUISITION_CHANNELS = ['organic', 'paid_search', 'referral', 'social_media']
CATEGORIES = ['편의점', '서빙', '주방', '매장관리', '배달', '사무보조', '이벤트']
MESSAGE_TYPES = ['A_urgent', 'B_friendly']

# A/B Test & Conversion Rate Config (as per request: 2~5%)
CONTROL_CONV_RATE = 0.02
TREATMENT_CONV_RATE = 0.05

fake = Faker('ko_KR')

def generate_users():
    """Generates dim_users DataFrame"""
    users = []
    for _ in range(NUM_USERS):
        users.append({
            'user_uuid': str(uuid.uuid4()),
            'neighborhood_id': random.choice(NEIGHBORHOOD_IDS),
            'manner_temperature': round(random.uniform(36.0, 50.0), 1),
            'is_push_agreed': random.choices([1, 0], weights=[0.8, 0.2], k=1)[0],
            'acquisition_channel': random.choice(ACQUISITION_CHANNELS),
            'created_at': fake.date_time_between(start_date=f'-{SIMULATION_DAYS*2}d', end_date='now')
        })
    return pd.DataFrame(users)

def generate_job_posts():
    """Generates dim_job_posts DataFrame"""
    posts = []
    employer_uuids = [str(uuid.uuid4()) for _ in range(NUM_EMPLOYERS)]
    for _ in range(NUM_POSTS):
        posts.append({
            'post_uuid': str(uuid.uuid4()),
            'employer_uuid': random.choice(employer_uuids),
            'category_code': random.choice(CATEGORIES),
            'is_urgent': random.choices([1, 0], weights=[0.2, 0.8], k=1)[0],
            'base_salary': random.choice([10000, 11000, 12000, 13000, 15000]),
            'created_at': fake.date_time_between(start_date=f'-{SIMULATION_DAYS*2}d', end_date='now')
        })
    return pd.DataFrame(posts)

def generate_event_logs(users_df, posts_df):
    """Generates fct_user_event_logs DataFrame"""
    logs = []
    # Create personas to simulate realistic behavior
    user_personas = {
        'hesitator': users_df.sample(frac=0.3),
        'active': users_df.sample(frac=0.2),
        'passive': users_df.sample(frac=0.5)
    }

    for day in range(SIMULATION_DAYS):
        current_date = START_DATE + timedelta(days=day)
        
        # Simulate events for each persona
        for persona_type, persona_df in user_personas.items():
            for _, user in persona_df.iterrows():
                if random.random() < (0.8 if persona_type == 'active' else 0.5 if persona_type == 'hesitator' else 0.2): # Session probability
                    session_id = str(uuid.uuid4())
                    num_events = random.randint(1, 10 if persona_type == 'active' else 6)
                    
                    available_posts = posts_df[posts_df['created_at'].dt.date <= current_date.date()]
                    if available_posts.empty: continue
                    post = available_posts.sample(1).iloc[0]

                    # --- Event Funnel Simulation ---
                    # 1. View Post
                    event_timestamp = current_date + timedelta(seconds=random.randint(0, 86399))
                    logs.append({'event_uuid': str(uuid.uuid4()), 'session_id': session_id, 'user_uuid': user['user_uuid'], 'post_uuid': post['post_uuid'], 'event_name': 'view', 'stay_duration_ms': None, 'event_timestamp': event_timestamp})
                    
                    # 2. Stay on Post
                    stay_duration = int(np.random.normal(30000, 15000) * (2.0 if persona_type == 'hesitator' else 1.2 if persona_type == 'active' else 0.8))
                    stay_duration = max(1000, stay_duration)
                    logs.append({'event_uuid': str(uuid.uuid4()), 'session_id': session_id, 'user_uuid': user['user_uuid'], 'post_uuid': post['post_uuid'], 'event_name': 'stay', 'stay_duration_ms': stay_duration, 'event_timestamp': event_timestamp + timedelta(milliseconds=100)})

                    # 3. Click Apply (Hesitators are less likely)
                    apply_prob = 0.1 if persona_type == 'hesitator' else 0.7 if persona_type == 'active' else 0.2
                    if random.random() < apply_prob:
                        logs.append({'event_uuid': str(uuid.uuid4()), 'session_id': session_id, 'user_uuid': user['user_uuid'], 'post_uuid': post['post_uuid'], 'event_name': 'click_apply', 'stay_duration_ms': None, 'event_timestamp': event_timestamp + timedelta(milliseconds=stay_duration)})

    return pd.DataFrame(logs)


def generate_campaign_logs(users_df, logs_df):
    """Generates fct_crm_campaign_logs based on 'hesitator' behavior"""
    # 1. Identify "hesitating" users: many 'stay' events, long duration, no 'click_apply'
    stay_events = logs_df[logs_df['event_name'] == 'stay']
    applied_users = set(logs_df[logs_df['event_name'] == 'click_apply']['user_uuid'])
    
    user_engagement = stay_events.groupby('user_uuid').agg(
        view_count=('event_uuid', 'count'),
        total_stay_ms=('stay_duration_ms', 'sum')
    ).reset_index()

    # Filter for users not in the applied set
    user_engagement = user_engagement[~user_engagement['user_uuid'].isin(applied_users)]

    # Define "hesitators" as top 40% in engagement who haven't applied
    hesitator_threshold = user_engagement['total_stay_ms'].quantile(0.6)
    target_users = user_engagement[user_engagement['total_stay_ms'] >= hesitator_threshold]
    
    # Merge with user info to respect push agreement
    target_users = pd.merge(target_users, users_df[['user_uuid', 'is_push_agreed']], on='user_uuid')
    eligible_users = target_users[target_users['is_push_agreed'] == 1]

    campaign_logs = []
    
    # 2. Split into groups and simulate campaign results
    for _, user in eligible_users.iterrows():
        # Find a relevant post for the campaign context
        user_viewed_posts = logs_df[(logs_df['user_uuid'] == user['user_uuid']) & (logs_df['event_name'] == 'view')]['post_uuid']
        if user_viewed_posts.empty: continue
        
        post_uuid_for_campaign = user_viewed_posts.iloc[0]

        # Assign to treatment or control
        group = random.choices(['treatment', 'control'], weights=[0.8, 0.2], k=1)[0]
        
        delivered = 1
        opened = 1 if random.random() < 0.3 else 0 # 30% open rate
        unsubscribed = 1 if opened and random.random() < 0.01 else 0 # 1% unsubscribe rate on open
        
        # Simulate conversion based on group
        conv_rate = TREATMENT_CONV_RATE if group == 'treatment' else CONTROL_CONV_RATE
        if opened and not unsubscribed and random.random() < conv_rate:
            # If converted, add a 'submit_application' event to the main log
            submit_event_time = logs_df[logs_df['user_uuid'] == user['user_uuid']]['event_timestamp'].max() + timedelta(hours=1)
            # This part is tricky as it modifies another table's data. 
            # For simplicity, we just log it in the campaign table. The final application event can be joined later.
            pass

        campaign_logs.append({
            'campaign_uuid': str(uuid.uuid4()),
            'user_uuid': user['user_uuid'],
            'post_uuid': post_uuid_for_campaign,
            'test_group': group,
            'message_type': random.choice(MESSAGE_TYPES),
            'is_delivered': delivered,
            'is_opened': opened,
            'is_unsubscribed': unsubscribed,
            'created_at': datetime.now()
        })
    return pd.DataFrame(campaign_logs)


def main():
    """Main function to generate and save all V2 data."""
    print("--- V2 데이터 생성을 시작합니다 (설계: 건율님) ---")

    # Generate dimensions
    users_df = generate_users()
    users_df.to_csv('V2_dim_users.csv', index=False)
    print(f"- {len(users_df)} 명의 유저 정보 생성 완료 -> V2_dim_users.csv")

    posts_df = generate_job_posts()
    posts_df.to_csv('V2_dim_job_posts.csv', index=False)
    print(f"- {len(posts_df)} 건의 공고 정보 생성 완료 -> V2_dim_job_posts.csv")

    # Generate facts
    logs_df = generate_event_logs(users_df, posts_df)
    logs_df.to_csv('V2_fct_user_event_logs.csv', index=False)
    print(f"- {len(logs_df)} 건의 유저 행동 로그 생성 완료 -> V2_fct_user_event_logs.csv")
    
    campaign_logs_df = generate_campaign_logs(users_df, logs_df)
    campaign_logs_df.to_csv('V2_fct_crm_campaign_logs.csv', index=False)
    print(f"- {len(campaign_logs_df)} 건의 CRM 캠페인 로그 생성 완료 -> V2_fct_crm_campaign_logs.csv")

    print("\n--- V2 데이터 파일 4개 생성이 성공적으로 완료되었습니다. ---")


if __name__ == "__main__":
    main()
