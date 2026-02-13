import pandas as pd
import os

def escape_sql_value(value):
    """Escapes single quotes in a string value for SQL. Handles None/NaN."""
    if pd.isna(value):
        return 'NULL'
    if isinstance(value, (int, float)):
        return str(value)
    # Convert to string, then replace single quotes with two single quotes
    # and wrap the entire string in single quotes.
    escaped_value = str(value).replace("'", "''")
    return f"'{escaped_value}'"

def generate_insert_statements(table_name, df):
    """Generates INSERT INTO statements for a given DataFrame."""
    inserts = []
    columns = ', '.join([f'`{col}`' for col in df.columns]) # Quote column names
    for _, row in df.iterrows():
        values = ', '.join([escape_sql_value(v) for v in row.values])
        inserts.append(f"INSERT INTO {table_name} ({columns}) VALUES ({values});")
    return inserts

def main():
    output_sql_path = 'sql/V2_full_schema_and_inserts.sql'
    data_dir = 'scripts/data'

    # Define table schemas as raw strings
    schemas = {
        'users': """
CREATE TABLE users (
    user_id VARCHAR(255) PRIMARY KEY,
    region_id INT,
    push_on TINYINT(1),
    total_settle_cnt INT,
    notification_blocked_at DATE
);
""",
        'category_map': """
CREATE TABLE category_map (
    original_cat VARCHAR(255),
    similar_cat VARCHAR(255),
    PRIMARY KEY (original_cat, similar_cat)
);
""",
        'job_posts': """
CREATE TABLE job_posts (
    job_id VARCHAR(255) PRIMARY KEY,
    category_id VARCHAR(255),
    region_id INT,
    hourly_rate INT,
    posted_at DATE
);
""",
        'settlements': """
CREATE TABLE settlements (
    st_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255),
    category_id VARCHAR(255),
    settled_at DATE,
    final_hourly_rate INT,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);
""",
        'campaign_logs': """
CREATE TABLE campaign_logs (
    log_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255),
    ab_group VARCHAR(50),
    is_applied TINYINT(1),
    sent_at DATE,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);
"""
    }

    # Order of tables for creation and dropping (important for foreign keys)
    table_order = ['users', 'category_map', 'job_posts', 'settlements', 'campaign_logs']

    with open(output_sql_path, 'w', encoding='utf-8') as f:
        f.write("-- V2_full_schema_and_inserts.sql\n")
        f.write("-- This file contains CREATE TABLE statements and INSERT statements for all generated data.\n")
        f.write("-- Intended for MySQL/MariaDB databases.\n\n")
        f.write("-- Use the appropriate database\n")
        f.write("-- USE your_database_name;\n\n")

        f.write("SET FOREIGN_KEY_CHECKS = 0;\n\n")

        # Drop tables in reverse order
        for table_name in reversed(table_order):
            f.write(f"DROP TABLE IF EXISTS {table_name};\n")
        f.write("\n")

        # Create tables
        for table_name in table_order:
            f.write(schemas[table_name])
            f.write("\n") # Add an extra newline for spacing
        
        f.write("SET FOREIGN_KEY_CHECKS = 1;\n\n")
        f.write("-- #############################################################\n")
        f.write("-- # INSERT Statements for All Data                            #\n")
        f.write("-- #############################################################\n\n")

        # Generate and write INSERT statements
        for table_name in table_order:
            csv_path = os.path.join(data_dir, f'{table_name}.csv')
            if os.path.exists(csv_path):
                print(f"Generating INSERT statements for {table_name}.csv...")
                df = pd.read_csv(csv_path, dtype=str) # Read all columns as string to avoid type inference issues
                inserts = generate_insert_statements(table_name, df)
                for insert_stmt in inserts:
                    f.write(insert_stmt + "\n")
                f.write("\n")
            else:
                print(f"Warning: {csv_path} not found. Skipping INSERT statements for this table.")

    print(f"\nSuccessfully generated {output_sql_path}")

if __name__ == '__main__':
    main()
