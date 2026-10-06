-- =====================================================================
-- 01_setup.sql  |  Harbourline Grill on Snowflake
-- Creates: warehouse (compute), database, 3 schemas, CSV file format, stage.
-- Run once in a Snowsight SQL worksheet (Run All). Safe to re-run.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- Compute: smallest size, pauses after 60 s idle so trial credits last
CREATE WAREHOUSE IF NOT EXISTS HARBOURLINE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Harbourline Grill demo: ETL + Power BI';
USE WAREHOUSE HARBOURLINE_WH;

CREATE DATABASE IF NOT EXISTS HARBOURLINE
  COMMENT = 'Harbourline Grill (synthetic) restaurant operations data';
USE DATABASE HARBOURLINE;

-- Three layers: land it, map it, model it
CREATE SCHEMA IF NOT EXISTS RAW     COMMENT = 'Landing zone: source extracts exactly as received, every column as text';
CREATE SCHEMA IF NOT EXISTS STAGING COMMENT = 'Master-data mappings used to clean RAW (store and role aliases)';
CREATE SCHEMA IF NOT EXISTS CORE    COMMENT = 'Clean, typed star schema that Power BI reads';

-- How to read the CSVs
CREATE OR REPLACE FILE FORMAT RAW.CSV_FF
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('')
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = FALSE      -- keep the messy spaces on purpose; we clean them visibly in SQL
  COMPRESSION = AUTO;     -- handles .csv or .csv.gz

-- Internal stage = a folder inside Snowflake where you upload the raw files
CREATE STAGE IF NOT EXISTS RAW.LANDING
  FILE_FORMAT = RAW.CSV_FF
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Upload the 11 files from the raw/ folder here';

-- Your Power BI "Server" value (note it down). If Power BI can't connect with it,
-- replace any underscores (_) in the account part with hyphens (-).
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() || '.snowflakecomputing.com' AS power_bi_server;
