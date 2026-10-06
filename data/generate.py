"""
Harbourline Grill - synthetic multi-location casual dining dataset.
Generates a clean star schema (clean/) and messy source extracts (raw/) for an ETL demo.
"""
import numpy as np, pandas as pd, os, math
rng = np.random.default_rng(29)
OUT = os.path.dirname(os.path.abspath(__file__))   # writes data/clean/ and data/raw/ next to this script
os.makedirs(f"{OUT}/clean", exist_ok=True); os.makedirs(f"{OUT}/raw", exist_ok=True)

START, END = pd.Timestamp("2025-01-06"), pd.Timestamp("2026-08-30")   # full Mon-Sun weeks
dates = pd.date_range(START, END, freq="D")
HOURS = list(range(7, 23))  # 7:00 .. 22:00 (close 23:00)

# ---------------- dim_location ----------------
loc = pd.DataFrame([
 ["L01","Downtown Robson","Vancouver",49.2846,-123.1250,180,1,1050,"2009-05-01"],
 ["L02","Kitsilano","Vancouver",49.2685,-123.1570,150,1,900,"2012-03-15"],
 ["L03","Metrotown","Burnaby",49.2276,-123.0000,170,0,980,"2011-08-01"],
 ["L04","Richmond Centre","Richmond",49.1666,-123.1360,160,0,880,"2014-06-01"],
 ["L05","Guildford","Surrey",49.1897,-122.8030,165,0,860,"2015-04-20"],
 ["L06","Coquitlam Centre","Coquitlam",49.2780,-122.8000,150,0,760,"2016-09-01"],
 ["L07","Lonsdale","North Vancouver",49.3200,-123.0720,130,1,720,"2017-05-10"],
 ["L08","Willowbrook","Langley",49.1040,-122.6600,140,0,700,"2018-02-01"],
 ["L09","Columbia Square","New Westminster",49.2010,-122.9120,120,0,640,"2019-07-01"],
 ["L10","Sevenoaks","Abbotsford",49.0500,-122.3000,140,0,690,"2020-10-15"],
], columns=["location_id","location_name","city","latitude","longitude","seats","has_patio","base_daily_covers","open_date"])
loc["region"] = np.where(loc.city.isin(["Vancouver","North Vancouver"]),"Vancouver & North Shore",
                 np.where(loc.city.isin(["Burnaby","New Westminster","Coquitlam"]),"Burnaby & Tri-Cities","South Fraser & Richmond"))
loc["area_manager"] = loc.region.map({"Vancouver & North Shore":"A. Chen","Burnaby & Tri-Cities":"M. Singh","South Fraser & Richmond":"R. Dubois"})

# ---------------- dim_date ----------------
hol = {"2025-01-01":"New Year's Day","2025-02-17":"Family Day","2025-04-18":"Good Friday","2025-05-19":"Victoria Day",
 "2025-07-01":"Canada Day","2025-08-04":"B.C. Day","2025-09-01":"Labour Day","2025-09-30":"Truth and Reconciliation Day",
 "2025-10-13":"Thanksgiving","2025-11-11":"Remembrance Day","2025-12-25":"Christmas Day",
 "2026-01-01":"New Year's Day","2026-02-16":"Family Day","2026-04-03":"Good Friday","2026-05-18":"Victoria Day",
 "2026-07-01":"Canada Day","2026-08-03":"B.C. Day"}
dd = pd.DataFrame({"date": pd.date_range(START-pd.Timedelta(days=1), END, freq="D")})
dd["year"]=dd.date.dt.year; dd["quarter"]="Q"+dd.date.dt.quarter.astype(str); dd["month_num"]=dd.date.dt.month
dd["month_name"]=dd.date.dt.strftime("%b"); dd["year_month"]=dd.date.dt.strftime("%Y-%m")
dd["day_of_week"]=dd.date.dt.strftime("%a"); dd["dow_num"]=dd.date.dt.dayofweek+1
dd["is_weekend"]=(dd.dow_num>=6).astype(int)
dd["week_start"]=dd.date-pd.to_timedelta(dd.date.dt.dayofweek,unit="D")
dd["iso_week"]=dd.date.dt.isocalendar().week.astype(int)
dd["holiday_name"]=dd.date.dt.strftime("%Y-%m-%d").map(hol).fillna("")
dd["is_stat_holiday"]=(dd.holiday_name!="").astype(int)
dd["season"]=dd.month_num.map({12:"Winter",1:"Winter",2:"Winter",3:"Spring",4:"Spring",5:"Spring",6:"Summer",7:"Summer",8:"Summer",9:"Fall",10:"Fall",11:"Fall"})

# ---------------- weather (synthetic, regional) ----------------
rainp=[.62,.55,.55,.45,.35,.30,.15,.17,.30,.50,.68,.65]; tmax=[7,8,11,14,18,21,24,24,20,14,9,6]
m=dd.month_num.values-1
rain = rng.random(len(dd)) < np.array(rainp)[m]
precip = np.where(rain, np.round(rng.gamma(1.6,5.5,len(dd)),1), 0.0)
temp = np.round(np.array(tmax)[m] + rng.normal(0,2.5,len(dd)),1)
weather = pd.DataFrame({"date":dd.date,"region":"Lower Mainland","max_temp_c":temp,"precip_mm":precip,
                        "is_rainy_day":(precip>=2).astype(int),"source":"SYNTHETIC - replace with Environment Canada daily data"})

# ---------------- dim_menu_item ----------------
# id, name, category, price_2025, is_main
menu = pd.DataFrame([
 ["M01","Harbour Classic Burger","Burgers",16.49,1],["M02","Bacon Cheddar Burger","Burgers",18.49,1],
 ["M03","Mushroom Swiss Burger","Burgers",17.99,1],["M04","Crispy Chicken Burger","Burgers",17.49,1],
 ["M05","Garden Veggie Burger","Burgers",16.99,1],
 ["M06","Fish & Chips","Mains",21.99,1],["M07","Chicken Tenders & Fries","Mains",18.49,1],
 ["M08","Sirloin Steak Frites","Mains",32.99,1],["M09","Pasta Primavera","Mains",18.99,1],
 ["M10","Salmon Rice Bowl","Bowls & Salads",23.99,1],["M11","Chicken Caesar Salad","Bowls & Salads",18.99,1],
 ["M12","Harvest Grain Bowl","Bowls & Salads",19.99,1],["M13","Clubhouse Sandwich","Sandwiches",17.99,1],
 ["M14","Veggie Hummus Wrap","Sandwiches",14.99,1],
 ["M15","Classic Breakfast","Breakfast",16.99,1],["M16","Eggs Benedict","Breakfast",19.49,1],
 ["M17","Buttermilk Pancake Stack","Breakfast",14.99,1],["M18","Sunrise Breakfast Burger","Breakfast",17.49,1],
 ["M19","Smashed Avocado Toast","Breakfast",15.49,1],
 ["M20","Side Fries","Sides",5.99,0],["M21","Onion Rings","Sides",7.49,0],["M22","Side Garden Salad","Sides",6.49,0],
 ["M23","Brownie Sundae","Desserts",9.49,0],["M24","Apple Crumble","Desserts",8.99,0],
 ["M25","Drip Coffee","Beverages",3.49,0],["M26","Fountain Soft Drink","Beverages",3.79,0],
 ["M27","Milkshake","Beverages",7.99,0],["M28","Local Craft Beer (pint)","Beverages",8.49,0],
 ["M29","House Wine (6oz)","Beverages",10.99,0],
], columns=["menu_item_id","menu_item_name","category","price_2025","is_main"])
menu["price_2026"] = np.round(menu.price_2025*1.04 - 0.005, 2)   # 4% menu price increase effective 2026-01-05
menu["price_change_date"]="2026-01-05"

DAYPARTS = {"Breakfast":[7,8,9,10],"Lunch":[11,12,13,14],"Afternoon":[15,16],"Dinner":[17,18,19,20],"Late Night":[21,22]}
main_w = {
 "Breakfast":{"M15":.34,"M16":.24,"M17":.19,"M18":.14,"M19":.09},
 "Lunch":{"M01":.18,"M02":.09,"M03":.05,"M04":.08,"M05":.03,"M06":.07,"M07":.06,"M08":.015,"M09":.025,
          "M10":.025,"M11":.08,"M12":.04,"M13":.10,"M14":.02,"M15":.06,"M18":.035},
 "Afternoon":{"M01":.24,"M02":.12,"M03":.06,"M04":.12,"M05":.03,"M06":.08,"M07":.14,"M11":.07,"M13":.08,"M14":.02,"M09":.02,"M10":.02},
 "Dinner":{"M01":.17,"M02":.10,"M03":.06,"M04":.08,"M05":.025,"M06":.10,"M07":.07,"M08":.05,"M09":.03,
           "M10":.035,"M11":.07,"M12":.04,"M13":.06,"M14":.015},
 "Late Night":{"M01":.28,"M02":.16,"M04":.12,"M06":.10,"M07":.20,"M03":.06,"M05":.02,"M11":.03,"M14":.01},
}
addon_p = {
 "Breakfast":{"M25":.62,"M26":.08,"M27":.03,"M20":.03},
 "Lunch":{"M26":.36,"M25":.10,"M27":.08,"M28":.07,"M29":.03,"M20":.08,"M21":.09,"M22":.07,"M23":.04,"M24":.03},
 "Afternoon":{"M26":.34,"M27":.16,"M28":.10,"M25":.10,"M21":.11,"M20":.07,"M23":.07,"M24":.04},
 "Dinner":{"M26":.30,"M28":.21,"M29":.12,"M27":.06,"M25":.05,"M21":.12,"M22":.08,"M20":.05,"M23":.10,"M24":.07},
 "Late Night":{"M28":.32,"M29":.12,"M26":.24,"M27":.08,"M21":.15,"M20":.08,"M23":.08},
}

# ---------------- dim_ingredient + recipes ----------------
# id, name, category, unit, std_cost_2025, waste_rate, is_produce
ing = pd.DataFrame([
 ["I01","Beef Patty (6oz)","Protein","each",2.10,.015,0],["I02","Chicken Breast","Protein","kg",13.50,.02,0],
 ["I03","Chicken Tenders","Protein","kg",11.00,.02,0],["I04","Cod Fillet","Protein","kg",22.00,.03,0],
 ["I05","Salmon Fillet","Protein","kg",26.00,.03,0],["I06","Sirloin Steak","Protein","kg",38.00,.02,0],
 ["I07","Bacon","Protein","kg",14.00,.02,0],["I08","Eggs","Dairy & Eggs","each",0.38,.02,0],
 ["I09","Veggie Patty","Protein","each",2.40,.02,0],["I10","Burger Bun","Bakery","each",0.55,.03,0],
 ["I11","Sandwich Bread (slice)","Bakery","each",0.18,.03,0],["I12","Tortilla Wrap","Bakery","each",0.45,.02,0],
 ["I13","Tomato","Produce","kg",3.40,.06,1],["I14","Iceberg Lettuce","Produce","kg",3.20,.08,1],
 ["I15","Onion","Produce","kg",1.80,.04,1],["I16","Mushrooms","Produce","kg",7.50,.07,1],
 ["I17","Avocado","Produce","each",1.60,.08,1],["I18","Romaine","Produce","kg",4.00,.08,1],
 ["I19","Mixed Greens","Produce","kg",9.00,.10,1],["I20","Cheddar Cheese","Dairy & Eggs","kg",12.00,.02,0],
 ["I21","Swiss Cheese","Dairy & Eggs","kg",15.00,.02,0],["I22","Fries (frozen)","Frozen","kg",2.40,.02,0],
 ["I23","Onion Rings (frozen)","Frozen","kg",5.50,.02,0],["I24","Pasta","Dry Goods","kg",3.20,.01,0],
 ["I25","Rice","Dry Goods","kg",2.60,.01,0],["I26","Grain Mix (quinoa/farro)","Dry Goods","kg",6.00,.01,0],
 ["I27","Hollandaise","Sauces","L",9.00,.05,0],["I28","Pancake Batter Mix","Dry Goods","kg",3.50,.02,0],
 ["I29","Maple Syrup","Sauces","L",18.00,.02,0],["I30","Coffee Beans","Beverage","kg",24.00,.02,0],
 ["I31","Soft Drink Syrup","Beverage","L",9.00,.01,0],["I32","Ice Cream","Frozen","L",7.00,.03,0],
 ["I33","Brownie","Bakery","each",1.10,.03,0],["I34","Apple Crumble Portion","Bakery","each",1.30,.03,0],
 ["I35","Milk","Dairy & Eggs","L",1.90,.03,0],["I36","Craft Beer (keg)","Beverage","L",5.50,.03,0],
 ["I37","House Wine","Beverage","L",11.00,.03,0],["I38","Burger Sauce","Sauces","L",6.00,.03,0],
 ["I39","Fryer Oil","Dry Goods","L",3.20,.00,0],["I40","Caesar Dressing","Sauces","L",8.00,.03,0],
 ["I41","Hummus","Sauces","kg",8.50,.04,0],["I42","Potatoes (hash)","Produce","kg",1.60,.04,1],
 ["I43","Parmesan","Dairy & Eggs","kg",22.00,.02,0],["I44","Cream","Dairy & Eggs","L",5.00,.03,0],
], columns=["ingredient_id","ingredient_name","ingredient_category","unit","std_cost_2025","expected_waste_rate","is_produce"])
ing["std_cost_2025"]=(ing.std_cost_2025*1.36).round(3)   # landed cost incl. freight/packaging
ing["std_cost_2026"] = np.round(ing.std_cost_2025*np.where(ing.ingredient_id=="I01",1.05,1.03),3)
ing["supplier"] = ing.ingredient_category.map({"Protein":"Pacific Protein Co.","Produce":"Fraser Valley Fresh","Dairy & Eggs":"Coastal Dairy",
  "Bakery":"Northshore Bakery","Frozen":"Sysco-style Broadline","Dry Goods":"Sysco-style Broadline","Sauces":"Sysco-style Broadline","Beverage":"Westcoast Beverage"})

R = [ # menu_item, ingredient, qty
 ("M01","I01",1),("M01","I10",1),("M01","I13",.035),("M01","I14",.02),("M01","I15",.02),("M01","I20",.025),("M01","I38",.02),("M01","I22",.20),("M01","I39",.03),
 ("M02","I01",1),("M02","I10",1),("M02","I13",.035),("M02","I14",.02),("M02","I07",.04),("M02","I20",.035),("M02","I38",.02),("M02","I22",.20),("M02","I39",.03),
 ("M03","I01",1),("M03","I10",1),("M03","I13",.035),("M03","I16",.06),("M03","I21",.03),("M03","I15",.02),("M03","I22",.20),("M03","I39",.03),
 ("M04","I02",.16),("M04","I10",1),("M04","I13",.035),("M04","I14",.02),("M04","I38",.02),("M04","I22",.20),("M04","I39",.04),
 ("M05","I09",1),("M05","I10",1),("M05","I13",.035),("M05","I14",.02),("M05","I15",.02),("M05","I38",.02),("M05","I22",.20),("M05","I39",.03),
 ("M06","I04",.20),("M06","I22",.25),("M06","I39",.06),("M06","I14",.02),
 ("M07","I03",.22),("M07","I22",.22),("M07","I39",.05),
 ("M08","I06",.25),("M08","I22",.20),("M08","I19",.04),("M08","I16",.04),("M08","I39",.03),
 ("M09","I24",.16),("M09","I13",.07),("M09","I16",.06),("M09","I15",.03),("M09","I43",.03),("M09","I44",.10),
 ("M10","I05",.16),("M10","I25",.15),("M10","I17",.5),("M10","I19",.03),("M10","I13",.02),
 ("M11","I02",.14),("M11","I18",.15),("M11","I40",.04),("M11","I11",1),("M11","I20",.015),
 ("M12","I26",.14),("M12","I19",.06),("M12","I13",.05),("M12","I17",.5),("M12","I41",.05),
 ("M13","I11",3),("M13","I02",.10),("M13","I07",.04),("M13","I13",.04),("M13","I14",.03),("M13","I22",.18),("M13","I39",.03),
 ("M14","I12",1),("M14","I41",.06),("M14","I13",.05),("M14","I14",.03),("M14","I15",.02),("M14","I19",.03),
 ("M15","I08",2),("M15","I07",.05),("M15","I42",.15),("M15","I11",2),("M15","I13",.05),
 ("M16","I08",2),("M16","I07",.04),("M16","I27",.05),("M16","I11",2),("M16","I42",.12),
 ("M17","I28",.15),("M17","I29",.04),("M17","I08",1),("M17","I35",.10),
 ("M18","I01",1),("M18","I10",1),("M18","I08",1),("M18","I07",.03),("M18","I20",.025),("M18","I13",.035),("M18","I42",.12),
 ("M19","I11",2),("M19","I17",1),("M19","I08",1),("M19","I13",.03),("M19","I19",.02),
 ("M20","I22",.20),("M20","I39",.03),("M21","I23",.18),("M21","I39",.04),
 ("M22","I19",.07),("M22","I13",.03),("M22","I15",.01),
 ("M23","I33",1),("M23","I32",.12),("M24","I34",1),("M24","I32",.08),
 ("M25","I30",.018),("M25","I35",.02),("M26","I31",.06),("M27","I32",.25),("M27","I35",.12),
 ("M28","I36",.568),("M29","I37",.18),
]
recipe = pd.DataFrame(R, columns=["menu_item_id","ingredient_id","qty_per_item"])
recipe = recipe.merge(ing[["ingredient_id","unit"]],on="ingredient_id")

# ---------------- weekly market ingredient prices ----------------
weeks = pd.date_range(START, END, freq="W-MON")
tom_2025=[1.30,1.35,1.25,1.05,.95,.88,.82,.80,.85,.95,1.10,1.20]
tom_2026=[1.75,1.95,1.70,1.20,.97,.90,.84,.82,.87,.97,1.12,1.22]
other_prod=[1.08,1.10,1.07,1.02,.98,.95,.93,.93,.96,1.0,1.04,1.07]
prices=[]
for w in weeks:
    t=(w-START).days/365.0
    for r in ing.itertuples():
        base=r.std_cost_2025*(1+0.035*t)
        if r.ingredient_id=="I01": base=r.std_cost_2025*(1+0.075*t)   # beef runs well above budget
        if r.ingredient_id=="I13": s=(tom_2026 if w.year==2026 else tom_2025)[w.month-1]
        elif r.is_produce: s=other_prod[w.month-1]
        else: s=1.0
        prices.append([w,r.ingredient_id,round(base*s*rng.normal(1,.025),3)])
price_wk=pd.DataFrame(prices,columns=["week_start","ingredient_id","market_unit_cost"])

# ---------------- covers (hourly) ----------------
curve=np.array([.03,.06,.07,.06,.07,.10,.08,.05,.035,.04,.07,.10,.09,.06,.035,.015]); curve/=curve.sum()
dow_f={1:.82,2:.85,3:.90,4:.97,5:1.15,6:1.25,7:1.12}
mon_f={1:.88,2:.90,3:.95,4:.98,5:1.03,6:1.08,7:1.12,8:1.12,9:1.0,10:.97,11:.93,12:1.02}
ddi=dd.set_index("date"); wti=weather.set_index("date")

def expected_covers(L, d, dow_override=None):
    r=ddi.loc[d]; dow=dow_override or r.dow_num
    f=L.base_daily_covers*dow_f[dow]*mon_f[r.month_num]*(1.03 if r.year==2026 else 1.0)
    if L.has_patio and r.month_num in (6,7,8): f*=1.08
    c=f*curve.copy()
    if dow in (6,7) or r.is_stat_holiday: c[1:4]*=1.4   # weekend/holiday brunch
    return c

cov_rows=[]; lab_rows=[]; sale_rows=[]
emp_pool={}; emp_rows=[]
ROLES={"Server":(14,2,18.25),"Host":(45,1,18.00),"Bartender":(40,0,19.50),"Line Cook":(24,2,22.75),
       "Prep Cook":(80,1,20.25),"Dishwasher":(55,1,18.50),"Manager":(999,1,31.00)}
first=["Ava","Liam","Noah","Mia","Ethan","Zoe","Lucas","Chloe","Arjun","Priya","Kenji","Hana","Mateo","Sofia","Owen","Leah","Jasper","Nina","Raj","Emma","Daniel","Grace","Wei","Min","Carlos","Isla","Harpreet","Simran","Tyler","Maya"]
last=["Nguyen","Singh","Wong","Smith","Li","Brown","Kaur","Chen","Martin","Gill","Lee","Wilson","Tremblay","Park","Sandhu","Roy","Garcia","Kim","Taylor","Dhillon"]
BLOCKS={"AM":(7,15),"MID":(11,19),"PM":(15,23)}
dp_of_hour={h:dp for dp,hs in DAYPARTS.items() for h in hs}
menu_idx=menu.set_index("menu_item_id")
sid=1
for L in loc.itertuples():
    for d in dates:
        r=ddi.loc[d]
        if d.month==12 and d.day==25: continue   # closed Christmas
        exp=expected_covers(L,d)
        mult=rng.normal(1,.07)
        if wti.loc[d].is_rainy_day: mult*= (0.88 if L.has_patio else 0.93)
        if d.month==12 and d.day in (24,31): mult*=0.7
        act=np.maximum(0,rng.poisson(np.maximum(exp*mult,0.1)))
        yr=d.year
        # hourly covers & sales (sales filled after item gen)
        # ---- items by daypart
        dp_sales={}
        for dp,hs in DAYPARTS.items():
            covers=int(act[[h-7 for h in hs]].sum())
            if covers==0: continue
            w=main_w[dp]; ids=list(w); p=np.array([w[i] for i in ids]); p/=p.sum()
            q=rng.multinomial(covers,p)
            items=dict(zip(ids,q))
            for i,pp in addon_p[dp].items(): items[i]=items.get(i,0)+rng.binomial(covers,pp)
            tot=0
            for i,qq in items.items():
                if qq<=0: continue
                price=menu_idx.loc[i,"price_2026" if d>=pd.Timestamp("2026-01-05") else "price_2025"]
                gross=round(qq*price,2); disc=round(gross*rng.beta(3,97),2); comp=round(gross*rng.beta(1,120),2)
                net=round(gross-disc-comp,2); tot+=net
                sale_rows.append([d,L.location_id,dp,i,qq,price,gross,disc,comp,net])
            dp_sales[dp]=(tot,covers)
        for h in HOURS:
            dp=dp_of_hour[h]; tot,cv=dp_sales.get(dp,(0,1)); c=int(act[h-7])
            cov_rows.append([d,L.location_id,h,dp,c,round(tot*c/cv,2) if cv else 0.0])
        # ---- labour schedule (built from EXPECTED covers, i.e. the manager's forecast)
        sched_exp = exp.copy()
        planted = (L.location_id=="L06" and r.dow_num==1)
        if planted: sched_exp = expected_covers(L,d,dow_override=5)   # Monday scheduled off the Friday template
        diff = act.sum()/max(exp.sum(),1)
        for role,(ratio,mn,wage) in ROLES.items():
            need=np.ceil(sched_exp/ratio).astype(int); need=np.maximum(need,mn)
            if role=="Manager": am,mid,pm=1,0,1
            elif role=="Bartender":
                am=0; pm=max(1,int(need[8:16].max())) if True else 0
                mid=1 if need[4:8].max()>0 and ratio<60 else 0
            elif role=="Prep Cook": am=max(1,int(np.ceil(sched_exp[:8].sum()/ (ratio*6)))); mid=0; pm=0
            else:
                am=int(need[0:4].max()); pm=int(need[12:16].max())
                gap=[need[h-7]-(am if h<15 else pm) for h in range(11,19)]
                mid=max(0,int(max(gap)))
            for blk,cnt in (("AM",am),("MID",mid),("PM",pm)):
                s,e=BLOCKS[blk]
                for _ in range(cnt):
                    emp_id=None
                    ss=d+pd.Timedelta(hours=s); se=d+pd.Timedelta(hours=e)
                    a_s=ss+pd.Timedelta(minutes=int(5*round(rng.normal(-2,5)/5)))
                    end_adj=rng.normal(8,10)
                    # managers cut staff early on slow days, except the planted Coquitlam Mondays
                    if diff<0.92 and role in ("Server","Line Cook","Host") and not planted and rng.random()<.6:
                        end_adj-=rng.integers(60,150)
                    if planted and role in ("Server","Line Cook","Host"): end_adj+=rng.normal(5,8)
                    a_e=se+pd.Timedelta(minutes=int(5*round(end_adj/5)))
                    lab_rows.append([f"S{sid:07d}",d,L.location_id,emp_id,role,blk,ss,se,a_s,a_e]); sid+=1

covers=pd.DataFrame(cov_rows,columns=["business_date","location_id","hour_of_day","daypart","covers","net_sales"])
sales=pd.DataFrame(sale_rows,columns=["business_date","location_id","daypart","menu_item_id","qty_sold","unit_price","gross_sales","discounts","comps","net_sales"])
shifts=pd.DataFrame(lab_rows,columns=["shift_id","business_date","location_id","employee_id","role","shift_block",
                                      "scheduled_start","scheduled_end","actual_start","actual_end"])
# ---- staff roster sized to demand; one shift per person per day; max 5 shifts (~40h) per week
shifts["week_start"]=shifts.business_date-pd.to_timedelta(shifts.business_date.dt.dayofweek,unit="D")
emp_rows=[]; eid=1; assigned=[]
for (l,role),g in shifts.groupby(["location_id","role"],sort=True):
    peak_wk=g.groupby("week_start").size().max(); peak_day=g.groupby("business_date").size().max()
    n=int(max(np.ceil(peak_wk/4.0*1.1),peak_day+1))
    base=ROLES[role][2]; ids=[]
    for _ in range(n):
        e=f"E{eid:04d}"; eid+=1; ids.append(e)
        emp_rows.append([e,f"{rng.choice(first)} {rng.choice(last)}",l,role,round(max(17.85,base*rng.normal(1,.035)),2),
                         (pd.Timestamp("2016-01-01")+pd.Timedelta(days=int(rng.integers(0,3200)))).date()])
    wkcount={}
    for (w,d),gd in g.groupby(["week_start","business_date"],sort=True):
        if w not in wkcount: wkcount={k:v for k,v in wkcount.items() if k[0]==w}
        order=sorted(ids,key=lambda e:(wkcount.get((w,e),0),rng.random()))
        pick=[e for e in order if wkcount.get((w,e),0)<5][:len(gd)]
        if len(pick)<len(gd): pick+= [e for e in order if e not in pick][:len(gd)-len(pick)]
        for e in pick: wkcount[(w,e)]=wkcount.get((w,e),0)+1
        assigned.append(pd.Series(pick,index=gd.index))
shifts["employee_id"]=pd.concat(assigned)
shifts=shifts.drop(columns="week_start")
emp=pd.DataFrame(emp_rows,columns=["employee_id","employee_name","home_location_id","role","hourly_wage","hire_date"])
wage_map=emp.set_index("employee_id").hourly_wage.to_dict()
shifts["scheduled_hours"]=(shifts.scheduled_end-shifts.scheduled_start).dt.total_seconds()/3600
shifts["actual_hours"]=((shifts.actual_end-shifts.actual_start).dt.total_seconds()/3600).round(2)
shifts["hourly_wage"]=(shifts.employee_id.map(wage_map)*np.where(shifts.business_date>=pd.Timestamp("2026-01-01"),1.025,1.0)).round(2)   # 2.5% raise Jan-2026
shifts["labour_cost"]=(shifts.actual_hours*shifts.hourly_wage).round(2)

# ---- hourly labour (pre-exploded for heatmap)
st=(shifts.actual_start-shifts.business_date).dt.total_seconds().values/3600
en=(shifts.actual_end-shifts.business_date).dt.total_seconds().values/3600
H=np.arange(6,24)
ov=np.clip(np.minimum(en[:,None],H[None,:]+1)-np.maximum(st[:,None],H[None,:]),0,1)
hl=pd.DataFrame(ov,columns=H); hl["business_date"]=shifts.business_date.values; hl["location_id"]=shifts.location_id.values
hl["wage"]=shifts.hourly_wage.values
long=hl.melt(id_vars=["business_date","location_id","wage"],var_name="hour_of_day",value_name="hrs")
long=long[long.hrs>0]; long["cost"]=long.hrs*long.wage
lab_hr=long.groupby(["business_date","location_id","hour_of_day"],as_index=False).agg(labour_hours=("hrs","sum"),labour_cost=("cost","sum"))
lab_hr["labour_hours"]=lab_hr.labour_hours.round(2); lab_hr["labour_cost"]=lab_hr.labour_cost.round(2)
lab_hr=lab_hr.merge(covers[["business_date","location_id","hour_of_day","covers","net_sales"]],how="left",on=["business_date","location_id","hour_of_day"])
lab_hr[["covers","net_sales"]]=lab_hr[["covers","net_sales"]].fillna(0)

# ---------------- inventory: theoretical vs actual usage, purchases, counts, waste ----------------
sales["week_start"]=sales.business_date-pd.to_timedelta(sales.business_date.dt.dayofweek,unit="D")
wk=sales.groupby(["week_start","location_id","menu_item_id"],as_index=False).qty_sold.sum()
use=wk.merge(recipe,on="menu_item_id"); use["theo"]=use.qty_sold*use.qty_per_item
use=use.groupby(["week_start","location_id","ingredient_id"],as_index=False).theo.sum()
use=use.merge(ing[["ingredient_id","expected_waste_rate","is_produce","unit"]],on="ingredient_id")
locbias={l:rng.normal(0,.008) for l in loc.location_id}
use["act_factor"]=1+use.expected_waste_rate+use.location_id.map(locbias)+rng.normal(0,.012,len(use))
planted_tom=(use.location_id=="L05")&(use.ingredient_id=="I13")&(use.week_start>=pd.Timestamp("2026-03-02"))
use.loc[planted_tom,"act_factor"]+=0.22
use["actual"]=use.theo*use.act_factor
use["rec_waste"]=use.theo*use.expected_waste_rate*rng.uniform(.5,.7,len(use))
use=use.merge(price_wk,on=["week_start","ingredient_id"])
use=use.sort_values(["location_id","ingredient_id","week_start"])
purch_rows=[]; count_rows=[]; waste_rows=[]; pid=1
for (l,i),g in use.groupby(["location_id","ingredient_id"]):
    days_cover=4 if g.is_produce.iloc[0] else 10
    prev=g.theo.iloc[0]/7*days_cover
    count_rows.append([START-pd.Timedelta(days=1),l,i,round(prev,3)])
    for r in g.itertuples():
        end=max(0,r.theo/7*days_cover*rng.normal(1,.12))
        buy=r.actual+end-prev
        if buy<0: end=prev-r.actual; buy=0
        splits=[(0,.55),(3,.45)] if r.is_produce else [(1,1.0)]
        for off,share in splits:
            q=buy*share
            if q<=0: continue
            uc=round(r.market_unit_cost*rng.normal(1,.02),3)
            purch_rows.append([f"PO{pid:07d}",r.week_start+pd.Timedelta(days=off),l,i,round(q,3),r.unit,uc,round(q*uc,2)]); pid+=1
        count_rows.append([r.week_start+pd.Timedelta(days=6),l,i,round(end,3)])
        wd=r.week_start+pd.Timedelta(days=int(rng.integers(0,7)))
        waste_rows.append([wd,l,i,round(r.rec_waste,3),r.unit,rng.choice(["Spoilage","Prep trim","Dropped/Remake","Expired"],p=[.4,.3,.2,.1])])
        prev=end
ing_u=ing.set_index("ingredient_id").unit
purch=pd.DataFrame(purch_rows,columns=["po_line_id","delivery_date","location_id","ingredient_id","qty_received","unit","unit_cost","line_total"])
purch["supplier"]=purch.ingredient_id.map(ing.set_index("ingredient_id").supplier)
counts=pd.DataFrame(count_rows,columns=["count_date","location_id","ingredient_id","qty_on_hand"])
counts["unit"]=counts.ingredient_id.map(ing_u)
waste=pd.DataFrame(waste_rows,columns=["waste_date","location_id","ingredient_id","qty_wasted","unit","reason"])

usage_wk=use[["week_start","location_id","ingredient_id","theo","actual","rec_waste"]].rename(columns={"theo":"theoretical_qty","actual":"actual_qty","rec_waste":"recorded_waste_qty"}).round(3)

# ---------------- monthly targets ----------------
m_sales=sales.assign(year_month=sales.business_date.dt.strftime("%Y-%m")).groupby(["year_month","location_id"],as_index=False).net_sales.sum()
tg=m_sales.copy(); tg["net_sales_budget"]=(tg.net_sales*rng.normal(1.02,.03,len(tg))).round(-2)
tg["labour_pct_target"]=0.30; tg["food_cost_pct_target"]=0.285; tg["avg_check_target"]=24.00
tg=tg.drop(columns="net_sales")

# ---------------- write CLEAN ----------------
def w(df,name,folder="clean"): df.to_csv(f"{OUT}/{folder}/{name}.csv",index=False,date_format="%Y-%m-%d")
w(loc.drop(columns=["base_daily_covers"]),"dim_location"); w(dd,"dim_date"); w(menu,"dim_menu_item"); w(ing,"dim_ingredient")
w(emp,"dim_employee"); w(recipe,"bridge_recipe"); w(weather,"dim_weather_daily")
w(sales.drop(columns="week_start"),"fact_sales_item_daypart"); w(covers,"fact_covers_hourly")
sh=shifts.copy()
for c in ["scheduled_start","scheduled_end","actual_start","actual_end"]: sh[c]=sh[c].dt.strftime("%Y-%m-%d %H:%M")
w(sh,"fact_labour_shifts"); w(lab_hr,"fact_labour_hourly")
w(purch,"fact_purchases"); w(counts,"fact_inventory_counts"); w(waste,"fact_waste_log")
w(price_wk,"fact_ingredient_price_weekly"); w(usage_wk,"fact_ingredient_usage_weekly"); w(tg,"fact_targets_monthly")

# ---------------- write RAW (messy source extracts) ----------------
name_var={"L01":["Downtown Robson","DT Robson","downtown robson ","Robson St"],"L02":["Kitsilano","KITS","kitsilano"],
 "L03":["Metrotown","Metrotown ","METROTOWN"],"L04":["Richmond Centre","Richmond Center","Rmd Centre"],
 "L05":["Guildford","Surrey - Guildford","guildford"],"L06":["Coquitlam Centre","Coquitlam Ctr","COQUITLAM"],
 "L07":["Lonsdale","N. Van Lonsdale","Lonsdale "],"L08":["Willowbrook","Langley Willowbrook","willowbrook"],
 "L09":["Columbia Square","New West","Columbia Sq"],"L10":["Sevenoaks","Abbotsford Sevenoaks","sevenoaks"]}
def messy_loc(s):
    out=s.map(lambda x: name_var[x][0]).values.copy()
    mask=rng.random(len(s))<.08
    out[mask]=[rng.choice(name_var[x]) for x in s.values[mask]]
    return out
# POS
rp=sales.drop(columns="week_start").merge(menu[["menu_item_id","menu_item_name"]],on="menu_item_id")
rp["store"]=messy_loc(rp.location_id); rp=rp.drop(columns=["location_id"])
d_s=rp.business_date.dt.strftime("%Y-%m-%d").values.copy(); msk=rng.random(len(rp))<.05
d_s[msk]=rp.business_date[msk].dt.strftime("%d-%b-%Y").values; rp["business_date"]=d_s
nm=rp.menu_item_name.values.copy(); msk=rng.random(len(rp))<.03; nm[msk]=[x.upper()+" " for x in nm[msk]]; rp["menu_item_name"]=nm
rp.loc[rng.random(len(rp))<.002,"net_sales"]=np.nan
dup=rp.sample(frac=.004,random_state=1); rp=pd.concat([rp,dup]).sample(frac=1,random_state=2)
rp=rp[["business_date","store","daypart","menu_item_id","menu_item_name","qty_sold","unit_price","gross_sales","discounts","comps","net_sales"]]
w(rp,"pos_sales_extract","raw")
rc=covers.copy(); rc["store"]=messy_loc(rc.location_id); rc=rc.drop(columns="location_id")
w(rc[["business_date","store","hour_of_day","covers","net_sales"]],"pos_covers_hourly_extract","raw")
# Labour
rl=sh.copy(); rl["store"]=messy_loc(rl.location_id)
role_var={"Line Cook":["LINE COOK","Cook - Line"],"Server":["server","SERVER"],"Dishwasher":["Dish","Dishwasher "]}
rv=rl.role.values.copy(); msk=rng.random(len(rl))<.05
rv[msk]=[rng.choice(role_var.get(x,[x])) for x in rv[msk]]; rl["role"]=rv
rl.loc[rng.random(len(rl))<.005,"actual_end"]=np.nan
rl=rl[["shift_id","business_date","store","employee_id","role","scheduled_start","scheduled_end","actual_start","actual_end"]]
rl=pd.concat([rl,rl.sample(frac=.003,random_state=3)]).sample(frac=1,random_state=4)
w(rl,"timeclock_extract","raw")
# Purchases: some produce lines in lb, supplier name variants
rpu=purch.copy(); rpu["store"]=messy_loc(rpu.location_id)
prod_ids=set(ing[(ing.is_produce==1)&(ing.unit=="kg")].ingredient_id)
msk=(rpu.ingredient_id.isin(prod_ids))&(rng.random(len(rpu))<.04)
rpu.loc[msk,"qty_received"]=(rpu.loc[msk,"qty_received"]*2.20462).round(3); rpu.loc[msk,"unit"]="lb"
rpu.loc[msk,"unit_cost"]=(rpu.loc[msk,"unit_cost"]/2.20462).round(3)
sv=rpu.supplier.values.copy(); msk2=rng.random(len(rpu))<.06; sv[msk2]=[s.upper() for s in sv[msk2]]; rpu["supplier"]=sv
rpu=rpu.merge(ing[["ingredient_id","ingredient_name"]],on="ingredient_id")
rpu=rpu[["po_line_id","delivery_date","store","supplier","ingredient_id","ingredient_name","qty_received","unit","unit_cost","line_total"]]
rpu=pd.concat([rpu,rpu.sample(frac=.003,random_state=5)]).sample(frac=1,random_state=6)
w(rpu,"purchasing_extract","raw")
rcn=counts.copy(); rcn["store"]=messy_loc(rcn.location_id)
w(rcn[["count_date","store","ingredient_id","qty_on_hand","unit"]],"inventory_counts_extract","raw")
rw=waste.copy(); rw["store"]=messy_loc(rw.location_id); w(rw[["waste_date","store","ingredient_id","qty_wasted","unit","reason"]],"waste_log_extract","raw")
# reference tables raw = clean copies
for n,df in [("ref_locations",loc.drop(columns="base_daily_covers")),("ref_menu",menu),("ref_ingredients",ing),("ref_recipes",recipe),("ref_employees",emp)]:
    w(df,n,"raw")

# ---------------- sanity summary ----------------
mc=recipe.merge(ing[["ingredient_id","std_cost_2025"]],on="ingredient_id").assign(c=lambda t:t.qty_per_item*t.std_cost_2025).groupby("menu_item_id").c.sum()
mm=menu.set_index("menu_item_id").join(mc).join(sales.groupby("menu_item_id").qty_sold.sum())
mm["cm"]=mm.price_2025-mm.c; mm["fc%"]=mm.c/mm.price_2025
mains=mm[mm.is_main==1].copy(); mains["mix"]=mains.qty_sold/mains.qty_sold.sum()
avg_cm=(mains.cm*mains.qty_sold).sum()/mains.qty_sold.sum(); thr=0.7/len(mains)
mains["quad"]=[("Star" if cm>=avg_cm else "Plowhorse") if mx>=thr else ("Puzzle" if cm>=avg_cm else "Dog") for cm,mx in zip(mains.cm,mains.mix)]
print(mains[["menu_item_name","price_2025","c","fc%","cm","mix","quad"]].round(3).to_string()); print("avgcm",avg_cm)
print("rows:",{k:len(v) for k,v in dict(sales=sales,covers=covers,shifts=shifts,lab_hr=lab_hr,purch=purch,counts=counts).items()})
tot_sales=sales.net_sales.sum(); print("total net sales", round(tot_sales/1e6,2),"M")
ls=shifts.groupby("location_id").labour_cost.sum()/sales.groupby("location_id").net_sales.sum(); print("labour %\n",ls.round(3))
x=lab_hr.merge(dd[["date","day_of_week"]],left_on="business_date",right_on="date")
g=x.groupby(["location_id","day_of_week"]).apply(lambda t:t.labour_cost.sum()/t.net_sales.sum()).unstack()
print(g.round(3))
uc=use.assign(tc=use.theo*use.market_unit_cost, ac=use.actual*use.market_unit_cost)
fc=uc.groupby("location_id")[["tc","ac"]].sum().join(sales.groupby("location_id").net_sales.sum())
fc["theo_pct"]=fc.tc/fc.net_sales; fc["act_pct"]=fc.ac/fc.net_sales; print(fc[["theo_pct","act_pct"]].round(3))
tm=use[(use.ingredient_id=="I13")].assign(ratio=lambda t:t.actual/t.theo).groupby(["location_id",use.week_start.dt.year])["ratio"].mean().unstack(); print(tm.round(3))
