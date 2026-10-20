"""
Generate synthetic seed CSVs for the paid_media_mart dbt project.

Run from the dbt project root:
    python scripts/generate_seeds.py

Writes 5 CSVs into ./seeds/. Uses only the Python standard library.
Fixed random seed, so every run produces identical data.
"""

import csv
import os
import random
from datetime import date, datetime, timedelta

random.seed(42)

START = date(2026, 7, 1)
END = date(2026, 9, 30)
OUT_DIR = "seeds"

# Campaign setup. Each platform uses its own ID format, like the real APIs.
# cvr = click-to-signup rate; paid_share = share of signups from a paid plan.
CAMPAIGNS = {
    "google": [
        {"id": "18234567801", "name": "Search - Brand", "daily": 180, "cpc": 1.80, "ctr": 0.12, "cvr": 0.090},
        {"id": "18234567802", "name": "Search - Nonbrand - Data Pipelines", "daily": 650, "cpc": 6.50, "ctr": 0.045, "cvr": 0.030},
        {"id": "18234567803", "name": "Search - Competitor", "daily": 300, "cpc": 8.20, "ctr": 0.030, "cvr": 0.020},
        {"id": "18234567804", "name": "PMax - Signups", "daily": 400, "cpc": 2.40, "ctr": 0.015, "cvr": 0.012},
        {"id": "18234567805", "name": "YouTube - Awareness", "daily": 250, "cpc": 0.90, "ctr": 0.004, "cvr": 0.003},
    ],
    "meta": [
        {"id": "120210000000001", "name": "Prospecting - Lookalike 1%", "daily": 500, "cpc": 2.10, "ctr": 0.011, "cvr": 0.010},
        {"id": "120210000000002", "name": "Prospecting - Interest Stack", "daily": 350, "cpc": 1.70, "ctr": 0.009, "cvr": 0.007},
        {"id": "120210000000003", "name": "Retargeting - Site Visitors 30d", "daily": 150, "cpc": 1.20, "ctr": 0.018, "cvr": 0.040},
        {"id": "120210000000004", "name": "Instagram - Reels Test", "daily": 120, "cpc": 0.95, "ctr": 0.008, "cvr": 0.004},
    ],
    "linkedin": [
        {"id": "612345001", "name": "ABM - Data Eng Titles", "daily": 450, "cpc": 11.50, "ctr": 0.006, "cvr": 0.035},
        {"id": "612345002", "name": "Thought Leadership - Doc Ads", "daily": 250, "cpc": 7.80, "ctr": 0.005, "cvr": 0.020},
        {"id": "612345003", "name": "Retargeting - Website", "daily": 100, "cpc": 6.20, "ctr": 0.009, "cvr": 0.050},
    ],
}

# Messy UTM variants, the way they show up in real signup data.
UTM_VARIANTS = {
    "google": [("google", "cpc"), ("Google", "cpc"), ("google ", "CPC"), ("google", "paid_search")],
    "meta": [("facebook", "paid_social"), ("fb", "paid_social"), ("Facebook", "cpc"), ("instagram", "paid_social"), ("meta", "paid_social")],
    "linkedin": [("linkedin", "paid_social"), ("LinkedIn", "paid_social"), ("linkedin", "cpc"), ("li", "paid_social")],
}

PLANS = [("free", 0.0), ("starter", 49.0), ("pro", 199.0)]


def daterange(start, end):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def day_factor(d):
    """Weekday seasonality plus noise, with a mid-quarter budget bump."""
    weekday = {0: 1.10, 1: 1.15, 2: 1.12, 3: 1.05, 4: 0.95, 5: 0.70, 6: 0.72}[d.weekday()]
    bump = 1.20 if date(2026, 8, 15) <= d <= date(2026, 9, 10) else 1.0
    return weekday * bump * random.uniform(0.85, 1.15)


def pick_plan():
    r = random.random()
    if r < 0.70:
        return PLANS[0]
    if r < 0.92:
        return PLANS[1]
    return PLANS[2]


def random_ts(d):
    secs = random.randint(0, 86399)
    return (datetime(d.year, d.month, d.day) + timedelta(seconds=secs)).strftime("%Y-%m-%d %H:%M:%S")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    google_rows, meta_rows, linkedin_rows, signups = [], [], [], []
    user_n = 0

    def add_signup(d, source, medium, campaign):
        nonlocal user_n
        user_n += 1
        plan, revenue = pick_plan()
        signups.append({
            "user_id": f"u_{user_n:06d}",
            "signup_ts": random_ts(d),
            "utm_source": source,
            "utm_medium": medium,
            "utm_campaign": campaign,
            "plan": plan,
            "revenue": f"{revenue:.2f}",
        })

    for d in daterange(START, END):
        f = day_factor(d)
        for platform, camps in CAMPAIGNS.items():
            for c in camps:
                spend = round(c["daily"] * f * random.uniform(0.9, 1.1), 2)
                clicks = max(1, int(spend / (c["cpc"] * random.uniform(0.85, 1.15))))
                impressions = int(clicks / (c["ctr"] * random.uniform(0.85, 1.15)))

                if platform == "google":
                    google_rows.append({
                        "date": d.isoformat(),
                        "campaign_id": c["id"],
                        "campaign_name": c["name"],
                        "cost_micros": int(spend * 1_000_000),
                        "impressions": impressions,
                        "clicks": clicks,
                    })
                elif platform == "meta":
                    meta_rows.append({
                        "date_start": d.isoformat(),
                        "campaign_id": c["id"],
                        "campaign_name": c["name"],
                        "spend": f"{spend:.2f}",
                        "impressions": impressions,
                        "clicks": clicks,
                    })
                else:
                    linkedin_rows.append({
                        "day": d.isoformat(),
                        "campaign_id": c["id"],
                        "campaign_name": c["name"],
                        "cost_usd": f"{spend:.2f}",
                        "impressions": impressions,
                        "clicks": clicks,
                    })

                # Paid signups attributed to this campaign
                n_signups = sum(1 for _ in range(clicks) if random.random() < c["cvr"])
                for _ in range(n_signups):
                    source, medium = random.choice(UTM_VARIANTS[platform])
                    campaign = c["id"]
                    # ~5% of paid signups lose their utm_campaign (broken tagging)
                    if random.random() < 0.05:
                        campaign = ""
                    add_signup(d, source, medium, campaign)

        # Non-paid signups: organic search, direct, referral, email
        for _ in range(int(14 * f)):
            add_signup(d, random.choice(["google", "bing", "duckduckgo"]), "organic", "")
        for _ in range(int(9 * f)):
            add_signup(d, "", "", "")  # direct: no UTMs at all
        for _ in range(int(4 * f)):
            add_signup(d, random.choice(["news.ycombinator.com", "reddit.com", "g2.com"]), "referral", "")
        for _ in range(int(3 * f)):
            add_signup(d, "newsletter", "email", "")

    signups.sort(key=lambda r: r["signup_ts"])

    # Mapping keys are already normalized (lowercase, trimmed). Staging cleans the UTMs to match.
    channel_mapping = [
        ("google", "cpc", "Paid Search"),
        ("google", "paid_search", "Paid Search"),
        ("facebook", "paid_social", "Paid Social - Meta"),
        ("facebook", "cpc", "Paid Social - Meta"),
        ("fb", "paid_social", "Paid Social - Meta"),
        ("instagram", "paid_social", "Paid Social - Meta"),
        ("meta", "paid_social", "Paid Social - Meta"),
        ("linkedin", "paid_social", "Paid Social - LinkedIn"),
        ("linkedin", "cpc", "Paid Social - LinkedIn"),
        ("li", "paid_social", "Paid Social - LinkedIn"),
        ("google", "organic", "Organic Search"),
        ("bing", "organic", "Organic Search"),
        ("duckduckgo", "organic", "Organic Search"),
        ("newsletter", "email", "Email"),
        # Marketo programs and their Salesforce campaigns classify through the same table.
        ("marketo", "email", "Email"),
        ("marketo", "webinar", "Events"),
    ]

    def write(name, rows, fields):
        path = os.path.join(OUT_DIR, name)
        with open(path, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=fields)
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {path}: {len(rows):,} rows")

    write("google_ads_spend.csv", google_rows, ["date", "campaign_id", "campaign_name", "cost_micros", "impressions", "clicks"])
    write("meta_ads_spend.csv", meta_rows, ["date_start", "campaign_id", "campaign_name", "spend", "impressions", "clicks"])
    write("linkedin_ads_spend.csv", linkedin_rows, ["day", "campaign_id", "campaign_name", "cost_usd", "impressions", "clicks"])
    write("signups.csv", signups, ["user_id", "signup_ts", "utm_source", "utm_medium", "utm_campaign", "plan", "revenue"])
    write("channel_mapping.csv",
          [{"utm_source": s, "utm_medium": m, "channel": c} for s, m, c in channel_mapping],
          ["utm_source", "utm_medium", "channel"])

    total = (sum(r["cost_micros"] for r in google_rows) / 1_000_000
             + sum(float(r["spend"]) for r in meta_rows)
             + sum(float(r["cost_usd"]) for r in linkedin_rows))
    print(f"\nTotal spend across platforms: ${total:,.2f}  (save this for the reconciliation test)")


if __name__ == "__main__":
    main()
