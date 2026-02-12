import pandas as pd
import os

def generate_user_inserts():
    users_df = pd.read_csv('scripts/data/users.csv')
    
    # Ensure the output directory exists
    output_dir = 'scripts'
    os.makedirs(output_dir, exist_ok=True)
    
    with open(os.path.join(output_dir, 'temp_user_inserts.sql'), 'w') as f:
        for _, row in users_df.iterrows():
            user_id = row['user_id']
            region_id = row['region_id']
            push_on = row['push_on']
            total_settle_cnt = row['total_settle_cnt']
            notification_blocked_at = row['notification_blocked_at']

            # Handle NULL for notification_blocked_at
            if pd.isna(notification_blocked_at):
                notification_blocked_at_sql = "NULL"
            else:
                notification_blocked_at_sql = f"'{notification_blocked_at}'"

            insert_statement = f"INSERT INTO users (`user_id`, `region_id`, `push_on`, `total_settle_cnt`, `notification_blocked_at`) VALUES ('{user_id}', '{region_id}', '{push_on}', '{total_settle_cnt}', {notification_blocked_at_sql});\n"
            f.write(insert_statement)

if __name__ == '__main__':
    generate_user_inserts()
