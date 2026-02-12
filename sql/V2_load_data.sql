-- V2_load_data.sql
-- 이 SQL 스크립트는 Carrot Market CRM 재활성화 분석을 위한 테이블 생성 및 CSV 파일로부터 데이터를 로드하는 명령을 포함합니다.
-- MySQL/MariaDB 데이터베이스에서 실행하도록 작성되었습니다.

-- 중요: LOAD DATA LOCAL INFILE 실행 전 다음 사항을 확인하십시오:
-- 1. CSV 파일들이 MySQL/MariaDB 서버에서 접근 가능한 경로에 위치해야 합니다.
--    동일한 머신에서 클라이언트로 실행하는 경우 'LOCAL' 키워드를 사용할 수 있지만,
--    'local_infile' 서버 변수 활성화가 필요할 수 있습니다 (SET GLOBAL local_infile = 1;).
-- 2. 아래 CSV 파일 경로는 프로젝트 루트를 기준으로 하거나 절대 경로로 정확해야 합니다.
--    현재는 명령이 실행되는 위치를 기준으로 'scripts/data/'에 CSV 파일이 있다고 가정합니다.

-- 적절한 데이터베이스를 사용하세요 (예: USE your_database_name;)

-- Disable foreign key checks temporarily for easier table drops and loads
-- 외래 키 제약 조건 확인을 일시적으로 비활성화하여 테이블 삭제 및 로드를 용이하게 합니다.
SET FOREIGN_KEY_CHECKS = 0;

-- Drop existing tables if they exist to ensure a clean slate
-- 기존 테이블이 존재하면 삭제하여 깨끗한 상태를 보장합니다.
DROP TABLE IF EXISTS campaign_logs;
DROP TABLE IF EXISTS settlements;
DROP TABLE IF EXISTS job_posts;
DROP TABLE IF EXISTS category_map;
DROP TABLE IF EXISTS users;

-- 1. 'users' 테이블 생성 (사용자 정보를 저장)
CREATE TABLE users (
    user_id VARCHAR(255) PRIMARY KEY, -- 사용자 고유 ID
    region_id INT,                    -- 사용자 지역 ID
    push_on TINYINT(1),               -- 푸시 알림 수신 여부 (1: 수신, 0: 미수신)
    total_settle_cnt INT,             -- 총 정산 횟수
    notification_blocked_at DATE      -- 알림 차단 시점
);

-- 2. 'category_map' 테이블 생성 (원본 카테고리와 유사 카테고리 매핑 정보)
CREATE TABLE category_map (
    original_cat VARCHAR(255), -- 원본 카테고리
    similar_cat VARCHAR(255),  -- 유사 카테고리
    PRIMARY KEY (original_cat, similar_cat)
);

-- 3. 'job_posts' 테이블 생성 (구인 공고 정보)
CREATE TABLE job_posts (
    job_id VARCHAR(255) PRIMARY KEY,  -- 공고 고유 ID
    category_id VARCHAR(255),         -- 카테고리 ID
    region_id INT,                    -- 지역 ID
    hourly_rate INT,                  -- 시간당 급여
    posted_at DATE                    -- 공고 게시일
);

-- 4. 'settlements' 테이블 생성 (사용자 정산 내역)
CREATE TABLE settlements (
    st_id VARCHAR(255) PRIMARY KEY,     -- 정산 고유 ID
    user_id VARCHAR(255),               -- 사용자 ID
    category_id VARCHAR(255),           -- 정산된 작업의 카테고리 ID
    settled_at DATE,                    -- 정산 완료일
    final_hourly_rate INT,              -- 최종 시간당 정산 금액
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- 5. 'campaign_logs' 테이블 생성 (캠페인 발송 및 사용자 반응 로그)
CREATE TABLE campaign_logs (
    log_id VARCHAR(255) PRIMARY KEY, -- 로그 고유 ID
    user_id VARCHAR(255),            -- 사용자 ID
    ab_group VARCHAR(50),            -- A/B 테스트 그룹 (Control, A, B 등)
    is_applied TINYINT(1),           -- 공고 지원 여부 (1: 지원함, 0: 지원 안 함)
    sent_at DATE,                    -- 캠페인 메시지 발송일
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Enable foreign key checks again
-- 외래 키 제약 조건 확인을 다시 활성화합니다.
SET FOREIGN_KEY_CHECKS = 1;

-- CSV 파일로부터 테이블에 데이터 로드
-- 경로는 프로젝트 루트 기준 'scripts/data/'에 CSV 파일이 있다고 가정합니다.
LOAD DATA LOCAL INFILE 'scripts/data/users.csv' -- 사용자 데이터 로드
INTO TABLE users
FIELDS TERMINATED BY ','                   -- 필드는 쉼표로 구분
ENCLOSED BY '"'                            -- 필드 값은 큰따옴표로 묶여 있음
LINES TERMINATED BY '\n'                   -- 각 줄은 줄바꿈 문자로 끝남
IGNORE 1 ROWS;                             -- 헤더 행 무시

LOAD DATA LOCAL INFILE 'scripts/data/category_map.csv' -- 카테고리 매핑 데이터 로드
INTO TABLE category_map
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'scripts/data/job_posts.csv' -- 구인 공고 데이터 로드
INTO TABLE job_posts
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'scripts/data/settlements.csv' -- 정산 내역 데이터 로드
INTO TABLE settlements
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'scripts/data/campaign_logs.csv' -- 캠페인 로그 데이터 로드
INTO TABLE campaign_logs
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 선택 사항: 데이터 로드 확인 (각 테이블의 레코드 수 반환)
SELECT 'users' AS table_name, COUNT(*) FROM users UNION ALL
SELECT 'settlements', COUNT(*) FROM settlements UNION ALL
SELECT 'job_posts', COUNT(*) FROM job_posts UNION ALL
SELECT 'category_map', COUNT(*) FROM category_map UNION ALL
SELECT 'campaign_logs', COUNT(*) FROM campaign_logs;
