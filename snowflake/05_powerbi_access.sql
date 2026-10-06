-- =====================================================================
-- 05_powerbi_access.sql  |  Let Power BI read CORE (read-only)
-- Snowflake no longer accepts a plain password for sign-ins like Power BI's,
-- so we create a read-only service user and give it a programmatic access
-- token (PAT). In Power BI you type the user name, and paste the token
-- where it asks for a password.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 1. Read-only role: can use the warehouse and SELECT from CORE, nothing else
CREATE ROLE IF NOT EXISTS BI_READER;
GRANT USAGE  ON WAREHOUSE HARBOURLINE_WH                 TO ROLE BI_READER;
GRANT USAGE  ON DATABASE  HARBOURLINE                    TO ROLE BI_READER;
GRANT USAGE  ON SCHEMA    HARBOURLINE.CORE               TO ROLE BI_READER;
GRANT SELECT ON ALL TABLES    IN SCHEMA HARBOURLINE.CORE TO ROLE BI_READER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HARBOURLINE.CORE TO ROLE BI_READER;

-- 2. Service user for Power BI (no password; token only)
CREATE USER IF NOT EXISTS POWERBI_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = BI_READER
  DEFAULT_WAREHOUSE = HARBOURLINE_WH
  COMMENT = 'Power BI read-only connection';
GRANT ROLE BI_READER TO USER POWERBI_SVC;

-- 3. Authentication policy: this user may ONLY sign in with a token.
--    Snowflake normally also requires an IP allow-list (network policy) for tokens;
--    ENFORCED_NOT_REQUIRED relaxes that so it works from home, the ferry, anywhere.
--    (At a real company you'd restrict it to office / Power BI gateway IPs.)
CREATE AUTHENTICATION POLICY IF NOT EXISTS HARBOURLINE.STAGING.POWERBI_AUTH_POLICY
  AUTHENTICATION_METHODS = ('PROGRAMMATIC_ACCESS_TOKEN')
  PAT_POLICY = (NETWORK_POLICY_EVALUATION = ENFORCED_NOT_REQUIRED)
  COMMENT = 'Token-only sign-in for the Power BI service user';
ALTER USER POWERBI_SVC SET AUTHENTICATION POLICY HARBOURLINE.STAGING.POWERBI_AUTH_POLICY;

-- 4. Create the token.  >>> COPY the token_secret value from the results NOW. <<<
--    Snowflake shows it once. Lost it? Run:
--      ALTER USER POWERBI_SVC REMOVE PROGRAMMATIC ACCESS TOKEN POWERBI_TOKEN;
--    then run this statement again.
ALTER USER POWERBI_SVC ADD PROGRAMMATIC ACCESS TOKEN POWERBI_TOKEN
  ROLE_RESTRICTION = 'BI_READER'
  DAYS_TO_EXPIRY = 30
  COMMENT = 'Power BI Desktop - Harbourline demo';
