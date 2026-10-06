-- =====================================================================
-- 04_data_quality.sql  |  GOVERNANCE: data-quality checks + reconciliation
-- Writes one row per check to CORE.DQ_RESULTS (kept as a history log).
--   FIXED = a known source problem the pipeline repaired (count shown)
--   PASS  = a rule that must be zero, and is
--   FAIL  = a rule that must be zero, and isn't -> investigate before reporting
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE HARBOURLINE_WH;
USE DATABASE HARBOURLINE;

CREATE TABLE IF NOT EXISTS CORE.DQ_RESULTS (
  run_at       TIMESTAMP_LTZ,
  check_id     NUMBER,
  check_area   VARCHAR,
  check_name   VARCHAR,
  issue_count  NUMBER,
  rule_type    VARCHAR,
  status       VARCHAR
);

INSERT INTO CORE.DQ_RESULTS (run_at, check_id, check_area, check_name, issue_count, rule_type, status)
WITH checks AS (
  -- ---------------- POS sales ----------------
  SELECT 1 AS check_id, 'POS sales' AS check_area, 'Duplicate rows removed' AS check_name,
         (SELECT COUNT(*) FROM RAW.POS_SALES) - (SELECT COUNT(*) FROM CORE.FACT_SALES_ITEM_DAYPART) AS issue_count,
         'FIXED' AS rule_type
  UNION ALL
  SELECT 2, 'POS sales', 'Dates in DD-MON-YYYY format standardised',
         (SELECT COUNT(*) FROM RAW.POS_SALES
           WHERE TRY_TO_DATE(business_date, 'YYYY-MM-DD') IS NULL
             AND TRY_TO_DATE(business_date, 'DD-MON-YYYY') IS NOT NULL), 'FIXED'
  UNION ALL
  SELECT 3, 'POS sales', 'Missing net_sales rebuilt as gross - discounts - comps',
         (SELECT SUM(is_net_sales_imputed) FROM CORE.FACT_SALES_ITEM_DAYPART), 'FIXED'
  UNION ALL
  SELECT 4, 'POS sales', 'Unparseable business dates',
         (SELECT COUNT(*) FROM CORE.FACT_SALES_ITEM_DAYPART WHERE business_date IS NULL), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 5, 'POS sales', 'Item names that do not match the menu master (ignoring case/spaces)',
         (SELECT COUNT(*) FROM RAW.POS_SALES s JOIN RAW.REF_MENU m ON m.menu_item_id = s.menu_item_id
           WHERE UPPER(TRIM(s.menu_item_name)) <> UPPER(TRIM(m.menu_item_name))), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 6, 'POS sales', 'Sales rows for menu items not in the menu master',
         (SELECT COUNT(*) FROM CORE.FACT_SALES_ITEM_DAYPART s
           LEFT JOIN CORE.DIM_MENU_ITEM m ON m.menu_item_id = s.menu_item_id
           WHERE m.menu_item_id IS NULL), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 7, 'POS sales', 'Rows where net <> gross - discounts - comps (> $0.01)',
         (SELECT COUNT(*) FROM CORE.FACT_SALES_ITEM_DAYPART
           WHERE ABS(net_sales - (gross_sales - discounts - comps)) > 0.01), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 8, 'POS sales', 'Store-days where hourly sales <> item sales (> $1)',
         (SELECT COUNT(*) FROM (
            SELECT COALESCE(i.business_date, h.business_date) AS d
            FROM (SELECT business_date, location_id, SUM(net_sales) AS amt
                    FROM CORE.FACT_SALES_ITEM_DAYPART GROUP BY 1, 2) i
            FULL OUTER JOIN (SELECT business_date, location_id, SUM(net_sales) AS amt
                               FROM CORE.FACT_COVERS_HOURLY GROUP BY 1, 2) h
              ON h.business_date = i.business_date AND h.location_id = i.location_id
            WHERE ABS(COALESCE(i.amt, 0) - COALESCE(h.amt, 0)) > 1)), 'MUST_BE_ZERO'
  -- ---------------- Store master data ----------------
  UNION ALL
  SELECT 9, 'Master data', 'Store-name variants mapped to master (rows across all extracts)',
         (SELECT COUNT(*)
            FROM (          SELECT store FROM RAW.POS_SALES
                  UNION ALL SELECT store FROM RAW.POS_COVERS_HOURLY
                  UNION ALL SELECT store FROM RAW.TIMECLOCK
                  UNION ALL SELECT store FROM RAW.PURCHASING
                  UNION ALL SELECT store FROM RAW.INVENTORY_COUNTS
                  UNION ALL SELECT store FROM RAW.WASTE_LOG) s
            JOIN STAGING.STORE_ALIAS a ON a.alias_key = UPPER(TRIM(s.store))
            JOIN CORE.DIM_LOCATION  l ON l.location_id = a.location_id
           WHERE s.store <> l.location_name),
         'FIXED'
  UNION ALL
  SELECT 10, 'Master data', 'Rows with a store name that could not be mapped (all facts)',
         (SELECT COUNT(*) FROM CORE.FACT_SALES_ITEM_DAYPART WHERE location_id IS NULL)
       + (SELECT COUNT(*) FROM CORE.FACT_COVERS_HOURLY      WHERE location_id IS NULL)
       + (SELECT COUNT(*) FROM CORE.FACT_LABOUR_SHIFTS      WHERE location_id IS NULL)
       + (SELECT COUNT(*) FROM CORE.FACT_PURCHASES          WHERE location_id IS NULL)
       + (SELECT COUNT(*) FROM CORE.FACT_INVENTORY_COUNTS   WHERE location_id IS NULL)
       + (SELECT COUNT(*) FROM CORE.FACT_WASTE_LOG          WHERE location_id IS NULL), 'MUST_BE_ZERO'
  -- ---------------- Labour ----------------
  UNION ALL
  SELECT 11, 'Labour', 'Duplicate timeclock rows removed',
         (SELECT COUNT(*) FROM RAW.TIMECLOCK) - (SELECT COUNT(*) FROM CORE.FACT_LABOUR_SHIFTS), 'FIXED'
  UNION ALL
  SELECT 12, 'Labour', 'Role labels standardised (e.g. "LINE COOK", "Cook - Line")',
         (SELECT COUNT(*) FROM RAW.TIMECLOCK t JOIN STAGING.ROLE_ALIAS r ON r.alias_key = UPPER(TRIM(t.role))
           WHERE t.role <> r.role), 'FIXED'
  UNION ALL
  SELECT 13, 'Labour', 'Missed clock-outs set to scheduled end (flagged)',
         (SELECT SUM(is_clock_out_imputed) FROM CORE.FACT_LABOUR_SHIFTS), 'FIXED'
  UNION ALL
  SELECT 14, 'Labour', 'Shifts with a role that could not be mapped',
         (SELECT COUNT(*) FROM CORE.FACT_LABOUR_SHIFTS WHERE role IS NULL), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 15, 'Labour', 'Shifts ending before they start',
         (SELECT COUNT(*) FROM CORE.FACT_LABOUR_SHIFTS WHERE actual_end <= actual_start), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 16, 'Labour', 'Shifts for employees not in the employee master',
         (SELECT COUNT(*) FROM CORE.FACT_LABOUR_SHIFTS WHERE hourly_wage IS NULL), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 17, 'Labour', 'Employees with two shifts on the same day',
         (SELECT COUNT(*) FROM (SELECT employee_id, business_date FROM CORE.FACT_LABOUR_SHIFTS
                                 GROUP BY 1, 2 HAVING COUNT(*) > 1)), 'MUST_BE_ZERO'
  -- ---------------- Inventory & purchasing ----------------
  UNION ALL
  SELECT 18, 'Inventory', 'Duplicate purchase lines removed',
         (SELECT COUNT(*) FROM RAW.PURCHASING) - (SELECT COUNT(*) FROM CORE.FACT_PURCHASES), 'FIXED'
  UNION ALL
  SELECT 19, 'Inventory', 'Produce lines received in lb converted to kg',
         (SELECT SUM(is_unit_converted) FROM CORE.FACT_PURCHASES), 'FIXED'
  UNION ALL
  SELECT 20, 'Inventory', 'Purchase unit <> ingredient master unit (after conversion)',
         (SELECT COUNT(*) FROM CORE.FACT_PURCHASES p JOIN CORE.DIM_INGREDIENT i ON i.ingredient_id = p.ingredient_id
           WHERE p.unit <> i.unit), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 21, 'Inventory', 'Purchase lines with a supplier not in the master list',
         (SELECT COUNT(*) FROM CORE.FACT_PURCHASES WHERE supplier IS NULL), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 22, 'Inventory', 'Negative inventory counts',
         (SELECT COUNT(*) FROM CORE.FACT_INVENTORY_COUNTS WHERE qty_on_hand < 0), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 23, 'Inventory', 'Usage weeks missing an opening or closing count',
         (SELECT COUNT(*) FROM CORE.FACT_INGREDIENT_USAGE_WEEKLY WHERE opening_qty IS NULL OR closing_qty IS NULL), 'MUST_BE_ZERO'
  UNION ALL
  SELECT 24, 'Inventory', 'Food-cost bridge does not add up (> $0.05)',
         (SELECT COUNT(*) FROM CORE.FACT_INGREDIENT_USAGE_WEEKLY
           WHERE ABS(theoretical_cost_at_standard + price_variance + recorded_waste_cost + unexplained_variance - actual_cost) > 0.05), 'MUST_BE_ZERO'
)
SELECT CURRENT_TIMESTAMP(), check_id, check_area, check_name, COALESCE(issue_count, 0), rule_type,
       CASE WHEN rule_type = 'FIXED' THEN 'FIXED'
            WHEN COALESCE(issue_count, 0) = 0 THEN 'PASS'
            ELSE 'FAIL' END
FROM checks;

-- Reconciliation: monthly net sales, source vs CORE
-- (small differences = duplicates removed and missing values rebuilt; that's the point)
WITH src AS (
  SELECT TO_CHAR(COALESCE(TRY_TO_DATE(business_date, 'YYYY-MM-DD'), TRY_TO_DATE(business_date, 'DD-MON-YYYY')), 'YYYY-MM') AS year_month,
         SUM(TRY_TO_NUMBER(net_sales, 12, 2)) AS raw_net_sales
  FROM RAW.POS_SALES GROUP BY 1
),
cor AS (
  SELECT TO_CHAR(business_date, 'YYYY-MM') AS year_month, SUM(net_sales) AS core_net_sales
  FROM CORE.FACT_SALES_ITEM_DAYPART GROUP BY 1
)
SELECT src.year_month, src.raw_net_sales, cor.core_net_sales,
       cor.core_net_sales - src.raw_net_sales AS difference
FROM src JOIN cor ON cor.year_month = src.year_month
ORDER BY src.year_month;

-- Latest run (last statement, so Run All shows this table)
SELECT check_id, check_area, check_name, issue_count, status
FROM CORE.DQ_RESULTS
WHERE run_at = (SELECT MAX(run_at) FROM CORE.DQ_RESULTS)
ORDER BY check_id;
