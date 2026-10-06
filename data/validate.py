import pandas as pd, numpy as np, os
HERE=os.path.dirname(os.path.abspath(__file__))
C=os.path.join(HERE,"clean")+"/"; r=lambda n,**k: pd.read_csv(C+n+".csv",**k)
loc=r("dim_location"); dd=r("dim_date",parse_dates=["date"]); menu=r("dim_menu_item"); ing=r("dim_ingredient")
emp=r("dim_employee",parse_dates=["hire_date"]); rec=r("bridge_recipe"); wx=r("dim_weather_daily",parse_dates=["date"])
s=r("fact_sales_item_daypart",parse_dates=["business_date"]); cv=r("fact_covers_hourly",parse_dates=["business_date"])
sh=r("fact_labour_shifts",parse_dates=["business_date","scheduled_start","scheduled_end","actual_start","actual_end"])
lh=r("fact_labour_hourly",parse_dates=["business_date"]); pu=r("fact_purchases",parse_dates=["delivery_date"])
ct=r("fact_inventory_counts",parse_dates=["count_date"]); wa=r("fact_waste_log",parse_dates=["waste_date"])
pr=r("fact_ingredient_price_weekly",parse_dates=["week_start"]); us=r("fact_ingredient_usage_weekly",parse_dates=["week_start"])
tg=r("fact_targets_monthly")
P=[];F=[]
def chk(name,ok,detail=""): (P if ok else F).append(f"{'PASS' if ok else 'FAIL'}  {name} {detail}")
D=set(dd.date)
# keys unique
for n,df,k in [("dim_location",loc,["location_id"]),("dim_date",dd,["date"]),("dim_menu_item",menu,["menu_item_id"]),("dim_ingredient",ing,["ingredient_id"]),
  ("dim_employee",emp,["employee_id"]),("bridge_recipe",rec,["menu_item_id","ingredient_id"]),("sales grain",s,["business_date","location_id","daypart","menu_item_id"]),
  ("covers grain",cv,["business_date","location_id","hour_of_day"]),("shift_id",sh,["shift_id"]),("labour hourly grain",lh,["business_date","location_id","hour_of_day"]),
  ("price grain",pr,["week_start","ingredient_id"]),("usage grain",us,["week_start","location_id","ingredient_id"]),("count grain",ct,["count_date","location_id","ingredient_id"]),
  ("targets grain",tg,["year_month","location_id"]),("po_line_id",pu,["po_line_id"])]:
    chk(f"unique key {n}", not df.duplicated(k).any())
# referential integrity
for n,df,col,ref in [("sales loc",s,"location_id",set(loc.location_id)),("sales item",s,"menu_item_id",set(menu.menu_item_id)),
  ("recipe item",rec,"menu_item_id",set(menu.menu_item_id)),("recipe ing",rec,"ingredient_id",set(ing.ingredient_id)),
  ("shift emp",sh,"employee_id",set(emp.employee_id)),("purch ing",pu,"ingredient_id",set(ing.ingredient_id)),
  ("sales date",s,"business_date",D),("covers date",cv,"business_date",D),("shift date",sh,"business_date",D),("lab hr date",lh,"business_date",D),
  ("purch date",pu,"delivery_date",D),("count date",ct,"count_date",D),("waste date",wa,"waste_date",D),("price wk",pr,"week_start",D),("usage wk",us,"week_start",D),("weather date",wx,"date",D)]:
    miss=(~df[col].isin(ref)).sum(); chk(f"FK {n}", miss==0, f"({miss} orphans)")
chk("every main/non-main item has a recipe", set(menu.menu_item_id)==set(rec.menu_item_id))
chk("recipe units match ingredient units",(rec.merge(ing,on="ingredient_id").pipe(lambda t:(t.unit_x==t.unit_y).all())))
# numeric sanity
chk("no negative sales/qty",(s[["qty_sold","gross_sales","discounts","comps","net_sales"]]>=0).all().all())
chk("net = gross - disc - comps",np.allclose(s.gross_sales-s.discounts-s.comps,s.net_sales,atol=0.011))
chk("gross = qty*price",np.allclose(s.qty_sold*s.unit_price,s.gross_sales,atol=0.011))
s["pc"]=np.where(s.business_date>="2026-01-05","price_2026","price_2025")
pm=s.merge(menu,on="menu_item_id"); chk("unit price matches menu price for date",np.allclose(pm.unit_price,np.where(pm.pc=="price_2026",pm.price_2026,pm.price_2025)))
# reconciliation hourly vs item sales
a=s.groupby(["business_date","location_id","daypart"]).net_sales.sum(); b=cv.groupby(["business_date","location_id","daypart"]).net_sales.sum()
j=pd.concat([a,b],axis=1,keys=["item","hourly"]).fillna(0); chk("hourly sales reconcile to item sales (daypart)",(abs(j.item-j.hourly)<0.2).all(),f"max diff {abs(j.item-j.hourly).max():.2f}")
chk("covers>0 wherever sales>0",((cv.net_sales>0)<= (cv.covers>0)).all())
# closed Christmas
chk("no sales on Dec 25",(s.business_date.dt.strftime("%m-%d")!="12-25").all())
# labour
chk("shift end > start",(sh.actual_end>sh.actual_start).all() and (sh.scheduled_end>sh.scheduled_start).all())
chk("actual hours 3-10",sh.actual_hours.between(3,10).all(),f"min {sh.actual_hours.min()} max {sh.actual_hours.max()}")
chk("labour_cost = hours*wage",np.allclose(sh.actual_hours*sh.hourly_wage,sh.labour_cost,atol=.011))
chk("labour hourly total = shifts total",abs(lh.labour_cost.sum()-sh.labour_cost.sum())/sh.labour_cost.sum()<1e-4,f"{lh.labour_cost.sum():.0f} vs {sh.labour_cost.sum():.0f}")
chk("hourly covers in labour table = covers table",lh.covers.sum()==cv.covers.sum(),f"{lh.covers.sum()} vs {cv.covers.sum()}")
e=sh.merge(emp,on="employee_id")
chk("shift role = employee role",(e.role_x==e.role_y).all()); chk("shift at employee home store",(e.location_id==e.home_location_id).all())
chk("employee hired before shifts",(e.hire_date<=e.business_date).all(),f"({(e.hire_date>e.business_date).sum()} violations)")
dbl=sh.groupby(["employee_id","business_date"]).size(); chk("no employee double-booked same day",(dbl==1).all(),f"({(dbl>1).sum()} emp-days)")
wk=sh.assign(w=sh.business_date-pd.to_timedelta(sh.business_date.dt.dayofweek,unit="D")).groupby(["employee_id","w"]).actual_hours.sum()
chk("weekly hours per employee <= 48",wk.max()<=48,f"(mean {wk.mean():.1f}, p95 {wk.quantile(.95):.1f}, max {wk.max():.1f})")
chk("wage >= BC minimum $17.85",emp.hourly_wage.min()>=17.85,f"(min {emp.hourly_wage.min()})")
chk("every open day/location has a manager AM and PM",sh[sh.role=="Manager"].groupby(["business_date","location_id"]).size().min()>=2)
# inventory identity
ct_p=ct.pivot_table(index=["location_id","ingredient_id"],columns="count_date",values="qty_on_hand")
pu["week_start"]=pu.delivery_date-pd.to_timedelta(pu.delivery_date.dt.dayofweek,unit="D")
pw=pu.groupby(["week_start","location_id","ingredient_id"]).qty_received.sum()
u2=us.set_index(["week_start","location_id","ingredient_id"])
ctx=ct.set_index(["count_date","location_id","ingredient_id"]).qty_on_hand
beg=[ctx.get((w-pd.Timedelta(days=1),l,i),np.nan) for w,l,i in u2.index]; end=[ctx.get((w+pd.Timedelta(days=6),l,i),np.nan) for w,l,i in u2.index]
calc=np.array(beg)+pw.reindex(u2.index).fillna(0).values-np.array(end)
err=np.abs(calc-u2.actual_qty.values); chk("actual usage = open + purchases - close",np.nanmax(err)<0.02,f"(max err {np.nanmax(err):.4f}, nan {np.isnan(err).sum()})")
chk("no negative inventory",(ct.qty_on_hand>=0).all()); chk("no negative purchases",(pu.qty_received>0).all())
# theoretical usage re-derived from sales x recipe
s["week_start"]=s.business_date-pd.to_timedelta(s.business_date.dt.dayofweek,unit="D")
t=s.groupby(["week_start","location_id","menu_item_id"]).qty_sold.sum().reset_index().merge(rec,on="menu_item_id")
t=(t.qty_sold*t.qty_per_item).groupby([t.week_start,t.location_id,t.ingredient_id]).sum()
chk("theoretical usage = sales x recipe",np.allclose(t.reindex(u2.index).values,u2.theoretical_qty.values,atol=.01))
chk("weekly price covers every week x ingredient",len(pr)==pr.week_start.nunique()*len(ing))
# planted stories
x=lh.merge(dd[["date","dow_num"]],left_on="business_date",right_on="date")
g=x.groupby(["location_id","dow_num"]).apply(lambda q:q.labour_cost.sum()/q.net_sales.sum(),include_groups=False)
chk("STORY L06 Monday labour stands out",g["L06",1]>g.drop(("L06",1)).max()+0.05,f"(L06 Mon {g['L06',1]:.3f}, next highest {g.drop(('L06',1)).max():.3f})")
tm=us[(us.ingredient_id=="I13")&(us.week_start>="2026-03-02")].groupby("location_id")[["actual_qty","theoretical_qty"]].sum()
v=tm.actual_qty/tm.theoretical_qty-1; chk("STORY L05 tomato variance",v["L05"]>v.drop("L05").max()+.15,f"(L05 {v['L05']:.3f}, others {v.drop('L05').min():.3f}-{v.drop('L05').max():.3f})")
pre=us[(us.ingredient_id=="I13")&(us.location_id=="L05")&(us.week_start<"2026-03-02")]; chk("STORY L05 tomato normal before Mar-2026",abs(pre.actual_qty.sum()/pre.theoretical_qty.sum()-1.055)<.03)
tp=pr[pr.ingredient_id=="I13"].assign(m=lambda q:q.week_start.dt.strftime("%Y-%m")).groupby("m").market_unit_cost.mean()
chk("STORY tomato Feb spike YoY",tp["2026-02"]/tp["2025-02"]>1.4,f"({tp['2025-02']:.2f} -> {tp['2026-02']:.2f})")
chk("tomato used in N items",True,f"(N={rec[rec.ingredient_id=='I13'].menu_item_id.nunique()})")
fc=(us.merge(pr,on=["week_start","ingredient_id"]).assign(c=lambda q:q.actual_qty*q.market_unit_cost).c.sum())/s.net_sales.sum()
chk("overall food cost % realistic (26-32%)",.26<fc<.32,f"({fc:.3f})")
lp=sh.labour_cost.sum()/s.net_sales.sum(); chk("overall labour % realistic (27-34%)",.27<lp<.34,f"({lp:.3f})")
# seasonality / weekday
mcov=cv.groupby(cv.business_date.dt.month).covers.sum()/cv.groupby(cv.business_date.dt.month).business_date.nunique()
chk("summer busier than Jan",mcov[7]>mcov[1]*1.15)
dc=cv.merge(dd,left_on="business_date",right_on="date").groupby("dow_num").covers.sum(); chk("Sat busiest, Mon slowest",dc.idxmax()==6 and dc.idxmin()==1)
rw=cv.merge(wx,left_on="business_date",right_on="date").groupby(["is_rainy_day"]).covers.mean(); chk("rainy days lower covers",rw[1]<rw[0])
# raw checks
R=os.path.join(HERE,"raw")+"/"; rp=pd.read_csv(R+"pos_sales_extract.csv"); chk("raw POS has duplicates",rp.duplicated().sum()>0,f"({rp.duplicated().sum()})")
chk("raw POS messy dates",rp.business_date.str.contains("[A-Za-z]").mean()>.03,f"({rp.business_date.str.contains('[A-Za-z]').mean():.3f})")
chk("raw POS null net_sales",rp.net_sales.isna().sum()>0,f"({rp.net_sales.isna().sum()})")
chk("raw POS store variants",rp.store.nunique()>10,f"({rp.store.nunique()} distinct)")
rpu=pd.read_csv(R+"purchasing_extract.csv"); chk("raw purchases lb lines",(rpu.unit=="lb").sum()>0,f"({(rpu.unit=='lb').sum()})")
rt=pd.read_csv(R+"timeclock_extract.csv"); chk("raw timeclock missing clock-out",rt.actual_end.isna().sum()>0,f"({rt.actual_end.isna().sum()})")
# raw cleanable back to clean totals
rp2=rp.drop_duplicates(); chk("raw POS dedup recovers clean row count",len(rp2)==len(s),f"({len(rp2)} vs {len(s)})")
print("\n".join(F+P)); print(f"\n{len(P)} passed, {len(F)} failed")
