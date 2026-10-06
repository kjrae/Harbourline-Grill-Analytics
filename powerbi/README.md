# Power BI dashboard

- `Harbourline_Grill_Dashboard.pbix`: open in **Power BI Desktop** (free, Windows only).
- `Harbourline_Grill_Dashboard.pdf`: the same four pages as a PDF, for anyone without Power BI.
- `theme/HarbourlineGrill_theme_navy.json`: the custom theme (View → Themes → Browse for themes).

**Opening the .pbix:** the data is imported into the file, so every page, slicer, drill-down and Claude note works offline.
**Refresh** needs a Snowflake connection (see `../snowflake/README.md`), so it will fail without your own account; the data already in the file is unaffected.
The map on the Overview page needs internet, and Power BI may ask you to enable map visuals (File → Options → Security).

---

## Pages
| Page | Visuals |
|---|---|
| **Overview** | Net sales card with like-for-like YoY · mini KPIs (covers, average check, labour %, food cost %) · growth by location · monthly sales vs last year · sales by daypart · location map |
| **Labour** | Labour % vs target · labour % by location · location × weekday heatmap · Coquitlam labour hours vs covers by weekday · weekly covers with a 4-week forecast |
| **Food & Menu** | Food cost % vs target · over-use by location · waterfall of the recipe-to-actual gap · decomposition tree (location → ingredient → month) · menu engineering scatter |
| **Recommendations** | Three action cards with annual value, owner and measure · Claude-written note for the selected location |

Navigation buttons, a Reset bookmark, and Location/Year slicers synced across pages.

## Model
Star schema, import mode, single-direction one-to-many relationships:
- `DIM_DATE[CALENDAR_DATE]` → `BUSINESS_DATE` in the sales, covers, labour shift and labour hourly facts, and → `WEEK_START` in `FACT_INGREDIENT_USAGE_WEEKLY` (marked as the date table)
- `DIM_LOCATION`, `DIM_MENU_ITEM`, `DIM_INGREDIENT` → their facts
- `Waterfall Steps`: a 3-row helper table for the waterfall (no relationships)
- `AI_RECOMMENDATIONS`: deliberately **not** related. Its chain-level row (`LOCATION_ID = 'ALL'`) has no match in `DIM_LOCATION`, and a relationship would add a "(Blank)" option to every location slicer, so the measures look the note up with `LOOKUPVALUE` instead.

## Key DAX measures
```DAX
Net Sales = SUM(FACT_SALES_ITEM_DAYPART[NET_SALES])
Covers = SUM(FACT_COVERS_HOURLY[COVERS])
Avg Check = DIVIDE([Net Sales], [Covers])

-- Like-for-like growth: only days that exist in both years
Net Sales LY = CALCULATE([Net Sales], SAMEPERIODLASTYEAR(DIM_DATE[CALENDAR_DATE]))
Net Sales Comparable = SUMX(VALUES(DIM_DATE[CALENDAR_DATE]), IF(NOT ISBLANK([Net Sales LY]), [Net Sales]))
Net Sales YoY % = DIVIDE([Net Sales Comparable] - [Net Sales LY], [Net Sales LY])

-- Labour (hourly table, used for the heatmaps)
HM Labour % = DIVIDE(SUM(FACT_LABOUR_HOURLY[LABOUR_COST]), SUM(FACT_LABOUR_HOURLY[NET_SALES]))

-- Food cost bridge (columns computed in Snowflake; the four parts sum to actual cost)
Theoretical Cost (Std) = SUM(FACT_INGREDIENT_USAGE_WEEKLY[THEORETICAL_COST_AT_STANDARD])
Price Variance         = SUM(FACT_INGREDIENT_USAGE_WEEKLY[PRICE_VARIANCE])
Recorded Waste         = SUM(FACT_INGREDIENT_USAGE_WEEKLY[RECORDED_WASTE_COST])
Unexplained Variance   = SUM(FACT_INGREDIENT_USAGE_WEEKLY[UNEXPLAINED_VARIANCE])
Actual Food Cost       = SUM(FACT_INGREDIENT_USAGE_WEEKLY[ACTUAL_COST])
Food Cost % = DIVIDE([Actual Food Cost], [Net Sales])
Over-use %  = DIVIDE([Recorded Waste] + [Unexplained Variance], [Theoretical Cost (Std)] + [Price Variance])

Waterfall Value = SWITCH(SELECTEDVALUE('Waterfall Steps'[Step]),
    "Supplier price", [Price Variance],
    "Recorded waste", [Recorded Waste],
    "Unexplained",    [Unexplained Variance])

-- Claude note for the selected location (falls back to the chain note)
AI Note =
    VAR locKey = SELECTEDVALUE(DIM_LOCATION[LOCATION_ID], "ALL")
    RETURN LOOKUPVALUE(AI_RECOMMENDATIONS[RECOMMENDATION_TEXT], AI_RECOMMENDATIONS[LOCATION_ID], locKey)
```
Status text, colours and the dynamic insight sentences are also measures, so cards and titles update with the slicers.
