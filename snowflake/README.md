# Snowflake pipeline: setup guide

**Time:** about 1–1.5 hours the first time. **Cost:** a free Snowflake trial is enough for scripts 01–05 and 06b.
**Result:** raw messy files → cleaned in Snowflake with SQL → Power BI reads the clean tables.

```
data/raw/*.csv ──upload──▶ RAW (text, as received) ──03_transform──▶ CORE (clean star schema) ──▶ Power BI
                               │                        ▲
                               └── STAGING (store/role mapping tables)
                                                04_data_quality ──▶ CORE.DQ_RESULTS (PASS / FIXED / FAIL log)
                                                06 / 06b ─────────▶ CORE.AI_RECOMMENDATIONS (Claude notes)
```

The scripts were tested against the generated files: the cleaned output matches `data/clean/` row for row, and all 24 data-quality checks pass. Every script is safe to re-run.

---

## 1. Create a trial account
1. Sign up at **signup.snowflake.com**. Choose **Enterprise** edition and **AWS**; any nearby region works.
2. Activate from the email and set up MFA when asked.
3. In **Snowsight**, open **Projects → Workspaces** and create a SQL file. Use **Run All** for each script.

## 2. Run `01_setup.sql`
Creates the warehouse `HARBOURLINE_WH` (XS, pauses after 60 s idle), database `HARBOURLINE`, schemas `RAW` / `STAGING` / `CORE`, a CSV file format and an internal stage. The last result is your **Power BI server name**.

## 3. Upload the 11 raw files
Generate them first with `python data/generate.py`. Then **Ingestion → Add Data → Load files into a Stage** → database `HARBOURLINE`, schema `RAW`, stage `LANDING`, and drag in everything from `data/raw/`.

## 4. Run `02_load_raw.sql`
Loads every column as text, so a bad value can never fail the load, and records each row's source file and load time. The final result should say **OK** for all 11 tables.

## 5. Run `03_transform.sql`
The ETL: maps store and role name variants, standardises dates, removes duplicates on each table's grain, rebuilds missing sales, fills missed clock-outs (flagged), converts lb to kg, and builds the food-cost and menu-engineering tables. `FACT_SALES_ITEM_DAYPART` should have **552,537** rows.

## 6. Run `04_data_quality.sql`
Writes 24 checks to `CORE.DQ_RESULTS`: 15 **PASS** and 9 **FIXED** (with counts of what was repaired). Nothing should say **FAIL**. Also runs a monthly reconciliation of source vs clean sales.

## 7. Run `05_powerbi_access.sql`
Creates a read-only role (`BI_READER`) and a service user (`POWERBI_SVC`) that can only sign in with a programmatic access token. **Copy the `token_secret` from the result immediately**: Snowflake shows it once. Never commit it anywhere.

## 8. Claude notes: `06` or `06b`
- **Paid account:** run `06_ai_recommendations.sql`. Cortex calls Claude with `AI_COMPLETE` once per store and stores each note with its prompt, model and timestamp. If Claude isn't offered in your region, first run
  `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';` as ACCOUNTADMIN.
- **Trial account:** Cortex AI functions are blocked on trials, so run `06b_ai_recommendations_trial.sql`. Snowflake still computes the numbers and builds the prompts; the notes were generated from those prompts outside Snowflake and are loaded as data, labelled in the `MODEL` column.

## 9. Connect Power BI
1. **Get Data → Snowflake.** Server: the value from step 2. Warehouse: `HARBOURLINE_WH`. Role (advanced options): `BI_READER`. Mode: **Import**.
2. Credentials: the **Snowflake** tab, user `POWERBI_SVC`, and paste the token as the password.
3. Navigator → `HARBOURLINE` → `CORE`, tick the DIM_, FACT_, MENU_ENGINEERING_2025, DQ_RESULTS and AI_RECOMMENDATIONS tables, and **Load**.

---

## Troubleshooting
| Problem | Fix |
|---|---|
| 02 shows CHECK UPLOAD | A file didn't upload, or uploaded twice. Run `LIST @RAW.LANDING;`, fix it, and re-run 02. |
| "Object does not exist" | Re-run the earlier scripts in order. |
| Power BI can't find the server | Replace `_` with `-` in the account part of the server name; don't include `https://`. |
| Power BI rejects the credentials | Use the Snowflake tab, user `POWERBI_SVC`, the token as password, role `BI_READER`. Tokens expire after 30 days. |
| Token lost | `ALTER USER POWERBI_SVC REMOVE PROGRAMMATIC ACCESS TOKEN POWERBI_TOKEN;` then re-run the last statement of 05. |
| "AI function … not available for trial accounts" | Expected on a trial. Use `06b_ai_recommendations_trial.sql`. |
| Worried about credits | The XS warehouse uses about 1 credit per hour while running and pauses after 60 seconds. The whole build uses a small fraction of the trial balance. |
