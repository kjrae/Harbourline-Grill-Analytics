-- =====================================================================
-- 06_ai_recommendations.sql  |  Claude writes the GM notes (Snowflake Cortex)
-- SQL computes every number. Claude only turns the numbers into sentences.
-- The prompt is stored next to the answer so every note can be audited.
-- Output: CORE.AI_RECOMMENDATIONS (1 chain row + 1 row per store)
-- Run All. Takes about a minute (11 calls to Claude).
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE HARBOURLINE_WH;
USE DATABASE HARBOURLINE;

-- 1. The numbers (2026 YTD), one row per store plus one chain row
CREATE OR REPLACE TABLE CORE.AI_KPI_INPUT AS
WITH lab AS (
  SELECT location_id, SUM(labour_cost) AS lc, SUM(net_sales) AS s
  FROM CORE.FACT_LABOUR_HOURLY
  WHERE YEAR(business_date) = 2026
  GROUP BY location_id
),
lab_day AS (      -- each store's worst day of the week for labour %
  SELECT location_id, DAYNAME(business_date) AS dow,
         SUM(labour_cost) / NULLIF(SUM(net_sales), 0) AS lp
  FROM CORE.FACT_LABOUR_HOURLY
  WHERE YEAR(business_date) = 2026
  GROUP BY location_id, DAYNAME(business_date)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY location_id
                             ORDER BY SUM(labour_cost) / NULLIF(SUM(net_sales), 0) DESC) = 1
),
sales AS (
  SELECT location_id, SUM(net_sales) AS ns
  FROM CORE.FACT_SALES_ITEM_DAYPART
  WHERE YEAR(business_date) = 2026
  GROUP BY location_id
),
food AS (
  SELECT location_id,
         SUM(actual_cost) AS ac, SUM(theoretical_cost_at_standard) AS tc,
         SUM(price_variance) AS pv, SUM(recorded_waste_cost) AS wc, SUM(unexplained_variance) AS uv
  FROM CORE.FACT_INGREDIENT_USAGE_WEEKLY
  WHERE YEAR(week_start) = 2026
  GROUP BY location_id
),
ing AS (          -- each store's biggest unexplained ingredient since March
  SELECT u.location_id, i.ingredient_name,
         SUM(u.actual_qty) / NULLIF(SUM(u.theoretical_qty), 0) - 1 AS over_pct,
         SUM(u.unexplained_variance) AS leak_cost
  FROM CORE.FACT_INGREDIENT_USAGE_WEEKLY u
  JOIN CORE.DIM_INGREDIENT i ON i.ingredient_id = u.ingredient_id
  WHERE u.week_start >= '2026-03-02'
  GROUP BY u.location_id, i.ingredient_name
  QUALIFY ROW_NUMBER() OVER (PARTITION BY u.location_id
                             ORDER BY SUM(u.unexplained_variance) DESC) = 1
),
ing_chain AS (    -- the same ingredient across all stores, for comparison
  SELECT i.ingredient_name,
         SUM(u.actual_qty) / NULLIF(SUM(u.theoretical_qty), 0) - 1 AS chain_over_pct
  FROM CORE.FACT_INGREDIENT_USAGE_WEEKLY u
  JOIN CORE.DIM_INGREDIENT i ON i.ingredient_id = u.ingredient_id
  WHERE u.week_start >= '2026-03-02'
  GROUP BY i.ingredient_name
),
chain AS (
  SELECT SUM(lab.lc) / SUM(lab.s) AS labour_pct,
         SUM(food.ac) / SUM(sales.ns) AS food_pct,
         SUM(food.ac) - SUM(food.tc) AS gap,
         SUM(food.pv) / NULLIF(SUM(food.ac) - SUM(food.tc), 0) AS price_share
  FROM lab JOIN food USING (location_id) JOIN sales USING (location_id)
),
stores AS (
  SELECT 'LOCATION' AS scope, l.location_id, l.location_name,
         lab.lc / lab.s AS labour_pct,
         ld.dow AS worst_day, ld.lp AS worst_day_labour_pct,
         food.ac / sales.ns AS food_cost_pct,
         (food.wc + food.uv) / NULLIF(food.tc + food.pv, 0) AS over_use_pct,
         ing.ingredient_name AS leak_ingredient, ing.over_pct AS leak_over_pct,
         ic.chain_over_pct AS leak_chain_over_pct, ing.leak_cost
  FROM CORE.DIM_LOCATION l
  JOIN lab            ON lab.location_id   = l.location_id
  JOIN lab_day ld     ON ld.location_id    = l.location_id
  JOIN sales          ON sales.location_id = l.location_id
  JOIN food           ON food.location_id  = l.location_id
  JOIN ing            ON ing.location_id   = l.location_id
  JOIN ing_chain ic   ON ic.ingredient_name = ing.ingredient_name
),
pct AS (          -- helper: format a ratio as "42.2%"
  SELECT s.*, c.labour_pct AS chain_labour_pct, c.food_pct AS chain_food_pct,
         c.gap AS chain_gap, c.price_share AS chain_price_share
  FROM stores s CROSS JOIN chain c
)
-- Store rows
SELECT scope, location_id, location_name,
       CASE WHEN worst_day_labour_pct >= 0.38 THEN 'Labour: ' || worst_day || ' schedule'
            WHEN leak_over_pct >= 0.15       THEN 'Food: ' || leak_ingredient || ' usage'
            WHEN over_use_pct  >= 0.03       THEN 'Food: general over-use'
            WHEN labour_pct    >= 0.305      THEN 'Labour: above target'
            ELSE 'On track' END AS headline,
       'Labour ' || TRIM(TO_CHAR(labour_pct * 100, '990.0')) || '% (target 30.0%, chain '
         || TRIM(TO_CHAR(chain_labour_pct * 100, '990.0')) || '%). Worst day: ' || worst_day || ' at '
         || TRIM(TO_CHAR(worst_day_labour_pct * 100, '990.0')) || '%. Food cost '
         || TRIM(TO_CHAR(food_cost_pct * 100, '990.0')) || '% (target 28.5%). Over-use (waste + unexplained) '
         || TRIM(TO_CHAR(over_use_pct * 100, '990.0')) || '% of recipe cost. Biggest unexplained ingredient since March: '
         || leak_ingredient || ', used ' || TRIM(TO_CHAR(leak_over_pct * 100, '990.0')) || '% over recipe vs '
         || TRIM(TO_CHAR(leak_chain_over_pct * 100, '990.0')) || '% chain-wide ($'
         || TRIM(TO_CHAR(leak_cost, '999,990')) || ').' AS kpi_summary
FROM pct
UNION ALL
-- Chain row (location_id 'ALL' so it shows when no store is selected)
SELECT 'CHAIN', 'ALL', 'All locations',
       'Chain summary',
       'Chain labour ' || TRIM(TO_CHAR(MAX(chain_labour_pct) * 100, '990.0')) || '% (target 30.0%). Food cost '
         || TRIM(TO_CHAR(MAX(chain_food_pct) * 100, '990.0')) || '% (target 28.5%). Gap between recipe cost and actual food cost: $'
         || TRIM(TO_CHAR(MAX(chain_gap), '999,999,990')) || ', of which '
         || TRIM(TO_CHAR(MAX(chain_price_share) * 100, '990')) || '% is supplier price. Worst store-day for labour: '
         || MAX_BY(location_name, worst_day_labour_pct) || ' on ' || MAX_BY(worst_day, worst_day_labour_pct) || ' at '
         || TRIM(TO_CHAR(MAX(worst_day_labour_pct) * 100, '990.0')) || '%. Biggest single ingredient leak: '
         || MAX_BY(location_name, leak_over_pct) || ' ' || MAX_BY(leak_ingredient, leak_over_pct) || ', '
         || TRIM(TO_CHAR(MAX(leak_over_pct) * 100, '990.0')) || '% over recipe since March.'
FROM pct;

-- 2. Claude writes the note. >>> If you get "unknown model", see the note at the bottom. <<<
CREATE OR REPLACE TABLE CORE.AI_RECOMMENDATIONS AS
WITH prompts AS (
  SELECT *,
         'You write short weekly notes for restaurant managers at Harbourline Grill, a casual-dining chain. '
      || 'Audience: ' || CASE WHEN scope = 'CHAIN' THEN 'the VP of Operations' ELSE 'the general manager of ' || location_name END || '. '
      || 'Use ONLY the figures below. Do not invent numbers, names or causes; you may say "likely". '
      || 'Write at most 3 short sentences in plain English, no bullet points, no greeting: '
      || 'what stands out, the likely cause, and one specific action for next week.' || CHAR(10)
      || 'Figures (2026 year to date): ' || kpi_summary AS prompt
  FROM CORE.AI_KPI_INPUT
)
SELECT scope, location_id, location_name, headline, kpi_summary, prompt,
       AI_COMPLETE('claude-sonnet-4-5', prompt) AS recommendation_text,
       'claude-sonnet-4-5'                       AS model,
       CURRENT_TIMESTAMP()                       AS generated_at
FROM prompts;

-- 3. Look at what Claude wrote (last statement, so Run All shows it)
SELECT location_name, headline, recommendation_text
FROM CORE.AI_RECOMMENDATIONS
ORDER BY scope, location_name;

-- ---------------------------------------------------------------------
-- "Unknown model" / "not available in your region"?
--   Replace BOTH 'claude-sonnet-4-5' strings in step 2 with one of:
--   'claude-4-sonnet'  or  'claude-3-7-sonnet'  and run step 2 + 3 again.
-- "Unknown function AI_COMPLETE"?  Use SNOWFLAKE.CORTEX.COMPLETE( ... ) instead.
-- ---------------------------------------------------------------------
