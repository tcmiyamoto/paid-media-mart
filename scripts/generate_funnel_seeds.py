"""
Generate synthetic B2B funnel seeds (leads and funnel events) for the paid_media_mart project.

Run from the dbt project root, after generate_seeds.py:
    python scripts/generate_funnel_seeds.py

Reads the ad spend seeds so lead volume follows actual daily campaign spend, then writes
seeds/leads.csv and seeds/funnel_events.csv. Standard library only, fixed random seed.

The business has two product lines and two motions:
  core         PLG (free trial) and SLG (talk to sales)
  new_product  SLG only (working session request)
Events after END are dropped, so recent cohorts have open pipeline, like a real CRM.
"""

import csv
import os
import random
from datetime import date, datetime, timedelta

random.seed(7)

START = date(2026, 7, 1)
END = date(2026, 9, 30)
SEEDS = "seeds"

# Cost per lead by landing form (paid traffic). Lower for self-serve, higher for sales forms.
CPL = {"free_trial": 95.0, "talk_to_sales": 260.0, "working_session": 520.0}

# Daily leads from non-paid channels, by form.
ORGANIC_DAILY = {
    "free_trial": [("google", "organic", 5.0), ("bing", "organic", 1.5), ("", "", 4.0),
                   ("g2.com", "referral", 1.0), ("newsletter", "email", 1.2)],
    "talk_to_sales": [("google", "organic", 2.0), ("", "", 2.5), ("g2.com", "referral", 0.6),
                      ("newsletter", "email", 0.5)],
    "working_session": [("", "", 0.5), ("google", "organic", 0.3), ("newsletter", "email", 0.3)],
}

UTM_VARIANTS = {
    "google": [("google", "cpc"), ("google", "paid_search")],
    "meta": [("facebook", "paid_social"), ("meta", "paid_social"), ("instagram", "paid_social")],
    "linkedin": [("linkedin", "paid_social"), ("li", "paid_social")],
}

CORE_BANDS = [("<15k", 0.35, 99, 6000), ("15k-60k", 0.30, 349, 15000), ("60k-200k", 0.20, 799, 36000),
              ("200k-500k", 0.10, 1499, 75000), ("500k+", 0.05, 2999, 120000)]
NEW_PRODUCT_BANDS = [("2-10", 0.30, 30000), ("11-50", 0.40, 60000), ("51-200", 0.22, 110000),
                     ("201+", 0.08, 180000)]


def read_daily_spend():
    """Return {(platform, campaign_id, date): spend_usd} from the existing spend seeds."""
    spend = {}
    with open(os.path.join(SEEDS, "google_ads_spend.csv")) as fh:
        for r in csv.DictReader(fh):
            spend[("google", r["campaign_id"], r["date"])] = float(r["cost_micros"]) / 1e6
    with open(os.path.join(SEEDS, "meta_ads_spend.csv")) as fh:
        for r in csv.DictReader(fh):
            spend[("meta", r["campaign_id"], r["date_start"])] = float(r["spend"])
    with open(os.path.join(SEEDS, "linkedin_ads_spend.csv")) as fh:
        for r in csv.DictReader(fh):
            spend[("linkedin", r["campaign_id"], r["day"])] = float(r["cost_usd"])
    return spend


def read_campaign_mapping():
    with open(os.path.join(SEEDS, "campaign_motion_mapping.csv")) as fh:
        return {(r["platform"], r["campaign_id"]): r for r in csv.DictReader(fh)}


def poisson(lam):
    """Knuth's algorithm; fine for the small daily rates used here."""
    L, k, p = pow(2.718281828459045, -lam), 0, 1.0
    while True:
        p *= random.random()
        if p <= L:
            return k
        k += 1


def pick(bands, weight_index=1):
    r, acc = random.random(), 0.0
    for b in bands:
        acc += b[weight_index]
        if r <= acc:
            return b
    return bands[-1]


def ts(d, hours_offset=0.0):
    base = datetime(d.year, d.month, d.day) + timedelta(seconds=random.randint(28800, 64800))
    return base + timedelta(hours=hours_offset)


def make_lead(lead_id, d, form, product_line, motion, source, medium, campaign_id, click_id):
    if product_line == "core":
        band = pick(CORE_BANDS)
        segment_type, segment = "monthly_expenses", band[0]
    else:
        band = pick(NEW_PRODUCT_BANDS)
        segment_type, segment = "employees", band[0]
    created = ts(d)
    lead = {
        "lead_id": lead_id, "created_ts": created.strftime("%Y-%m-%d %H:%M:%S"),
        "landing_form": form, "product_line": product_line, "motion": motion,
        "utm_source": source, "utm_medium": medium, "utm_campaign": campaign_id,
        "click_id": click_id, "segment_type": segment_type, "segment": segment,
    }
    return lead, band, created


def events_for(lead, band, created):
    """Walk a lead through its motion's stages; return the events that happened by END."""
    out = []
    end_dt = datetime(END.year, END.month, END.day, 23, 59, 59)

    def add(stage, t, amount=""):
        if t <= end_dt:
            out.append({"lead_id": lead["lead_id"], "stage": stage,
                        "event_ts": t.strftime("%Y-%m-%d %H:%M:%S"), "amount": amount})
            return True
        return False

    if lead["motion"] == "plg":
        add("trial_started", created)
        if random.random() < 0.46:
            t = created + timedelta(days=random.uniform(0.1, 5))
            if add("activated", t) and random.random() < 0.38:
                arr = band[2] * 12
                add("converted_paid", created + timedelta(days=random.uniform(13, 18)), f"{arr:.2f}")
        return out

    new = lead["product_line"] == "new_product"
    add("lead_created", created)
    if random.random() >= (0.55 if new else 0.62):
        return out
    t = created + timedelta(days=random.uniform(0.01, 3))
    if not add("meeting_booked", t) or random.random() >= (0.80 if new else 0.74):
        return out
    t = t + timedelta(days=random.uniform(1, 6))
    if not add("meeting_held", t) or random.random() >= (0.52 if new else 0.60):
        return out
    acv = (band[2] if new else band[3]) * random.uniform(0.8, 1.25)
    t = t + timedelta(days=random.uniform(1, 8))
    if not add("opportunity_created", t, f"{acv:.2f}"):
        return out
    close = t + timedelta(days=random.uniform(35, 90) if new else random.uniform(14, 50))
    won = random.random() < (0.26 if new else 0.32)
    add("closed_won" if won else "closed_lost", close, f"{acv:.2f}" if won else "")
    return out


def main():
    spend = read_daily_spend()
    mapping = read_campaign_mapping()
    leads, events, n = [], [], 0

    d = START
    while d <= END:
        ds = d.isoformat()
        # Paid leads follow each campaign's actual spend that day.
        for (platform, cid), m in mapping.items():
            day_spend = spend.get((platform, cid, ds), 0.0)
            for _ in range(poisson(day_spend / CPL[m["landing_form"]])):
                n += 1
                source, medium = random.choice(UTM_VARIANTS[platform])
                gclid = ""
                # The free trial form doesn't capture the Google click ID; sales forms do.
                if platform == "google" and m["landing_form"] != "free_trial":
                    gclid = f"Cj0K{random.getrandbits(48):012x}"
                lead, band, created = make_lead(f"L{n:06d}", d, m["landing_form"], m["product_line"],
                                                m["motion"], source, medium, cid, gclid)
                leads.append(lead)
                events.extend(events_for(lead, band, created))
        # Non-paid leads.
        for form, sources in ORGANIC_DAILY.items():
            product_line = "new_product" if form == "working_session" else "core"
            motion = "plg" if form == "free_trial" else "slg"
            for source, medium, rate in sources:
                for _ in range(poisson(rate)):
                    n += 1
                    lead, band, created = make_lead(f"L{n:06d}", d, form, product_line, motion,
                                                    source, medium, "", "")
                    leads.append(lead)
                    events.extend(events_for(lead, band, created))
        d += timedelta(days=1)

    for name, rows in (("leads.csv", leads), ("funnel_events.csv", events)):
        with open(os.path.join(SEEDS, name), "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {name}: {len(rows):,} rows")


if __name__ == "__main__":
    main()
