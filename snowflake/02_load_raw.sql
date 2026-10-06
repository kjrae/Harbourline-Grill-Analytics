-- =====================================================================
-- 02_load_raw.sql  |  EXTRACT + LOAD: stage files -> RAW tables
-- Run AFTER uploading the 11 files from raw/ into stage RAW.LANDING.
-- Every column lands as text so a bad value can never fail the load;
-- typing and cleaning happen in 03_transform.sql. Each row also records
-- which file it came from and when it was loaded (audit trail).
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE HARBOURLINE_WH;
USE DATABASE HARBOURLINE;
USE SCHEMA RAW;

LIST @RAW.LANDING;   -- you should see 11 files

-- ---------- POS: item sales ----------
CREATE OR REPLACE TABLE RAW.POS_SALES (
  business_date VARCHAR, store VARCHAR, daypart VARCHAR, menu_item_id VARCHAR, menu_item_name VARCHAR,
  qty_sold VARCHAR, unit_price VARCHAR, gross_sales VARCHAR, discounts VARCHAR, comps VARCHAR, net_sales VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.POS_SALES FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*pos_sales_extract.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

-- ---------- POS: hourly covers ----------
CREATE OR REPLACE TABLE RAW.POS_COVERS_HOURLY (
  business_date VARCHAR, store VARCHAR, hour_of_day VARCHAR, covers VARCHAR, net_sales VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.POS_COVERS_HOURLY FROM (
  SELECT $1,$2,$3,$4,$5, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*pos_covers_hourly_extract.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

-- ---------- Labour: timeclock ----------
CREATE OR REPLACE TABLE RAW.TIMECLOCK (
  shift_id VARCHAR, business_date VARCHAR, store VARCHAR, employee_id VARCHAR, role VARCHAR,
  scheduled_start VARCHAR, scheduled_end VARCHAR, actual_start VARCHAR, actual_end VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.TIMECLOCK FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*timeclock_extract.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

-- ---------- Inventory: purchasing ----------
CREATE OR REPLACE TABLE RAW.PURCHASING (
  po_line_id VARCHAR, delivery_date VARCHAR, store VARCHAR, supplier VARCHAR, ingredient_id VARCHAR,
  ingredient_name VARCHAR, qty_received VARCHAR, unit VARCHAR, unit_cost VARCHAR, line_total VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.PURCHASING FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*purchasing_extract.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

-- ---------- Inventory: weekly counts ----------
CREATE OR REPLACE TABLE RAW.INVENTORY_COUNTS (
  count_date VARCHAR, store VARCHAR, ingredient_id VARCHAR, qty_on_hand VARCHAR, unit VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.INVENTORY_COUNTS FROM (
  SELECT $1,$2,$3,$4,$5, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*inventory_counts_extract.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

-- ---------- Inventory: waste log ----------
CREATE OR REPLACE TABLE RAW.WASTE_LOG (
  waste_date VARCHAR, store VARCHAR, ingredient_id VARCHAR, qty_wasted VARCHAR, unit VARCHAR, reason VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.WASTE_LOG FROM (
  SELECT $1,$2,$3,$4,$5,$6, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*waste_log_extract.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

-- ---------- Reference / master data ----------
CREATE OR REPLACE TABLE RAW.REF_LOCATIONS (
  location_id VARCHAR, location_name VARCHAR, city VARCHAR, latitude VARCHAR, longitude VARCHAR, seats VARCHAR,
  has_patio VARCHAR, open_date VARCHAR, region VARCHAR, area_manager VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.REF_LOCATIONS FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*ref_locations.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

CREATE OR REPLACE TABLE RAW.REF_MENU (
  menu_item_id VARCHAR, menu_item_name VARCHAR, category VARCHAR, price_2025 VARCHAR, is_main VARCHAR,
  price_2026 VARCHAR, price_change_date VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.REF_MENU FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*ref_menu.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

CREATE OR REPLACE TABLE RAW.REF_INGREDIENTS (
  ingredient_id VARCHAR, ingredient_name VARCHAR, ingredient_category VARCHAR, unit VARCHAR,
  std_cost_2025 VARCHAR, expected_waste_rate VARCHAR, is_produce VARCHAR, std_cost_2026 VARCHAR, supplier VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.REF_INGREDIENTS FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*ref_ingredients.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

CREATE OR REPLACE TABLE RAW.REF_RECIPES (
  menu_item_id VARCHAR, ingredient_id VARCHAR, qty_per_item VARCHAR, unit VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.REF_RECIPES FROM (
  SELECT $1,$2,$3,$4, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*ref_recipes.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

CREATE OR REPLACE TABLE RAW.REF_EMPLOYEES (
  employee_id VARCHAR, employee_name VARCHAR, home_location_id VARCHAR, role VARCHAR, hourly_wage VARCHAR, hire_date VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_LTZ);
COPY INTO RAW.REF_EMPLOYEES FROM (
  SELECT $1,$2,$3,$4,$5,$6, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @RAW.LANDING)
  PATTERN = '.*ref_employees.*'
  FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FF');

-- ---------- Load check: every row should say OK ----------
SELECT table_name, loaded_rows, expected_rows,
       IFF(loaded_rows = expected_rows, 'OK', 'CHECK UPLOAD') AS status
FROM (
            SELECT 'POS_SALES' AS table_name,         (SELECT COUNT(*) FROM RAW.POS_SALES)         AS loaded_rows, 554747 AS expected_rows
  UNION ALL SELECT 'POS_COVERS_HOURLY',                (SELECT COUNT(*) FROM RAW.POS_COVERS_HOURLY),  96160
  UNION ALL SELECT 'TIMECLOCK',                        (SELECT COUNT(*) FROM RAW.TIMECLOCK),         224777
  UNION ALL SELECT 'PURCHASING',                       (SELECT COUNT(*) FROM RAW.PURCHASING),         44813
  UNION ALL SELECT 'INVENTORY_COUNTS',                 (SELECT COUNT(*) FROM RAW.INVENTORY_COUNTS),   38280
  UNION ALL SELECT 'WASTE_LOG',                        (SELECT COUNT(*) FROM RAW.WASTE_LOG),          37840
  UNION ALL SELECT 'REF_LOCATIONS',                    (SELECT COUNT(*) FROM RAW.REF_LOCATIONS),         10
  UNION ALL SELECT 'REF_MENU',                         (SELECT COUNT(*) FROM RAW.REF_MENU),              29
  UNION ALL SELECT 'REF_INGREDIENTS',                  (SELECT COUNT(*) FROM RAW.REF_INGREDIENTS),       44
  UNION ALL SELECT 'REF_RECIPES',                      (SELECT COUNT(*) FROM RAW.REF_RECIPES),          131
  UNION ALL SELECT 'REF_EMPLOYEES',                    (SELECT COUNT(*) FROM RAW.REF_EMPLOYEES),        842
)
ORDER BY table_name;
