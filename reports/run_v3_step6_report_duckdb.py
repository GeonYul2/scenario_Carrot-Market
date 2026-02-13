import pathlib
import sys

try:
    import duckdb
except ImportError:
    print("duckdb is required. Install with: pip install duckdb")
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORTS_DIR = ROOT / "reports"
SQL_PATH = REPORTS_DIR / "v3_step6_push_policy_simulation.duckdb.sql"
OUT_CSV = REPORTS_DIR / "v3_step6_policy_results.csv"
OUT_DB = REPORTS_DIR / "v3_step6_policy_results.duckdb"

con = duckdb.connect(str(OUT_DB))

# Load source CSVs into temporary tables (STEP6 only)
con.execute(
    f"""
    CREATE OR REPLACE TABLE users AS
    SELECT * FROM read_csv_auto('{(ROOT / 'scripts' / 'data' / 'users.csv').as_posix()}', header=true);

    CREATE OR REPLACE TABLE settlements AS
    SELECT * FROM read_csv_auto('{(ROOT / 'scripts' / 'data' / 'settlements.csv').as_posix()}', header=true);

    CREATE OR REPLACE TABLE job_posts AS
    SELECT * FROM read_csv_auto('{(ROOT / 'scripts' / 'data' / 'job_posts.csv').as_posix()}', header=true);

    CREATE OR REPLACE TABLE category_map AS
    SELECT * FROM read_csv_auto('{(ROOT / 'scripts' / 'data' / 'category_map.csv').as_posix()}', header=true);

    CREATE OR REPLACE TABLE campaign_logs AS
    SELECT * FROM read_csv_auto('{(ROOT / 'scripts' / 'data' / 'campaign_logs.csv').as_posix()}', header=true);
    """
)

query = SQL_PATH.read_text(encoding="utf-8")
con.execute(f"CREATE OR REPLACE TABLE v3_step6_policy_results AS {query}")
con.execute(f"COPY v3_step6_policy_results TO '{OUT_CSV.as_posix()}' (HEADER, DELIMITER ',')")

print(f"Saved: {OUT_CSV}")
print("Preview:")
print(con.execute("SELECT * FROM v3_step6_policy_results LIMIT 12").fetchdf())

con.close()
