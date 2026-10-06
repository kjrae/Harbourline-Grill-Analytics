-- =====================================================================
-- 03_transform.sql  |  TRANSFORM: RAW -> CORE star schema
-- Cleans the messy extracts and builds the tables Power BI reads.
--   * store / role name variants  -> mapped to master IDs (STAGING tables)
--   * mixed date formats          -> one DATE type
--   * duplicate rows              -> removed on the business key
--   * missing net_sales           -> gross - discounts - comps (flagged)
--   * missed clock-outs           -> scheduled end (flagged)
--   * produce bought in lb        -> converted to kg
--   * food cost logic             -> theoretical vs actual usage, variance $
-- Rows that can't be mapped are KEPT with a NULL key so 04_data_quality.sql
-- can count them; nothing is dropped silently. Safe to re-run.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE HARBOURLINE_WH;
USE DATABASE HARBOURLINE;
ALTER SESSION SET WEEK_START = 1;   -- weeks start Monday

-- =====================================================================
-- STAGING: master-data mappings (the governance fix: one agreed list)
-- alias_key = UPPER(TRIM(name as typed in the source system))
-- =====================================================================
CREATE OR REPLACE TABLE STAGING.STORE_ALIAS (alias_key VARCHAR, location_id VARCHAR);
INSERT INTO STAGING.STORE_ALIAS (alias_key, location_id) VALUES
  ('DOWNTOWN ROBSON','L01'), ('DT ROBSON','L01'), ('ROBSON ST','L01'),
  ('KITSILANO','L02'), ('KITS','L02'),
  ('METROTOWN','L03'),
  ('RICHMOND CENTRE','L04'), ('RICHMOND CENTER','L04'), ('RMD CENTRE','L04'),
  ('GUILDFORD','L05'), ('SURREY - GUILDFORD','L05'),
  ('COQUITLAM CENTRE','L06'), ('COQUITLAM CTR','L06'), ('COQUITLAM','L06'),
  ('LONSDALE','L07'), ('N. VAN LONSDALE','L07'),
  ('WILLOWBROOK','L08'), ('LANGLEY WILLOWBROOK','L08'),
  ('COLUMBIA SQUARE','L09'), ('COLUMBIA SQ','L09'), ('NEW WEST','L09'),
  ('SEVENOAKS','L10'), ('ABBOTSFORD SEVENOAKS','L10');

CREATE OR REPLACE TABLE STAGING.ROLE_ALIAS (alias_key VARCHAR, role VARCHAR);
INSERT INTO STAGING.ROLE_ALIAS (alias_key, role) VALUES
  ('SERVER','Server'), ('HOST','Host'), ('BARTENDER','Bartender'),
  ('LINE COOK','Line Cook'), ('COOK - LINE','Line Cook'), ('PREP COOK','Prep Cook'),
  ('DISHWASHER','Dishwasher'), ('DISH','Dishwasher'), ('MANAGER','Manager');

-- =====================================================================
-- DIMENSIONS
-- =====================================================================
CREATE OR REPLACE TABLE CORE.DIM_LOCATION AS
SELECT location_id, location_name, city, region, area_manager,
       TRY_TO_DOUBLE(latitude)  AS latitude,
       TRY_TO_DOUBLE(longitude) AS longitude,
       TRY_TO_NUMBER(seats)     AS seats,
       TRY_TO_NUMBER(has_patio) AS has_patio,
       TRY_TO_DATE(open_date, 'YYYY-MM-DD') AS open_date
FROM RAW.REF_LOCATIONS;

CREATE OR REPLACE TABLE CORE.DIM_INGREDIENT AS
SELECT ingredient_id, ingredient_name, ingredient_category, unit, supplier,
       TRY_TO_NUMBER(std_cost_2025, 12, 4)      AS std_cost_2025,
       TRY_TO_NUMBER(std_cost_2026, 12, 4)      AS std_cost_2026,
       TRY_TO_NUMBER(expected_waste_rate, 6, 4) AS expected_waste_rate,
       TRY_TO_NUMBER(is_produce)                AS is_produce
FROM RAW.REF_INGREDIENTS;

CREATE OR REPLACE TABLE CORE.BRIDGE_RECIPE AS
SELECT menu_item_id, ingredient_id,
       TRY_TO_NUMBER(qty_per_item, 12, 4) AS qty_per_item,
       unit
FROM RAW.REF_RECIPES;

-- Menu items with plate cost and contribution margin (menu engineering inputs)
CREATE OR REPLACE TABLE CORE.DIM_MENU_ITEM AS
WITH m AS (
  SELECT menu_item_id, menu_item_name, category,
         TRY_TO_NUMBER(is_main)               AS is_main,
         TRY_TO_NUMBER(price_2025, 10, 2)     AS price_2025,
         TRY_TO_NUMBER(price_2026, 10, 2)     AS price_2026,
         TRY_TO_DATE(price_change_date, 'YYYY-MM-DD') AS price_change_date
  FROM RAW.REF_MENU
),
c AS (
  SELECT r.menu_item_id,
         SUM(r.qty_per_item * i.std_cost_2025) AS food_cost_2025,
         SUM(r.qty_per_item * i.std_cost_2026) AS food_cost_2026
  FROM CORE.BRIDGE_RECIPE r
  JOIN CORE.DIM_INGREDIENT i ON i.ingredient_id = r.ingredient_id
  GROUP BY r.menu_item_id
)
SELECT m.menu_item_id, m.menu_item_name, m.category, m.is_main,
       m.price_2025, m.price_2026, m.price_change_date,
       ROUND(c.food_cost_2025, 3)                          AS std_food_cost_2025,
       ROUND(c.food_cost_2026, 3)                          AS std_food_cost_2026,
       ROUND(m.price_2025 - c.food_cost_2025, 2)           AS contribution_margin_2025,
       ROUND(m.price_2026 - c.food_cost_2026, 2)           AS contribution_margin_2026,
       ROUND(c.food_cost_2025 / m.price_2025, 4)           AS food_cost_pct_2025,
       ROUND(c.food_cost_2026 / m.price_2026, 4)           AS food_cost_pct_2026
FROM m
LEFT JOIN c ON c.menu_item_id = m.menu_item_id;

CREATE OR REPLACE TABLE CORE.DIM_EMPLOYEE AS
SELECT employee_id, employee_name, home_location_id, role,
       TRY_TO_NUMBER(hourly_wage, 8, 2)   AS hourly_wage_2025,
       TRY_TO_DATE(hire_date, 'YYYY-MM-DD') AS hire_date
FROM RAW.REF_EMPLOYEES;

-- Calendar table generated in SQL (no source file needed)
CREATE OR REPLACE TABLE CORE.DIM_DATE AS
WITH d AS (
  SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2025-01-05'::DATE) AS calendar_date
  FROM TABLE(GENERATOR(ROWCOUNT => 700))
),
hol AS (
  SELECT hdate::DATE AS hdate, holiday_name FROM (VALUES
    ('2025-01-01','New Year''s Day'), ('2025-02-17','Family Day'), ('2025-04-18','Good Friday'),
    ('2025-05-19','Victoria Day'), ('2025-07-01','Canada Day'), ('2025-08-04','B.C. Day'),
    ('2025-09-01','Labour Day'), ('2025-09-30','Truth and Reconciliation Day'), ('2025-10-13','Thanksgiving'),
    ('2025-11-11','Remembrance Day'), ('2025-12-25','Christmas Day'),
    ('2026-01-01','New Year''s Day'), ('2026-02-16','Family Day'), ('2026-04-03','Good Friday'),
    ('2026-05-18','Victoria Day'), ('2026-07-01','Canada Day'), ('2026-08-03','B.C. Day')
  ) AS v (hdate, holiday_name)
)
SELECT d.calendar_date,
       YEAR(d.calendar_date)                         AS year,
       'Q' || QUARTER(d.calendar_date)               AS quarter,
       MONTH(d.calendar_date)                        AS month_num,
       MONTHNAME(d.calendar_date)                    AS month_name,
       TO_CHAR(d.calendar_date, 'YYYY-MM')           AS year_month,
       DAYNAME(d.calendar_date)                      AS day_of_week,
       DAYOFWEEKISO(d.calendar_date)                 AS dow_num,          -- Mon = 1
       IFF(DAYOFWEEKISO(d.calendar_date) >= 6, 1, 0) AS is_weekend,
       DATE_TRUNC('WEEK', d.calendar_date)           AS week_start,       -- Monday
       WEEKISO(d.calendar_date)                      AS iso_week,
       COALESCE(h.holiday_name, '')                  AS holiday_name,
       IFF(h.hdate IS NULL, 0, 1)                    AS is_stat_holiday,
       CASE WHEN MONTH(d.calendar_date) IN (12, 1, 2) THEN 'Winter'
            WHEN MONTH(d.calendar_date) IN (3, 4, 5)  THEN 'Spring'
            WHEN MONTH(d.calendar_date) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Fall' END                          AS season
FROM d
LEFT JOIN hol h ON h.hdate = d.calendar_date
WHERE d.calendar_date <= '2026-08-30'::DATE;

-- =====================================================================
-- FACTS
-- =====================================================================

-- POS item sales: fix dates, map stores, impute missing net, drop duplicates
CREATE OR REPLACE TABLE CORE.FACT_SALES_ITEM_DAYPART AS
WITH typed AS (
  SELECT COALESCE(TRY_TO_DATE(s.business_date, 'YYYY-MM-DD'),
                  TRY_TO_DATE(s.business_date, 'DD-MON-YYYY'))  AS business_date,
         a.location_id,
         s.daypart,
         s.menu_item_id,
         TRY_TO_NUMBER(s.qty_sold)              AS qty_sold,
         TRY_TO_NUMBER(s.unit_price, 10, 2)     AS unit_price,
         TRY_TO_NUMBER(s.gross_sales, 12, 2)    AS gross_sales,
         TRY_TO_NUMBER(s.discounts, 12, 2)      AS discounts,
         TRY_TO_NUMBER(s.comps, 12, 2)          AS comps,
         TRY_TO_NUMBER(s.net_sales, 12, 2)      AS net_sales_raw,
         s._loaded_at
  FROM RAW.POS_SALES s
  LEFT JOIN STAGING.STORE_ALIAS a ON a.alias_key = UPPER(TRIM(s.store))
)
SELECT business_date, location_id, daypart, menu_item_id,
       qty_sold, unit_price, gross_sales, discounts, comps,
       COALESCE(net_sales_raw, gross_sales - discounts - comps) AS net_sales,
       IFF(net_sales_raw IS NULL, 1, 0)                         AS is_net_sales_imputed
FROM typed
QUALIFY ROW_NUMBER() OVER (PARTITION BY business_date, location_id, daypart, menu_item_id
                           ORDER BY _loaded_at) = 1;

-- POS hourly covers
CREATE OR REPLACE TABLE CORE.FACT_COVERS_HOURLY AS
WITH typed AS (
  SELECT COALESCE(TRY_TO_DATE(c.business_date, 'YYYY-MM-DD'),
                  TRY_TO_DATE(c.business_date, 'DD-MON-YYYY')) AS business_date,
         a.location_id,
         TRY_TO_NUMBER(c.hour_of_day)          AS hour_of_day,
         TRY_TO_NUMBER(c.covers)               AS covers,
         TRY_TO_NUMBER(c.net_sales, 12, 2)     AS net_sales,
         c._loaded_at
  FROM RAW.POS_COVERS_HOURLY c
  LEFT JOIN STAGING.STORE_ALIAS a ON a.alias_key = UPPER(TRIM(c.store))
)
SELECT business_date, location_id, hour_of_day,
       CASE WHEN hour_of_day BETWEEN 7  AND 10 THEN 'Breakfast'
            WHEN hour_of_day BETWEEN 11 AND 14 THEN 'Lunch'
            WHEN hour_of_day BETWEEN 15 AND 16 THEN 'Afternoon'
            WHEN hour_of_day BETWEEN 17 AND 20 THEN 'Dinner'
            ELSE 'Late Night' END AS daypart,
       covers, net_sales
FROM typed
QUALIFY ROW_NUMBER() OVER (PARTITION BY business_date, location_id, hour_of_day ORDER BY _loaded_at) = 1;

-- Timeclock shifts: map store and role, dedupe, impute missed clock-outs, cost them
-- Business rule: 2.5% general wage increase effective 2026-01-01
CREATE OR REPLACE TABLE CORE.FACT_LABOUR_SHIFTS AS
WITH typed AS (
  SELECT t.shift_id,
         TRY_TO_DATE(t.business_date, 'YYYY-MM-DD')                   AS business_date,
         a.location_id,
         t.employee_id,
         r.role,
         TRY_TO_TIMESTAMP_NTZ(t.scheduled_start, 'YYYY-MM-DD HH24:MI') AS scheduled_start,
         TRY_TO_TIMESTAMP_NTZ(t.scheduled_end,   'YYYY-MM-DD HH24:MI') AS scheduled_end,
         TRY_TO_TIMESTAMP_NTZ(t.actual_start,    'YYYY-MM-DD HH24:MI') AS actual_start,
         TRY_TO_TIMESTAMP_NTZ(t.actual_end,      'YYYY-MM-DD HH24:MI') AS actual_end_raw
  FROM RAW.TIMECLOCK t
  LEFT JOIN STAGING.STORE_ALIAS a ON a.alias_key = UPPER(TRIM(t.store))
  LEFT JOIN STAGING.ROLE_ALIAS  r ON r.alias_key = UPPER(TRIM(t.role))
  QUALIFY ROW_NUMBER() OVER (PARTITION BY t.shift_id ORDER BY t._loaded_at) = 1
),
fixed AS (
  SELECT typed.*,
         COALESCE(actual_end_raw, scheduled_end)      AS actual_end,
         IFF(actual_end_raw IS NULL, 1, 0)            AS is_clock_out_imputed
  FROM typed
),
costed AS (
  SELECT f.*,
         DATEDIFF('minute', f.scheduled_start, f.scheduled_end) / 60        AS scheduled_hours,
         ROUND(DATEDIFF('minute', f.actual_start, f.actual_end) / 60, 2)     AS actual_hours,
         ROUND(e.hourly_wage_2025 * IFF(f.business_date >= '2026-01-01'::DATE, 1.025, 1), 2) AS hourly_wage
  FROM fixed f
  LEFT JOIN CORE.DIM_EMPLOYEE e ON e.employee_id = f.employee_id
)
SELECT shift_id, business_date, location_id, employee_id, role,
       CASE HOUR(scheduled_start) WHEN 7 THEN 'AM' WHEN 11 THEN 'MID' ELSE 'PM' END AS shift_block,
       scheduled_start, scheduled_end, actual_start, actual_end, is_clock_out_imputed,
       scheduled_hours, actual_hours, hourly_wage,
       ROUND(actual_hours * hourly_wage, 2) AS labour_cost
FROM costed;

-- Labour by hour (for the heatmap): split each shift across the clock hours it covers,
-- then line it up with hourly covers and sales
CREATE OR REPLACE TABLE CORE.FACT_LABOUR_HOURLY AS
WITH hours AS (
  SELECT h AS hour_of_day FROM (VALUES (6),(7),(8),(9),(10),(11),(12),(13),(14),
                                       (15),(16),(17),(18),(19),(20),(21),(22),(23)) AS v (h)
),
s AS (
  SELECT business_date, location_id, hourly_wage,
         DATEDIFF('minute', business_date::TIMESTAMP_NTZ, actual_start) AS start_min,
         DATEDIFF('minute', business_date::TIMESTAMP_NTZ, actual_end)   AS end_min
  FROM CORE.FACT_LABOUR_SHIFTS
),
split AS (
  SELECT s.business_date, s.location_id, h.hour_of_day, s.hourly_wage,
         (LEAST(s.end_min, (h.hour_of_day + 1) * 60) - GREATEST(s.start_min, h.hour_of_day * 60)) / 60 AS hrs
  FROM s
  JOIN hours h
    ON h.hour_of_day * 60 < s.end_min
   AND (h.hour_of_day + 1) * 60 > s.start_min
),
lab AS (
  SELECT business_date, location_id, hour_of_day,
         SUM(hrs)               AS labour_hours,
         SUM(hrs * hourly_wage) AS labour_cost
  FROM split
  GROUP BY business_date, location_id, hour_of_day
)
SELECT COALESCE(l.business_date, c.business_date) AS business_date,
       COALESCE(l.location_id,  c.location_id)    AS location_id,
       COALESCE(l.hour_of_day,  c.hour_of_day)    AS hour_of_day,
       ROUND(COALESCE(l.labour_hours, 0), 2)      AS labour_hours,
       ROUND(COALESCE(l.labour_cost, 0), 2)       AS labour_cost,
       COALESCE(c.covers, 0)                      AS covers,
       COALESCE(c.net_sales, 0)                   AS net_sales
FROM lab l
FULL OUTER JOIN CORE.FACT_COVERS_HOURLY c
  ON  c.business_date = l.business_date
  AND c.location_id   = l.location_id
  AND c.hour_of_day   = l.hour_of_day;

-- Purchases: dedupe, standardise supplier names, convert lb -> kg
CREATE OR REPLACE TABLE CORE.FACT_PURCHASES AS
WITH d AS (
  SELECT p.po_line_id, p.delivery_date, p.store, p.supplier, p.ingredient_id,
         p.qty_received, p.unit, p.unit_cost, p.line_total, a.location_id
  FROM RAW.PURCHASING p
  LEFT JOIN STAGING.STORE_ALIAS a ON a.alias_key = UPPER(TRIM(p.store))
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.po_line_id ORDER BY p._loaded_at) = 1
),
sup AS (SELECT DISTINCT supplier AS supplier_master FROM RAW.REF_INGREDIENTS)
SELECT d.po_line_id,
       TRY_TO_DATE(d.delivery_date, 'YYYY-MM-DD') AS delivery_date,
       d.location_id,
       sup.supplier_master                         AS supplier,
       d.ingredient_id,
       ROUND(IFF(d.unit = 'lb', TRY_TO_DOUBLE(d.qty_received) / 2.20462, TRY_TO_DOUBLE(d.qty_received)), 3) AS qty_received,
       IFF(d.unit = 'lb', 'kg', d.unit)                                                                      AS unit,
       ROUND(IFF(d.unit = 'lb', TRY_TO_DOUBLE(d.unit_cost) * 2.20462, TRY_TO_DOUBLE(d.unit_cost)), 3)       AS unit_cost,
       TRY_TO_NUMBER(d.line_total, 12, 2)                                                                    AS line_total,
       IFF(d.unit = 'lb', 1, 0)                                                                              AS is_unit_converted
FROM d
LEFT JOIN sup ON UPPER(TRIM(d.supplier)) = UPPER(sup.supplier_master);

CREATE OR REPLACE TABLE CORE.FACT_INVENTORY_COUNTS AS
SELECT TRY_TO_DATE(c.count_date, 'YYYY-MM-DD') AS count_date,
       a.location_id, c.ingredient_id,
       TRY_TO_DOUBLE(c.qty_on_hand) AS qty_on_hand,
       c.unit
FROM RAW.INVENTORY_COUNTS c
LEFT JOIN STAGING.STORE_ALIAS a ON a.alias_key = UPPER(TRIM(c.store));

CREATE OR REPLACE TABLE CORE.FACT_WASTE_LOG AS
SELECT TRY_TO_DATE(w.waste_date, 'YYYY-MM-DD') AS waste_date,
       a.location_id, w.ingredient_id,
       TRY_TO_DOUBLE(w.qty_wasted) AS qty_wasted,
       w.unit, w.reason
FROM RAW.WASTE_LOG w
LEFT JOIN STAGING.STORE_ALIAS a ON a.alias_key = UPPER(TRIM(w.store));

-- Food cost engine: weekly theoretical vs actual usage per store x ingredient
--   theoretical = items sold x recipe quantity          (what we SHOULD have used)
--   actual      = opening count + purchases - closing   (what we DID use)
--   unit_cost   = what this store paid that week (falls back to chain average, then standard)
-- The $ columns add up:  theoretical_cost_at_standard + price_variance
--                        + recorded_waste_cost + unexplained_variance = actual_cost
CREATE OR REPLACE TABLE CORE.FACT_INGREDIENT_USAGE_WEEKLY AS
WITH theo AS (
  SELECT DATE_TRUNC('WEEK', s.business_date) AS week_start, s.location_id, r.ingredient_id,
         SUM(s.qty_sold * r.qty_per_item)    AS theoretical_qty
  FROM CORE.FACT_SALES_ITEM_DAYPART s
  JOIN CORE.BRIDGE_RECIPE r ON r.menu_item_id = s.menu_item_id
  GROUP BY 1, 2, 3
),
purch AS (
  SELECT DATE_TRUNC('WEEK', delivery_date) AS week_start, location_id, ingredient_id,
         SUM(qty_received) AS purchased_qty,
         SUM(line_total)   AS purchased_cost
  FROM CORE.FACT_PURCHASES
  GROUP BY 1, 2, 3
),
chain_price AS (
  SELECT week_start, ingredient_id, SUM(purchased_cost) / NULLIF(SUM(purchased_qty), 0) AS chain_unit_cost
  FROM purch
  GROUP BY 1, 2
),
waste AS (
  SELECT DATE_TRUNC('WEEK', waste_date) AS week_start, location_id, ingredient_id,
         SUM(qty_wasted) AS recorded_waste_qty
  FROM CORE.FACT_WASTE_LOG
  GROUP BY 1, 2, 3
),
base AS (
  SELECT t.week_start, t.location_id, t.ingredient_id,
         t.theoretical_qty,
         o.qty_on_hand                       AS opening_qty,
         COALESCE(p.purchased_qty, 0)        AS purchased_qty,
         c.qty_on_hand                       AS closing_qty,
         o.qty_on_hand + COALESCE(p.purchased_qty, 0) - c.qty_on_hand AS actual_qty,
         COALESCE(w.recorded_waste_qty, 0)   AS recorded_waste_qty,
         COALESCE(p.purchased_cost / NULLIF(p.purchased_qty, 0), cp.chain_unit_cost,
                  IFF(YEAR(t.week_start) >= 2026, i.std_cost_2026, i.std_cost_2025)) AS unit_cost,
         IFF(YEAR(t.week_start) >= 2026, i.std_cost_2026, i.std_cost_2025)            AS std_unit_cost
  FROM theo t
  JOIN CORE.DIM_INGREDIENT i ON i.ingredient_id = t.ingredient_id
  LEFT JOIN CORE.FACT_INVENTORY_COUNTS o
         ON o.location_id = t.location_id AND o.ingredient_id = t.ingredient_id
        AND o.count_date = DATEADD('day', -1, t.week_start)
  LEFT JOIN CORE.FACT_INVENTORY_COUNTS c
         ON c.location_id = t.location_id AND c.ingredient_id = t.ingredient_id
        AND c.count_date = DATEADD('day', 6, t.week_start)
  LEFT JOIN purch p       ON p.week_start = t.week_start AND p.location_id = t.location_id AND p.ingredient_id = t.ingredient_id
  LEFT JOIN chain_price cp ON cp.week_start = t.week_start AND cp.ingredient_id = t.ingredient_id
  LEFT JOIN waste w       ON w.week_start = t.week_start AND w.location_id = t.location_id AND w.ingredient_id = t.ingredient_id
)
SELECT week_start, location_id, ingredient_id,
       ROUND(theoretical_qty, 3)     AS theoretical_qty,
       ROUND(opening_qty, 3)         AS opening_qty,
       ROUND(purchased_qty, 3)       AS purchased_qty,
       ROUND(closing_qty, 3)         AS closing_qty,
       ROUND(actual_qty, 3)          AS actual_qty,
       ROUND(recorded_waste_qty, 3)  AS recorded_waste_qty,
       ROUND(actual_qty / NULLIF(theoretical_qty, 0) - 1, 4) AS usage_variance_pct,
       ROUND(unit_cost, 4)           AS unit_cost,
       ROUND(std_unit_cost, 4)       AS std_unit_cost,
       ROUND(theoretical_qty * std_unit_cost, 2)                                   AS theoretical_cost_at_standard,
       ROUND(theoretical_qty * (unit_cost - std_unit_cost), 2)                     AS price_variance,
       ROUND(recorded_waste_qty * unit_cost, 2)                                    AS recorded_waste_cost,
       ROUND((actual_qty - theoretical_qty - recorded_waste_qty) * unit_cost, 2)   AS unexplained_variance,
       ROUND(actual_qty * unit_cost, 2)                                            AS actual_cost
FROM base;

-- Menu engineering (mains, calendar 2025, 2025 prices and standard costs)
-- Popularity threshold = 70% of an equal share; margin threshold = mix-weighted average CM
CREATE OR REPLACE TABLE CORE.MENU_ENGINEERING_2025 AS
WITH sold AS (
  SELECT s.menu_item_id, SUM(s.qty_sold) AS qty_sold
  FROM CORE.FACT_SALES_ITEM_DAYPART s
  WHERE YEAR(s.business_date) = 2025
  GROUP BY 1
),
mains AS (
  SELECT m.menu_item_id, m.menu_item_name, m.category, m.price_2025, m.std_food_cost_2025,
         m.food_cost_pct_2025, m.contribution_margin_2025, s.qty_sold,
         s.qty_sold / SUM(s.qty_sold) OVER ()                                         AS menu_mix_pct,
         SUM(s.qty_sold * m.contribution_margin_2025) OVER () / SUM(s.qty_sold) OVER () AS avg_cm,
         0.7 / COUNT(*) OVER ()                                                       AS popularity_threshold
  FROM CORE.DIM_MENU_ITEM m
  JOIN sold s ON s.menu_item_id = m.menu_item_id
  WHERE m.is_main = 1
)
SELECT menu_item_id, menu_item_name, category, price_2025, std_food_cost_2025, food_cost_pct_2025,
       contribution_margin_2025, qty_sold,
       ROUND(menu_mix_pct, 4)          AS menu_mix_pct,
       ROUND(avg_cm, 2)                AS avg_contribution_margin,
       ROUND(popularity_threshold, 4)  AS popularity_threshold,
       CASE WHEN menu_mix_pct >= popularity_threshold AND contribution_margin_2025 >= avg_cm THEN 'Star'
            WHEN menu_mix_pct >= popularity_threshold                                    THEN 'Plowhorse'
            WHEN contribution_margin_2025 >= avg_cm                                      THEN 'Puzzle'
            ELSE 'Dog' END             AS quadrant
FROM mains;

-- Quick look at what was built
SELECT 'DIM_DATE' AS table_name, COUNT(*) AS row_count FROM CORE.DIM_DATE
UNION ALL SELECT 'DIM_LOCATION', COUNT(*) FROM CORE.DIM_LOCATION
UNION ALL SELECT 'DIM_MENU_ITEM', COUNT(*) FROM CORE.DIM_MENU_ITEM
UNION ALL SELECT 'DIM_INGREDIENT', COUNT(*) FROM CORE.DIM_INGREDIENT
UNION ALL SELECT 'DIM_EMPLOYEE', COUNT(*) FROM CORE.DIM_EMPLOYEE
UNION ALL SELECT 'BRIDGE_RECIPE', COUNT(*) FROM CORE.BRIDGE_RECIPE
UNION ALL SELECT 'FACT_SALES_ITEM_DAYPART', COUNT(*) FROM CORE.FACT_SALES_ITEM_DAYPART
UNION ALL SELECT 'FACT_COVERS_HOURLY', COUNT(*) FROM CORE.FACT_COVERS_HOURLY
UNION ALL SELECT 'FACT_LABOUR_SHIFTS', COUNT(*) FROM CORE.FACT_LABOUR_SHIFTS
UNION ALL SELECT 'FACT_LABOUR_HOURLY', COUNT(*) FROM CORE.FACT_LABOUR_HOURLY
UNION ALL SELECT 'FACT_PURCHASES', COUNT(*) FROM CORE.FACT_PURCHASES
UNION ALL SELECT 'FACT_INVENTORY_COUNTS', COUNT(*) FROM CORE.FACT_INVENTORY_COUNTS
UNION ALL SELECT 'FACT_WASTE_LOG', COUNT(*) FROM CORE.FACT_WASTE_LOG
UNION ALL SELECT 'FACT_INGREDIENT_USAGE_WEEKLY', COUNT(*) FROM CORE.FACT_INGREDIENT_USAGE_WEEKLY
UNION ALL SELECT 'MENU_ENGINEERING_2025', COUNT(*) FROM CORE.MENU_ENGINEERING_2025;
