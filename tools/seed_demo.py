#!/usr/bin/env python3
"""Loads demo data (based on the Longview design) into a running backend.

    python3 tools/seed_demo.py --api http://localhost:8080
Run it on an empty database: it stops if accounts already exist.
"""
import argparse, json, urllib.request, datetime as dt

p = argparse.ArgumentParser()
p.add_argument("--api", default="http://localhost:8080")
a = p.parse_args()

def call(method, path, body=None):
    req = urllib.request.Request(a.api + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        t = r.read()
        return json.loads(t) if t else None

today = dt.date.today()
y, m = today.year, today.month
def d(day, months_back=0):
    mm, yy = m - months_back, y
    while mm < 1: mm += 12; yy -= 1
    return dt.date(yy, mm, min(day, 28)).isoformat()

if call("GET", "/api/accounts"):
    raise SystemExit("There are already accounts. Start the backend with a fresh DB_PATH to load the demo.")
cats = {c["name"]: c["id"] for c in call("GET", "/api/categories")}
start = d(28, 9)
monzo = call("POST", "/api/accounts", {"name": "Monzo Current", "type": "current", "source": "file_import", "openingBalance": 150000, "openingDate": start, "logoWebsite": "monzo.com"})["id"]
starling = call("POST", "/api/accounts", {"name": "Starling Savings", "type": "savings", "source": "file_import", "openingBalance": 0, "openingDate": start, "countsTowardsSavings": True, "logoWebsite": "starlingbank.com"})["id"]
amex = call("POST", "/api/accounts", {"name": "Amex card", "type": "credit_card", "source": "file_import", "openingBalance": 0, "openingDate": start, "logoWebsite": "americanexpress.com"})["id"]
call("POST", "/api/accounts", {"name": "Cash wallet", "type": "cash", "source": "manual", "openingBalance": 8500, "openingDate": d(10)})

call("PUT", "/api/goal", {"monthlyAmount": 50000, "startDate": d(1, 8)})

rules = [
    ("Weekday lunch at Tesco", "Lunch", False, [{"field": "merchant", "op": "contains", "value": "Tesco"}, {"field": "amount", "op": "less_than", "value": "20.00"},
        {"field": "day_of_week", "days": ["Mon", "Tue", "Wed", "Thu", "Fri"]}, {"field": "time", "from": "11:00", "to": "15:00"}]),
    ("Salary", "Income", False, [{"field": "description", "op": "contains", "value": "ACME LTD"}]),
    ("Fuel", "Transport", False, [{"field": "merchant", "op": "is_one_of", "value": "Shell, BP, Esso"}]),
    ("Amazon orders", None, True, [{"field": "merchant", "op": "contains", "value": "Amazon"}]),
    ("Supermarkets", "Groceries", False, [{"field": "merchant", "op": "is_one_of", "value": "Sainsbury, Aldi, Tesco Superstore"}]),
    ("Savings transfer", "Savings", False, [{"field": "merchant", "op": "contains", "value": "To Starling"}]),
]
for name, cat, split, conds in rules:
    call("POST", "/api/rules", {"name": name, "categoryId": cats.get(cat), "splitByReceipt": split, "conditions": conds})

bills = [("Rent", 115000, 1), ("Council tax", 16800, 1), ("Energy", 9600, 5), ("Water", 3800, 8), ("Broadband", 3200, 12), ("Gym", 3500, 18), ("Phone", 1800, 20)]
for n, amt, day in bills:
    call("POST", "/api/scheduled", {"name": n, "amount": amt, "categoryId": cats["Bills"] if n != "Gym" else cats["Health & fitness"], "group": "bill", "repeat": "monthly", "firstDate": d(day, 9), "accountId": monzo})
call("POST", "/api/scheduled", {"name": "Streaming", "amount": 1099, "categoryId": cats["Bills"], "group": "bill", "repeat": "monthly", "firstDate": d(22, 9), "accountId": amex})
call("POST", "/api/scheduled", {"name": "Car insurance", "amount": 54000, "group": "yearly", "repeat": "yearly", "firstDate": d(3, 7), "accountId": starling})
for n, amt in [("Groceries", 32000), ("Lunch", 8000), ("Transport", 12000)]:
    call("POST", "/api/scheduled", {"name": n, "amount": amt, "categoryId": cats[n], "group": "pot", "repeat": "monthly", "firstDate": "2000-01-01"})

saved = [52000, 48000, 61000, 35000, 50000, 29000, 54000, 42000, 16000]
rows = ["Date,Time,Name,Paid out,Paid in"]
for back in range(8, -1, -1):
    s = saved[8 - back]
    rows.append(f"{d(2, back)},09:00,To Starling Savings,{s/100:.2f},")
    if back > 0 or today.day >= 28:
        pass
    rows.append(f"{d(28, back + 1)},06:00,ACME LTD,,3250.00")
    for n, amt, day in bills:
        if back > 0 or day <= today.day:
            rows.append(f"{d(day, back)},07:00,{n},{amt/100:.2f},")
    for day, t, n, amt in [(3, "18:44", "Sainsbury's", 62.40), (4, "12:05", "Tesco Express", 4.10), (6, "13:12", "Tesco Metro", 6.45),
                           (8, "11:30", "Tesco Superstore", 58.30), (11, "12:22", "Tesco Express", 4.85), (13, "14:02", "Tesco Express", 7.40), (15, "10:20", "Aldi", 53.50)]:
        if back > 0 or day <= today.day:
            rows.append(f"{d(day, back)},{t},{n},{amt:.2f},")
    if back in (0, 2, 4):
        rows.append(f"{d(13, back)},08:10,Train to Leeds,80.60,")
rows.append(f"{d(9)},09:40,Vet bill,186.40,")
rows.append(f"{d(22, 1)},10:00,Boiler repair,245.00,")
starling_rows = ["Date,Description,Amount"] + [f"{d(2, b)},From Monzo,{saved[8 - b]/100:.2f}" for b in range(8, -1, -1)]

def imp(acc, text, name):
    p = call("POST", "/api/import/parse", {"accountId": acc, "fileName": name, "content": text})
    return call("POST", "/api/import/commit", {"accountId": acc, "content": text, "mapping": p["mapping"], "dateFormat": p["dateFormat"], "signConvention": p["signConvention"]})

print("monzo", imp(monzo, "\n".join(r.replace(r.split(",")[0], dt.date.fromisoformat(r.split(",")[0]).strftime("%d/%m/%Y"), 1) if r[0].isdigit() else r for r in rows), "monzo.csv"))
print("starling", imp(starling, "\n".join(starling_rows), "starling.csv"))
amex_csv = "\n".join(["Date,Description,Amount,Appears On Your Statement As,Extended Details,Address,Reference",
    f"{dt.date.fromisoformat(d(12)).strftime('%d/%m/%Y')},AMAZON.CO.UK*AB12C,64.97,AMAZON.CO.UK,Online retail,LUXEMBOURG,AT243160034",
    f"{dt.date.fromisoformat(d(9)).strftime('%d/%m/%Y')},SHELL 4471,52.10,SHELL,Fuel,READING,AT243130072",
    f"{dt.date.fromisoformat(d(4)).strftime('%d/%m/%Y')},GIFT SHOP,45.00,GIFT SHOP,Retail,LONDON,AT243100001",
    f"{dt.date.fromisoformat(d(5)).strftime('%d/%m/%Y')},PAYMENT RECEIVED - THANK YOU,-500.00,PAYMENT RECEIVED,,,AT243090001"])
print("amex", imp(amex, amex_csv, "amex-statement.csv"))
long_date = dt.date.fromisoformat(d(12)).strftime("%-d %B %Y")
call("POST", "/api/receipts", {"text": f"Order placed {long_date}\nUSB-C charging cable, 2 m £8.99\nChildren's picture book £6.99\nWashing-up liquid, 3 pack £4.49\nRunning shoes £44.50\nOrder Total: £64.97"})
bal = {b["date"]: b["calculated"] for b in call("GET", f"/api/accounts/{monzo}/balances?days=31")}
if d(10) in bal:
    call("PUT", f"/api/accounts/{monzo}/overrides", {"date": d(10), "balance": bal[d(10)] + 1360, "note": "Pending refund not in the feed yet"})
print("Done. Open the app to see the demo data.")
