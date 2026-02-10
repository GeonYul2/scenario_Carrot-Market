-- --------------------------------------------------------------------------------
-- [Project V2] 당근알바 CRM 분석을 위한 데이터 웨어하우스 스키마 (DDL)
-- --------------------------------------------------------------------------------
-- Design Principles:
-- 1. Star Schema: Dimension (dim)과 Fact (fct) 테이블로 분리하여 분석 효율성 및 확장성 확보
-- 2. Hyper-local & Trust: 'neighborhood_id', 'manner_temperature' 등 당근의 핵심 가치 반영
-- 3. Event-Driven: 모든 유저 행동을 시계열 로그로 추적
-- 4. Experiment Integrity: A/B 테스트 설계 및 성과 측정이 용이한 구조
-- 5. Professionalism: UUID, TIMESTAMP 등 정교한 데이터 타입 및 감사 컬럼 적용
-- --------------------------------------------------------------------------------

-- 데이터베이스가 있다면 선택, 없다면 수동으로 생성 후 선택해주세요.
-- USE your_database_name;

-- 1. 기존 테이블이 있다면 삭제 (초기화)
SET foreign_key_checks = 0;
DROP TABLE IF EXISTS dim_users, dim_job_posts, fct_user_event_logs, fct_crm_campaign_logs;
SET foreign_key_checks = 1;

-- 2. 테이블 생성 (CREATE TABLE)

-- 2.1. dim_users (유저 마스터 테이블)
-- 유저의 고정적인 특성 정보를 저장하는 Dimension 테이블
CREATE TABLE dim_users (
    user_uuid VARCHAR(36) PRIMARY KEY, -- UUID는 VARCHAR(36)으로 저장
    neighborhood_id INT,
    manner_temperature DECIMAL(3, 1), -- e.g., 36.5, 40.2
    is_push_agreed TINYINT(1), -- BOOLEAN은 TINYINT(1)로 저장 (0: false, 1: true)
    acquisition_channel VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2.2. dim_job_posts (알바 공고 마스터 테이블)
-- 알바 공고의 고정적인 특성 정보를 저장하는 Dimension 테이블
CREATE TABLE dim_job_posts (
    post_uuid VARCHAR(36) PRIMARY KEY,
    employer_uuid VARCHAR(36),
    category_code VARCHAR(50),
    is_urgent TINYINT(1),
    base_salary INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2.3. fct_user_event_logs (유저 행동 로그 테이블)
-- 시간에 따라 계속 쌓이는 유저의 행동 데이터를 저장하는 Fact 테이블
CREATE TABLE fct_user_event_logs (
    event_uuid VARCHAR(36) PRIMARY KEY,
    session_id VARCHAR(36),
    user_uuid VARCHAR(36),
    post_uuid VARCHAR(36),
    event_name ENUM('view', 'stay', 'click_apply', 'save', 'submit_application'),
    stay_duration_ms BIGINT,
    event_timestamp TIMESTAMP,
    -- 외래 키 제약 조건 (필요시 활성화)
    -- FOREIGN KEY (user_uuid) REFERENCES dim_users(user_uuid),
    -- FOREIGN KEY (post_uuid) REFERENCES dim_job_posts(post_uuid)
    INDEX (event_timestamp),
    INDEX (user_uuid),
    INDEX (post_uuid)
);

-- 2.4. fct_crm_campaign_logs (CRM 캠페인 결과 테이블)
-- CRM 캠페인 실행 및 성과를 기록하는 Fact 테이블
CREATE TABLE fct_crm_campaign_logs (
    campaign_uuid VARCHAR(36) PRIMARY KEY,
    user_uuid VARCHAR(36),
    post_uuid VARCHAR(36),
    test_group ENUM('treatment', 'control'),
    message_type VARCHAR(50),
    is_delivered TINYINT(1),
    is_opened TINYINT(1),
    is_unsubscribed TINYINT(1),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- 외래 키 제약 조건 (필요시 활성화)
    -- FOREIGN KEY (user_uuid) REFERENCES dim_users(user_uuid),
    INDEX (user_uuid)
);

-- --------------------------------------------------------------------------------
-- [완료] 테이블 생성이 완료되었습니다.
-- 다음으로 Python 스크립트를 사용하여 이 테이블에 가상 데이터를 삽입합니다.
-- --------------------------------------------------------------------------------


