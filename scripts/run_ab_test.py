import os
import pymysql
import pandas as pd
from dotenv import load_dotenv
import random

def get_db_connection():
    """Reads .env file and returns a new database connection."""
    load_dotenv()
    try:
        connection = pymysql.connect(
            host=os.getenv('DB_HOST'),
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASS'),
            database=os.getenv('DB_NAME'),
            port=int(os.getenv('DB_PORT')),
            cursorclass=pymysql.cursors.DictCursor
        )
        print("✅ 데이터베이스에 성공적으로 연결되었습니다.")
        return connection
    except pymysql.Error as e:
        print(f"❌ 데이터베이스 연결 실패: {e}")
        print("`.env` 파일에 정확한 DB 접속 정보를 입력했는지 확인해주세요.")
        return None

def get_target_users(connection):
    """Executes the targeting SQL to get 'hesitating users'."""
    print("\n[1/3] '고관여 망설임 유저' 타겟 목록을 추출합니다...")
    try:
        with connection.cursor() as cursor:
            # This query is from project_summary.md (Mission 2)
            sql = """
            SELECT
                logs.user_uuid
            FROM fct_user_event_logs AS logs
            JOIN dim_users AS users ON logs.user_uuid = users.user_uuid
            WHERE
                logs.event_timestamp >= NOW() - INTERVAL 7 DAY
                AND users.is_push_agreed = 1
            GROUP BY
                logs.user_uuid
            HAVING
                COUNT(CASE WHEN logs.event_name IN ('view', 'stay') THEN logs.event_uuid END) >= 3
                AND
                SUM(logs.stay_duration_ms) >= (
                    SELECT PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY total_stay)
                    FROM (
                        SELECT SUM(stay_duration_ms) as total_stay
                        FROM fct_user_event_logs
                        WHERE event_timestamp >= NOW() - INTERVAL 7 DAY AND stay_duration_ms IS NOT NULL
                        GROUP BY user_uuid
                    ) AS stay_sums
                )
                AND
                COUNT(CASE WHEN logs.event_name = 'submit_application' THEN logs.event_uuid END) = 0;
            """
            cursor.execute(sql)
            result = cursor.fetchall()
            target_users = [row['user_uuid'] for row in result]
            print(f"✅ 총 {len(target_users)} 명의 타겟 유저를 찾았습니다.")
            return target_users
    except pymysql.Error as e:
        print(f"❌ 타겟 유저 추출 실패: {e}")
        return []

def run_ab_test_assignment(connection, user_list):
    """Assigns users to groups and INSERTS into the campaign log table."""
    print("\n[2/3] 타겟 유저를 A/B 그룹에 할당하고, 캠페인 로그를 기록합니다...")
    
    if not user_list:
        print("타겟 유저가 없어 A/B 테스트를 진행할 수 없습니다.")
        return

    try:
        with connection.cursor() as cursor:
            # Clear previous campaign data for a clean run
            cursor.execute("TRUNCATE TABLE fct_crm_campaign_logs;")
            print("- 기존 캠페인 로그를 모두 삭제했습니다.")

            # Prepare data for insertion
            campaign_logs = []
            for user_id in user_list:
                group = random.choices(['treatment', 'control'], weights=[0.8, 0.2], k=1)[0]
                campaign_logs.append((
                    str(random.randint(10000, 99999)), # Simplified campaign_uuid
                    user_id,
                    None, # post_uuid, can be enhanced later
                    group,
                    random.choice(['A_urgent', 'B_friendly']), # message_type
                    1, # is_delivered
                    random.choices([1, 0], weights=[0.3, 0.7], k=1)[0], # is_opened (30% open rate)
                    0 # is_unsubscribed
                ))
            
            # Bulk INSERT
            sql = """
            INSERT INTO fct_crm_campaign_logs 
            (campaign_uuid, user_uuid, post_uuid, test_group, message_type, is_delivered, is_opened, is_unsubscribed) 
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """
            cursor.executemany(sql, campaign_logs)
            connection.commit()
            print(f"✅ {len(campaign_logs)} 건의 캠페인 로그를 `fct_crm_campaign_logs` 테이블에 기록했습니다.")
    except pymysql.Error as e:
        print(f"❌ 캠페인 로그 기록 실패: {e}")
        connection.rollback()


def main():
    """Main function to run the A/B test simulation."""
    conn = get_db_connection()
    if conn:
        try:
            target_users = get_target_users(conn)
            run_ab_test_assignment(conn, target_users)
            print("\n[3/3] A/B 테스트 실행 시뮬레이션이 성공적으로 완료되었습니다.")
        finally:
            conn.close()
            print("\n데이터베이스 연결을 닫았습니다.")

if __name__ == '__main__':
    main()
