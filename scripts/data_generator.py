import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import os # Added for os.path.join and os.makedirs

# Configuration
NUM_USERS = 1000
NUM_JOB_POSTS = 500
NUM_SETTLEMENTS_PER_USER = 5 # Average
CAMPAIGN_SEND_DATE = datetime(2023, 10, 26) # Week 0

# --- 1. Data Schema Definition ---

# Users Table
# user_id, region_id, push_on(0/1), total_settle_cnt(정산 횟수)
def generate_users_data(num_users):
    users = []
    for i in range(num_users):
        user_id = f'user_{i+1}'
        region_id = random.randint(1, 10) # 10 regions
        push_on = random.choice([0, 1])
        total_settle_cnt = np.random.geometric(p=0.3) # More users with fewer settlements, some with many
        users.append([user_id, region_id, push_on, total_settle_cnt])
    return pd.DataFrame(users, columns=['user_id', 'region_id', 'push_on', 'total_settle_cnt'])

# Category Map Table
# original_cat, similar_cat (예: 카페 -> 서빙, 베이커리 등 유사 업종 매핑)
def generate_category_map_data():
    categories = {
        '카페': ['바리스타', '서빙', '베이커리'],
        '식당': ['주방보조', '서빙', '배달'],
        '편의점': ['판매', '재고관리'],
        '학원': ['강사보조', '행정'],
        '사무보조': ['문서작성', '자료입력'],
        '배달': ['배달', '물류'],
        'IT': ['개발보조', '테스트']
    }
    category_map = []
    for original, similars in categories.items():
        for similar in similars:
            category_map.append([original, similar])
    return pd.DataFrame(category_map, columns=['original_cat', 'similar_cat'])

# Job Posts Table
# job_id, category_id, region_id, hourly_rate(현재 시급), posted_at
def generate_job_posts_data(num_job_posts, category_map_df):
    job_posts = []
    unique_categories = category_map_df['original_cat'].unique().tolist() + category_map_df['similar_cat'].unique().tolist()
    unique_categories = list(set(unique_categories)) # Ensure uniqueness

    for i in range(num_job_posts):
        job_id = f'job_{i+1}'
        category_id = random.choice(unique_categories)
        region_id = random.randint(1, 10)
        hourly_rate = random.randint(9620, 25000) # Minimum wage to higher
        posted_at = CAMPAIGN_SEND_DATE - timedelta(days=random.randint(1, 180)) # Job posts within last 6 months
        job_posts.append([job_id, category_id, region_id, hourly_rate, posted_at])
    return pd.DataFrame(job_posts, columns=['job_id', 'category_id', 'region_id', 'hourly_rate', 'posted_at'])


# Settlements Table
# st_id, user_id, category_id, settled_at, final_hourly_rate(정산받은 시급)
# IQR 분포 주입: total_settle_cnt가 높은 유저(프로 알바러)는 재방문 주기가 짧고, 낮은 유저는 주기가 길게 분포하도록 settled_at 데이터를 생성할 것.
def generate_settlements_data(users_df, job_posts_df, num_settlements_per_user):
    settlements = []
    st_id_counter = 1
    
    # Identify a subset of users (e.g., 30% of all users) to guarantee *some* post-campaign activity for retention
    # This ensures that some users will always have activity for cohort analysis
    users_to_guarantee_post_campaign_activity = users_df.sample(frac=0.30, random_state=42)['user_id'].tolist()

    for _, user in users_df.iterrows():
        user_id = user['user_id']
        total_settle_cnt = user['total_settle_cnt']

        # Determine settlement frequency based on total_settle_cnt
        if total_settle_cnt > 10: # "Pro" part-timer - very frequent
            avg_days_between_settlements = random.randint(5, 10)
        elif total_settle_cnt > 3: # Regular part-timer - moderate frequent
            avg_days_between_settlements = random.randint(15, 30)
        else: # Casual part-timer - less frequent
            avg_days_between_settlements = random.randint(30, 90)

        num_settlements = max(1, int(np.random.normal(num_settlements_per_user, num_settlements_per_user/2)))
        num_settlements = min(num_settlements, total_settle_cnt + 5) # Cap max settlements to avoid excessive loops

        # Initial settlement date: ensure some overlap with campaign period
        last_settled_at = CAMPAIGN_SEND_DATE - timedelta(days=random.randint(1, 365)) # Start a year before

        for i in range(num_settlements): # Generate historical settlements (mostly before campaign)
            st_id = f'st_{st_id_counter}'
            
            random_job = job_posts_df.sample(1).iloc[0]
            category_id = random_job['category_id']
            final_hourly_rate = random_job['hourly_rate'] - random.randint(0, 1000)

            settled_at = last_settled_at + timedelta(days=max(1, int(random.gauss(avg_days_between_settlements, avg_days_between_settlements/2))))
            
            # Ensure historical settlements don't go too far into the future beyond a reasonable historical window before campaign
            if settled_at > CAMPAIGN_SEND_DATE - timedelta(days=1):
                 settled_at = CAMPAIGN_SEND_DATE - timedelta(days=random.randint(1, 30)) # Make it recent but before campaign for historical

            settlements.append([st_id, user_id, category_id, settled_at, final_hourly_rate]) # Appending datetime object
            last_settled_at = settled_at
            st_id_counter += 1

        # Explicitly add 1-3 settlements AFTER CAMPAIGN_SEND_DATE for a subset of users to guarantee retention
        if user_id in users_to_guarantee_post_campaign_activity:
            num_post_campaign_settlements = random.randint(1, 3) # Add more settlements for retention
            for _ in range(num_post_campaign_settlements):
                st_id = f'st_{st_id_counter}'
                random_job = job_posts_df.sample(1).iloc[0]
                category_id = random_job['category_id']
                final_hourly_rate = random_job['hourly_rate'] - random.randint(0, 1000)
                
                target_week_offset = random.choice([1, 2, 4]) # Force into Week 1, 2, or 4
                settled_at = CAMPAIGN_SEND_DATE + timedelta(days=random.randint(target_week_offset * 7 - 6, target_week_offset * 7))
                
                settlements.append([st_id, user_id, category_id, settled_at, final_hourly_rate]) # Appending datetime object
                st_id_counter += 1

    return pd.DataFrame(settlements, columns=['st_id', 'user_id', 'category_id', 'settled_at', 'final_hourly_rate'])
# Campaign Logs Table
# log_id, user_id, ab_group(Control/A/B), is_applied(0/1), sent_at
# 인과관계 설정:
# * Variant B (Personalized): 유사 업종(similar_cat)이면서 시급(hourly_rate)이 과거 정산액(final_hourly_rate)보다 높은 공고가 매칭된 경우, is_applied 확률이 가장 높게 설정.
# Variant A (Generic): 일반 복귀 메시지는 중간 확률.
# Control (Holdout): 자연 복귀율(가장 낮은 확률) 반영.
def generate_campaign_logs_data(users_df, settlements_df, job_posts_df, category_map_df):
    campaign_logs = []
    log_id_counter = 1
    sent_at_base = CAMPAIGN_SEND_DATE # For the initial campaign send

    # Calculate last settlement info for each user for personalization logic
    last_settlement_info = settlements_df.sort_values(by='settled_at').groupby('user_id').tail(1)
    
    # Merge with users_df to get all user details
    users_with_settlements = pd.merge(users_df, last_settlement_info[['user_id', 'category_id', 'final_hourly_rate']], on='user_id', how='left')
    users_with_settlements.rename(columns={'category_id': 'last_settle_category', 'final_hourly_rate': 'last_final_hourly_rate'}, inplace=True)
    
    # Define apply probabilities for initial campaign
    prob_control = 0.02
    prob_variant_a = 0.05
    prob_variant_b_matched = 0.15 # High probability for matched variant B
    prob_variant_b_unmatched = 0.03 # Still slightly better than control, but not as good as matched

    for _, user in users_with_settlements.iterrows():
        user_id = user['user_id']
        ab_group = random.choice(['Control', 'A', 'B'])
        
        is_applied_initial = 0
        
        # Initial campaign application probability
        if ab_group == 'Control':
            is_applied_initial = np.random.choice([0, 1], p=[1 - prob_control, prob_control])
        elif ab_group == 'A':
            is_applied_initial = np.random.choice([0, 1], p=[1 - prob_variant_a, prob_variant_a])
        elif ab_group == 'B':
            matched_condition = False
            last_settle_category = user.get('last_settle_category')
            last_final_hourly_rate = user.get('last_final_hourly_rate')

            if pd.notna(last_settle_category) and pd.notna(last_final_hourly_rate):
                similar_cats = category_map_df[category_map_df['original_cat'] == last_settle_category]['similar_cat'].tolist()
                all_possible_cats = [last_settle_category] + similar_cats
                matching_jobs = job_posts_df[
                    (job_posts_df['category_id'].isin(all_possible_cats)) &
                    (job_posts_df['hourly_rate'] > last_final_hourly_rate)
                ]
                if not matching_jobs.empty:
                    matched_condition = True
            
            if matched_condition:
                is_applied_initial = np.random.choice([0, 1], p=[1 - prob_variant_b_matched, prob_variant_b_matched])
            else:
                is_applied_initial = np.random.choice([0, 1], p=[1 - prob_variant_b_unmatched, prob_variant_b_unmatched])
        
        # Log for the initial campaign send
        campaign_logs.append([f'log_{log_id_counter}', user_id, ab_group, is_applied_initial, sent_at_base]) # Appending datetime object
        log_id_counter += 1

        # --- Simulate follow-up applications in subsequent weeks for retention ---
        # Add a higher chance for applications in Week 1, 2, 4 post-campaign
        
        prob_follow_up_apply_base = 0.05 # Increased base chance
        prob_follow_up_apply_A = 0.1 # Increased for A
        prob_follow_up_apply_B = 0.2 # Increased for B

        for week_num in [1, 2, 4]:
            current_prob = prob_follow_up_apply_base
            if ab_group == 'B':
                current_prob = prob_follow_up_apply_B
            elif ab_group == 'A':
                current_prob = prob_follow_up_apply_A
            
            if is_applied_initial == 1 and ab_group == 'B': # Boost for B if initial applied
                current_prob *= 1.5 # Boost is now 1.5x instead of 2x (to keep prob <= 1)
                                      # Max prob would be 0.2 * 1.5 = 0.3, which is fine

            if random.random() < current_prob:
                follow_up_sent_at = sent_at_base + timedelta(days=random.randint(week_num * 7 - 6, week_num * 7))
                campaign_logs.append([f'log_{log_id_counter}', user_id, ab_group, 1, follow_up_sent_at]) # Appending datetime object
                log_id_counter += 1
    
    return pd.DataFrame(campaign_logs, columns=['log_id', 'user_id', 'ab_group', 'is_applied', 'sent_at'])
def main():
    print("Generating data...")

    # Generate dataframes
    users_df = generate_users_data(NUM_USERS)
    category_map_df = generate_category_map_data()
    job_posts_df = generate_job_posts_data(NUM_JOB_POSTS, category_map_df)
    settlements_df = generate_settlements_data(users_df, job_posts_df, NUM_SETTLEMENTS_PER_USER)
    campaign_logs_df = generate_campaign_logs_data(users_df, settlements_df, job_posts_df, category_map_df)

    # Convert date columns to datetime objects within data_generator.py for accurate min/max checks
    # These are already datetime objects from generate_X_data functions
    # settlements_df['settled_at'] = pd.to_datetime(settlements_df['settled_at']) # No longer needed if already datetime
    # campaign_logs_df['sent_at'] = pd.to_datetime(campaign_logs_df['sent_at'])   # No longer needed if already datetime

    print("\n--- DEBUG (DataGenerator): Dates before CSV write ---")
    print(f"Settlements min date: {settlements_df['settled_at'].min()}")
    print(f"Settlements max date: {settlements_df['settled_at'].max()}")
    print(f"Campaign Logs min date: {campaign_logs_df['sent_at'].min()}")
    print(f"Campaign Logs max date: {campaign_logs_df['sent_at'].max()}")
    print(f"CAMPAIGN_SEND_DATE: {CAMPAIGN_SEND_DATE}")
    print(f"CAMPAIGN_SEND_DATE + 1 day: {CAMPAIGN_SEND_DATE + timedelta(days=1)}")

    # Save to CSV
    output_dir = 'scripts/data' # Changed this line
    os.makedirs(output_dir, exist_ok=True)

    # Convert datetime columns to string format required for CSV before saving
    settlements_df['settled_at'] = settlements_df['settled_at'].dt.strftime('%Y-%m-%d')
    campaign_logs_df['sent_at'] = campaign_logs_df['sent_at'].dt.strftime('%Y-%m-%d')
    job_posts_df['posted_at'] = job_posts_df['posted_at'].dt.strftime('%Y-%m-%d') # Also for job_posts

    users_df.to_csv(os.path.join(output_dir, 'users.csv'), index=False)
    settlements_df.to_csv(os.path.join(output_dir, 'settlements.csv'), index=False)
    job_posts_df.to_csv(os.path.join(output_dir, 'job_posts.csv'), index=False)
    category_map_df.to_csv(os.path.join(output_dir, 'category_map.csv'), index=False)
    campaign_logs_df.to_csv(os.path.join(output_dir, 'campaign_logs.csv'), index=False)

    print("Data generation complete. CSV files saved in 'data/' directory.")

    # --- AB Test Probability Report ---
    print("\n--- AB Test Simulated Apply Rates ---")
    ab_test_summary = campaign_logs_df.groupby('ab_group')['is_applied'].agg(['count', 'sum']).reset_index()
    ab_test_summary['apply_rate'] = ab_test_summary['sum'] / ab_test_summary['count']
    print(ab_test_summary)

if __name__ == '__main__':
    main()
