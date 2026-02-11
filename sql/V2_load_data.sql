-- V2_load_data.sql
-- SQL commands to create tables and load data from CSV files for the Carrot Market CRM Reactivation Analysis.
-- This script is intended to be run on a MySQL/MariaDB database.

-- IMPORTANT: Before running LOAD DATA INFILE, ensure:
-- 1. The CSV files are located in a path accessible by the MySQL/MariaDB server.
--    If running from a client on the same machine, 'LOCAL' keyword can be used,
--    but 'local_infile' server variable might need to be enabled (SET GLOBAL local_infile = 1;).
-- 2. The paths to the CSV files below are correct relative to your project root or absolute paths.
--    Currently assuming CSVs are in 'scripts/data/' relative to where the command is executed.

-- Use the appropriate database
-- USE your_database_name;

-- Disable foreign key checks temporarily for easier table drops and loads
SET FOREIGN_KEY_CHECKS = 0;

-- Drop existing tables if they exist to ensure a clean slate
DROP TABLE IF EXISTS campaign_logs;
DROP TABLE IF EXISTS settlements;
DROP TABLE IF EXISTS job_posts;
DROP TABLE IF EXISTS category_map;
DROP TABLE IF EXISTS users;

-- 1. Create 'users' table
CREATE TABLE users (
    user_id VARCHAR(255) PRIMARY KEY,
    region_id INT,
    push_on TINYINT(1),
    total_settle_cnt INT
);

-- 2. Create 'category_map' table
CREATE TABLE category_map (
    original_cat VARCHAR(255),
    similar_cat VARCHAR(255),
    PRIMARY KEY (original_cat, similar_cat)
);

-- 3. Create 'job_posts' table
CREATE TABLE job_posts (
    job_id VARCHAR(255) PRIMARY KEY,
    category_id VARCHAR(255),
    region_id INT,
    hourly_rate INT,
    posted_at DATE
);

-- 4. Create 'settlements' table
CREATE TABLE settlements (
    st_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255),
    category_id VARCHAR(255),
    settled_at DATE,
    final_hourly_rate INT,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- 5. Create 'campaign_logs' table
CREATE TABLE campaign_logs (
    log_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255),
    ab_group VARCHAR(50),
    is_applied TINYINT(1),
    sent_at DATE,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Enable foreign key checks again
SET FOREIGN_KEY_CHECKS = 1;

-- Load data into tables
-- Paths are relative to the project root, assuming 'scripts/data/'
LOAD DATA LOCAL INFILE 'scripts/data/users.csv'
INTO TABLE users
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '
'
IGNORE 1 ROWS; -- Ignore header row

LOAD DATA LOCAL INFILE 'scripts/data/category_map.csv'
INTO TABLE category_map
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '
'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'scripts/data/job_posts.csv'
INTO TABLE job_posts
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '
'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'scripts/data/settlements.csv'
INTO TABLE settlements
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '
'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'scripts/data/campaign_logs.csv'
INTO TABLE campaign_logs
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '
'
IGNORE 1 ROWS;

-- Optional: Verify data count
SELECT 'users' AS table_name, COUNT(*) FROM users UNION ALL
SELECT 'settlements', COUNT(*) FROM settlements UNION ALL
SELECT 'job_posts', COUNT(*) FROM job_posts UNION ALL
SELECT 'category_map', COUNT(*) FROM category_map UNION ALL
SELECT 'campaign_logs', COUNT(*) FROM campaign_logs;
