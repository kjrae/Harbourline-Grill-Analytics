-- =====================================================================
-- 06b_ai_recommendations_trial.sql  |  Trial-account version of script 06
-- Snowflake trial accounts can't call Cortex AI, so for this demo:
--   * Snowflake still computes every number and builds the exact prompts (step 1)
--   * the prompts were run through Claude outside Snowflake, and the answers are
--     loaded here (step 2), labelled honestly in the MODEL column
-- On a paid account, script 06 does step 2 live with AI_COMPLETE instead.
-- Run All.
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

-- 2. Store Claude's notes next to the prompts that produced them
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
),
notes (location_id, recommendation_text) AS (
  SELECT * FROM VALUES
  ('ALL', 'Chain labour is on target at 29.8% and food cost is just over at 28.6%, but the averages hide two specific problems. Coquitlam Centre''s Mondays run 42.2% labour, the worst store-day in the chain, and Guildford has used 28.0% more tomato than the recipes call for since March. Ask both GMs to act on these this week, and take the $683K recipe-to-actual gap to purchasing, since 55% of it is supplier price.'),
  ('L09', 'Labour is running at 32.1%, above the 30.0% target and the chain''s 29.8%, with Tuesdays the worst day at 35.4%. Food is under control: cost is 28.3% against a 28.5% target and over-use is only 1.2% of recipe cost. Next week, check Tuesday''s schedule against sales and trim the hours that aren''t needed.'),
  ('L06', 'Mondays stand out: labour runs 42.2% of sales, far above the 30.0% target, while the store overall sits at 31.2%. The likely cause is a Monday schedule that doesn''t match Monday''s sales. Rebuild next Monday''s schedule from expected covers and send staff home early when it''s quiet.'),
  ('L01', 'Downtown Robson is on track, with labour at 28.2% and food cost at 28.2%, both under target. Over-use is just 1.0% of recipe cost, and Mixed Greens, the largest unexplained item, is below the chain rate (8.3% vs 9.5%). No change needed; keep an eye on Mondays, the weakest labour day at 30.1%.'),
  ('L05', 'Tomato is the issue: since March it has been used 28.0% over recipe, against 7.7% across the chain, adding $6,140 of unexplained cost. The likely cause is over-portioning or waste that isn''t being logged. This week, check tomato portions against the spec sheet and log every discarded tomato.'),
  ('L02', 'Kitsilano is on track, with labour at 28.8% against a 30.0% target and food cost right on target at 28.5%. Over-use is 1.8% of recipe cost, and Craft Beer (keg), the largest unexplained item, is in line with the chain at 2.6%. Keep an eye on Tuesdays, the weakest labour day at 30.5%.'),
  ('L07', 'Labour is slightly above target at 31.0%, with Mondays the weakest day at 33.3%, and food cost is 28.8% against 28.5%. Over-use is 2.8% of recipe cost, and Beef Patty (6oz) is running 1.7% over recipe vs 0.9% chain-wide. Next week, tighten the Monday schedule and spot-check beef patty counts at close.'),
  ('L03', 'Metrotown is on track, with labour at 28.4% and food cost at 28.5%, both at or under target. Over-use is 1.8% of recipe cost, and Avocado, the largest unexplained item, is in line with the chain (7.5% vs 7.6%). No change needed; even Mondays, the weakest day, are right at 30.0%.'),
  ('L04', 'Richmond Centre is on track, with labour at 29.0% and food cost at 28.4%, both under target. Mixed Greens is the largest unexplained item at 9.7% over recipe, in line with the chain''s 9.5%. Keep current routines and watch Tuesdays, the weakest labour day at 30.3%.'),
  ('L10', 'Food cost is the concern: 29.2% against a 28.5% target, with waste plus unexplained usage at 4.4% of recipe cost. Beef Patty (6oz) is the largest unexplained item, running 3.0% over recipe vs 0.9% chain-wide, which likely points to loose counting or portioning. Start daily beef patty counts next week, and review Mondays, the weakest labour day at 34.2%.'),
  ('L08', 'Labour is above target at 31.2%, driven by Mondays at 34.0%, while food cost is under target at 28.4%. Over-use is modest at 1.8% of recipe cost. Next week, review the Monday schedule against sales and cut hours where it''s quiet.')
)
SELECT p.scope, p.location_id, p.location_name, p.headline, p.kpi_summary, p.prompt,
       n.recommendation_text,
       'Claude (run outside Snowflake: Cortex is blocked on trial accounts)' AS model,
       CURRENT_TIMESTAMP() AS generated_at
FROM prompts p
JOIN notes n ON n.location_id = p.location_id;

-- 3. Check: 11 rows
SELECT location_name, headline, recommendation_text
FROM CORE.AI_RECOMMENDATIONS
ORDER BY scope, location_name;
