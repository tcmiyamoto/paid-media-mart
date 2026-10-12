"""
Generate synthetic multi-touch journey seeds for the paid_media_mart project.

Run from the dbt project root, after generate_funnel_seeds.py:
    python scripts/generate_touchpoint_seeds.py

Reads seeds/leads.csv and seeds/funnel_events.csv and writes:
  web_sessions.csv         GA4-style sessions (one row per session, with UTMs)
  web_identities.csv       user_pseudo_id -> lead_id, set when a visitor submits a form
  marketo_activities.csv   email clicks and webinar attendance for known leads

Every lead keeps the UTMs it already has in leads.csv; that is its lead-creation touch.
This script adds the touches around it: earlier anonymous visits, and nurture touches between
lead creation and opportunity. Standard library only, fixed random seed.

Built-in messiness, handled in the dbt models:
  - About 8% of leads have no web session at conversion (ad blocker or no consent), so
    their journey is only the CRM form fill.
  - About 15% of pre-lead visits happen on a second device that is never identified.
  - Some UTM sources have inconsistent casing and stray spaces.
  - About 2% of Marketo activity rows are exported twice.
  - Touches after the opportunity is created, and post-trial onboarding emails, are
    included; the attribution window has to exclude them.
  - Sessions from visitors who never convert.
"""

import csv
import os
import random
from datetime import datetime, timedelta

random.seed(11)

SEEDS = "seeds"
END = datetime(2026, 9, 30, 23, 59, 59)
FMT = "%Y-%m-%d %H:%M:%S"

LANDING_PAGE = {"free_trial": "/signup", "talk_to_sales": "/contact-sales",
                "working_session": "/new-product/working-session"}

GOOGLE_PLG = ["18234567802", "18234567804", "18234567805"]
META_PLG = ["120210000000001", "120210000000002", "120210000000004"]

# Pre-lead touch options by journey type: (weight, source, medium, campaign ids, landing page)
PRE_LEAD = {
    "core_plg": [
        (0.30, "meta", "paid_social", META_PLG, "/"),
        (0.25, "google", "organic", [""], "/blog"),
        (0.18, "", "", [""], "/"),
        (0.10, "g2.com", "referral", [""], "/compare"),
        (0.12, "google", "cpc", GOOGLE_PLG, "/pricing"),
        (0.05, "newsletter", "email", [""], "/blog"),
    ],
    "core_slg": [
        (0.30, "linkedin", "paid_social", ["612345003"], "/customers"),
        (0.20, "google", "organic", [""], "/blog"),
        (0.15, "g2.com", "referral", [""], "/compare"),
        (0.12, "", "", [""], "/"),
        (0.08, "facebook", "paid_social", ["120210000000003"], "/"),
        (0.10, "google", "cpc", ["18234567803"], "/pricing"),
        (0.05, "newsletter", "email", [""], "/blog"),
    ],
    "new_product_slg": [
        (0.45, "linkedin", "paid_social", ["612345001", "612345002"], "/new-product"),
        (0.12, "google", "organic", [""], "/blog"),
        (0.13, "", "", [""], "/"),
        (0.08, "g2.com", "referral", [""], "/compare"),
        (0.12, "newsletter", "email", [""], "/new-product"),
        (0.10, "linkedin", "paid_social", ["612345003"], "/customers"),
    ],
}

# Number of visits before the lead, and how far back they go (days).
PRE_LEAD_COUNT = {
    "core_plg": [(0, 0.40), (1, 0.33), (2, 0.17), (3, 0.10)],
    "core_slg": [(0, 0.15), (1, 0.30), (2, 0.30), (3, 0.15), (4, 0.10)],
    "new_product_slg": [(1, 0.20), (2, 0.30), (3, 0.25), (4, 0.15), (5, 0.10)],
}
LOOKBACK_DAYS = {"core_plg": 30, "core_slg": 45, "new_product_slg": 60}

# Identified web visits between lead and opportunity (SLG nurture).
NURTURE_WEB = [
    (0.50, "", "", [""], "/"),
    (0.25, "google", "organic", [""], "/docs"),
    (0.25, "linkedin", "paid_social", ["612345003"], "/customers"),
]

# Visitors who never convert.
NOISE = [
    (0.30, "google", "organic", [""], "/blog"),
    (0.20, "", "", [""], "/"),
    (0.15, "meta", "paid_social", META_PLG, "/"),
    (0.12, "google", "cpc", GOOGLE_PLG + ["18234567801", "18234567803"], "/pricing"),
    (0.10, "linkedin", "paid_social", ["612345001", "612345002", "612345003"], "/customers"),
    (0.08, "g2.com", "referral", [""], "/compare"),
    (0.05, "bing", "organic", [""], "/blog"),
]
NOISE_PER_DAY = 85

MESSY_SOURCE = {"linkedin": "LinkedIn", "google": "Google ", "facebook": "Facebook", "meta": "Meta"}


def weighted(options, idx=0):
    r, acc = random.random(), 0.0
    for o in options:
        acc += o[idx]
        if r <= acc:
            return o
    return options[-1]


def count_from(dist):
    r, acc = random.random(), 0.0
    for n, w in dist:
        acc += w
        if r <= acc:
            return n
    return dist[-1][0]


def new_pseudo_id():
    return f"{random.getrandbits(32):010d}.{random.randint(1700000000, 1790000000)}"


def messy(source):
    """Return the source with inconsistent casing or a trailing space about 6% of the time."""
    if source in MESSY_SOURCE and random.random() < 0.06:
        return MESSY_SOURCE[source]
    return source


def main():
    with open(os.path.join(SEEDS, "leads.csv")) as fh:
        leads = list(csv.DictReader(fh))
    opp_at = {}
    with open(os.path.join(SEEDS, "funnel_events.csv")) as fh:
        for r in csv.DictReader(fh):
            if r["stage"] == "opportunity_created":
                opp_at[r["lead_id"]] = datetime.strptime(r["event_ts"], FMT)

    sessions, identities, activities = [], [], []
    counters = {"s": 0, "a": 0}

    def add_session(pseudo_id, t, source, medium, campaign, page):
        if t > END:
            return
        counters["s"] += 1
        sessions.append({
            "session_id": f"S{counters['s']:07d}", "user_pseudo_id": pseudo_id,
            "session_start_ts": t.strftime(FMT), "source": messy(source), "medium": medium,
            "campaign": campaign, "landing_page": page,
            "device_category": random.choices(["desktop", "mobile", "tablet"], [0.72, 0.25, 0.03])[0],
        })

    def add_activity(lead_id, t, activity_type, program, channel):
        if t > END:
            return
        counters["a"] += 1
        row = {"activity_id": f"A{counters['a']:07d}", "lead_id": lead_id,
               "activity_type": activity_type, "activity_ts": t.strftime(FMT),
               "program_name": program, "program_channel": channel}
        activities.append(row)
        if random.random() < 0.02:
            activities.append(dict(row))  # duplicate export row

    for lead in leads:
        lid = lead["lead_id"]
        created = datetime.strptime(lead["created_ts"], FMT)
        journey = f"{lead['product_line']}_{lead['motion']}"
        product = "New Product" if lead["product_line"] == "new_product" else "Core"
        tracked = random.random() >= 0.08
        main_id = new_pseudo_id()

        # Earlier anonymous visits.
        n_pre = count_from(PRE_LEAD_COUNT[journey])
        offsets = sorted((random.uniform(0.5, LOOKBACK_DAYS[journey]) for _ in range(n_pre)), reverse=True)
        for days in offsets:
            _, source, medium, campaigns, page = weighted(PRE_LEAD[journey])
            second_device = random.random() < 0.15
            pid = new_pseudo_id() if second_device or not tracked else main_id
            add_session(pid, created - timedelta(days=days), source, medium,
                        random.choice(campaigns), page)

        # The visit where the form was submitted, and the identity it creates.
        if tracked:
            add_session(main_id, created - timedelta(minutes=random.uniform(1, 20)),
                        lead["utm_source"], lead["utm_medium"], lead["utm_campaign"],
                        LANDING_PAGE[lead["landing_form"]])
            identities.append({"user_pseudo_id": main_id, "lead_id": lid,
                               "identified_ts": created.strftime(FMT)})

        if lead["motion"] == "plg":
            # Onboarding emails after the trial starts. Outside the attribution window.
            for _ in range(count_from([(0, 0.3), (1, 0.3), (2, 0.25), (3, 0.15)])):
                add_activity(lid, created + timedelta(days=random.uniform(0.5, 14)),
                             "email_clicked", "Onboarding - Trial", "email")
            continue

        # SLG nurture between lead creation and opportunity (or 30 days if no opportunity).
        window_end = opp_at.get(lid, created + timedelta(days=30))
        span = max((window_end - created).total_seconds(), 3600)

        def in_window():
            return created + timedelta(seconds=random.uniform(600, span - 60))

        for _ in range(count_from([(0, 0.30), (1, 0.35), (2, 0.20), (3, 0.15)])):
            add_activity(lid, in_window(), "email_clicked", f"Nurture - {product}", "email")
        if random.random() < (0.35 if product == "New Product" else 0.20):
            add_activity(lid, in_window(), "webinar_attended", f"Webinar - {product} Live Demo", "webinar")
        if tracked:
            for _ in range(count_from([(0, 0.40), (1, 0.35), (2, 0.25)])):
                _, source, medium, campaigns, page = weighted(NURTURE_WEB)
                add_session(main_id, in_window(), source, medium, random.choice(campaigns), page)

        # Touches after the opportunity opens. Outside the attribution window.
        if lid in opp_at:
            for _ in range(random.randint(0, 2)):
                add_activity(lid, opp_at[lid] + timedelta(days=random.uniform(1, 20)),
                             "email_clicked", f"Nurture - {product}", "email")

    # Visitors who never convert.
    day = datetime(2026, 5, 3)
    while day <= END:
        for _ in range(NOISE_PER_DAY + random.randint(-15, 15)):
            _, source, medium, campaigns, page = weighted(NOISE)
            add_session(new_pseudo_id(), day + timedelta(seconds=random.randint(0, 86399)),
                        source, medium, random.choice(campaigns), page)
        day += timedelta(days=1)

    sessions.sort(key=lambda r: r["session_start_ts"])
    activities.sort(key=lambda r: r["activity_ts"])
    for name, rows in (("web_sessions.csv", sessions), ("web_identities.csv", identities),
                       ("marketo_activities.csv", activities)):
        with open(os.path.join(SEEDS, name), "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {name}: {len(rows):,} rows")


if __name__ == "__main__":
    main()
