"""
Generate synthetic Salesforce CRM seeds (plus trial events from the product database) for the
paid_media_mart project. Replaces the flat leads.csv / funnel_events.csv export.

Run from the dbt project root, after generate_seeds.py and before generate_touchpoint_seeds.py:
    python scripts/generate_salesforce_seeds.py

Column names follow the Fivetran Salesforce connector (snake_case standard fields, custom
fields ending in __c, is_deleted, _fivetran_synced). Standard library only, fixed random seeds.

The business has two product lines and two motions:
  core         PLG (free trial) and SLG (talk to sales)
  new_product  SLG only (working session request)

Lead volume and funnel rates are generated exactly as before (same random seed and call order),
so lead counts, pipeline, and won ARR match the earlier funnel layer. A second random stream
adds what a real CRM has on top: accounts, contacts, opportunity stage history, buying
committees, and campaign membership.

Objects written to seeds/:
  sf_lead                       every form fill and trial signup, with UTM and SQL date fields
  sf_account, sf_contact        created when a sales-led lead converts to an opportunity
  sf_opportunity                one per converted lead; campaign_id is the primary campaign source
  sf_opportunity_history        one row per stage change
  sf_opportunity_contact_role   the converting contact plus other members of the buying committee
  sf_campaign                   one per ad campaign, inbound source, and Marketo program
  sf_campaign_member            form-fill responses here; Marketo program members are added by
                                generate_touchpoint_seeds.py, as Marketo's CRM sync would
  app_trial_events              trial started, activated, converted to paid (product database)

Built-in messiness, handled in staging:
  - About 1.5% of leads have a merged duplicate (is_deleted = true, master_record_id set).
  - A few test opportunities were created and deleted.
  - Emails are raw PII; staging hashes them and drops the raw value.
Events after END are dropped, so recent cohorts have open pipeline, like a real CRM.
"""

import csv
import os
import random
from datetime import date, datetime, timedelta

random.seed(7)               # Lead volume and funnel outcomes: unchanged from the earlier generator.
crm = random.Random(23)      # Everything Salesforce adds on top.

START = date(2026, 7, 1)
END = date(2026, 9, 30)
END_DT = datetime(END.year, END.month, END.day, 23, 59, 59)
SYNCED = "2026-10-01 06:00:00"
SEEDS = "seeds"
FMT = "%Y-%m-%d %H:%M:%S"

# ---------------------------------------------------------------------------------------------
# Lead volume and funnel outcomes (same logic and random call order as the earlier generator)
# ---------------------------------------------------------------------------------------------

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


def read_campaign_names():
    """Latest ad campaign name per (platform, campaign_id), for Salesforce campaign names."""
    names = {}
    for platform, fname, date_col in (("google", "google_ads_spend.csv", "date"),
                                      ("meta", "meta_ads_spend.csv", "date_start"),
                                      ("linkedin", "linkedin_ads_spend.csv", "day")):
        with open(os.path.join(SEEDS, fname)) as fh:
            for r in sorted(csv.DictReader(fh), key=lambda r: r[date_col]):
                names[(platform, r["campaign_id"])] = r["campaign_name"]
    return names


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


def make_lead(n, d, form, product_line, motion, source, medium, campaign_id, click_id, platform):
    if product_line == "core":
        band = pick(CORE_BANDS)
        segment_type, segment = "monthly_expenses", band[0]
    else:
        band = pick(NEW_PRODUCT_BANDS)
        segment_type, segment = "employees", band[0]
    created = ts(d)
    lead = {
        "n": n, "created": created, "landing_form": form, "product_line": product_line,
        "motion": motion, "utm_source": source, "utm_medium": medium, "utm_campaign": campaign_id,
        "click_id": click_id, "segment_type": segment_type, "segment": segment,
        "ad_platform": platform,
    }
    return lead, band, created


def stages_for(lead, band, created):
    """Walk a lead through its motion's stages; return {stage: (timestamp, amount)} reached by END."""
    out = {}

    def add(stage, t, amount=None):
        if t <= END_DT:
            out[stage] = (t, amount)
            return True
        return False

    if lead["motion"] == "plg":
        add("trial_started", created)
        if random.random() < 0.46:
            t = created + timedelta(days=random.uniform(0.1, 5))
            if add("activated", t) and random.random() < 0.38:
                arr = band[2] * 12
                add("converted_paid", created + timedelta(days=random.uniform(13, 18)), round(arr, 2))
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
    if not add("opportunity_created", t, round(acv, 2)):
        return out
    close = t + timedelta(days=random.uniform(35, 90) if new else random.uniform(14, 50))
    won = random.random() < (0.26 if new else 0.32)
    # The planned close is kept even when it falls after END: it becomes an open opportunity
    # with an expected close date.
    out["_close"] = (close, round(acv, 2) if won else None, won)
    return out


def generate_leads():
    spend = read_daily_spend()
    mapping = read_campaign_mapping()
    leads, n = [], 0

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
                lead, band, created = make_lead(n, d, m["landing_form"], m["product_line"],
                                                m["motion"], source, medium, cid, gclid, platform)
                lead["stages"] = stages_for(lead, band, created)
                leads.append(lead)
        # Non-paid leads.
        for form, sources in ORGANIC_DAILY.items():
            product_line = "new_product" if form == "working_session" else "core"
            motion = "plg" if form == "free_trial" else "slg"
            for source, medium, rate in sources:
                for _ in range(poisson(rate)):
                    n += 1
                    lead, band, created = make_lead(n, d, form, product_line, motion,
                                                    source, medium, "", "", "")
                    lead["stages"] = stages_for(lead, band, created)
                    leads.append(lead)
        d += timedelta(days=1)
    return leads


# ---------------------------------------------------------------------------------------------
# Salesforce objects
# ---------------------------------------------------------------------------------------------

def sfid(prefix, n):
    """18-character Salesforce-style ID: 3-character object prefix, then a sequence."""
    return f"{prefix}8c{n:010d}QAB"


def fmt(t):
    return t.strftime(FMT) if t else ""


LEAD_SOURCE = {"free_trial": "Free Trial", "talk_to_sales": "Talk to Sales",
               "working_session": "Working Session"}
PRODUCT_INTEREST = {"core": "Core", "new_product": "New Product"}
CANONICAL_UTM = {"google": ("google", "cpc"), "meta": ("meta", "paid_social"),
                 "linkedin": ("linkedin", "paid_social")}
CAMPAIGN_TYPE = {"google": "Paid Search", "meta": "Paid Social", "linkedin": "Paid Social"}

# Inbound campaigns: non-paid leads respond to one of these (a common "website inbound" setup),
# so every lead and every opportunity has a primary campaign source.
INBOUND = [
    ("Inbound - Organic Search", "Website", "google", "organic", {("google", "organic"), ("bing", "organic")}),
    ("Inbound - Direct", "Website", "", "", {("", "")}),
    ("Inbound - Review Sites", "Referral", "g2.com", "referral", {("g2.com", "referral")}),
    ("Newsletter", "Email", "newsletter", "email", {("newsletter", "email")}),
]
# Marketo programs synced to Salesforce campaigns.
PROGRAMS = [
    ("Nurture - Core", "Email", "email"),
    ("Nurture - New Product", "Email", "email"),
    ("Onboarding - Trial", "Email", "email"),
    ("Webinar - Core Live Demo", "Webinar", "webinar"),
    ("Webinar - New Product Live Demo", "Webinar", "webinar"),
]

OPP_STAGES = [("Discovery", 10), ("Evaluation", 30), ("Proposal", 60), ("Negotiation", 80)]
# Where a lost opportunity drops out (index into OPP_STAGES).
LOST_AT = [(0, 0.35), (1, 0.30), (2, 0.25), (3, 0.10)]
CONTACT_ROLES = ["Decision Maker", "Economic Buyer", "Evaluator", "Technical Buyer", "Influencer"]
TITLES = ["Controller", "VP Finance", "CFO", "Head of Operations", "Founder", "Data Lead",
          "Finance Manager", "COO"]
INDUSTRIES = ["Software", "Ecommerce", "Healthcare", "Financial Services", "Media", "Manufacturing"]

# Buying committee members (contacts besides the one who converted) who engaged with marketing.
# Weights per committee member: (weight, campaign key, days before the opportunity it happens).
COMMITTEE_TOUCH = {
    "core": [(0.40, None, 0), (0.18, "prog:Webinar - Core Live Demo", 45),
             (0.15, "ad:linkedin:612345003", 40), (0.12, "prog:Nurture - Core", 60),
             (0.10, "inbound:Inbound - Review Sites", 75), (0.05, "ad:google:18234567803", 30)],
    "new_product": [(0.30, None, 0), (0.25, "prog:Webinar - New Product Live Demo", 50),
                    (0.25, "ad:linkedin:612345001", 60), (0.10, "ad:linkedin:612345002", 60),
                    (0.10, "prog:Nurture - New Product", 70)],
}


def weighted(rng, options):
    r, acc = rng.random(), 0.0
    for opt in options:
        acc += opt[0]
        if r <= acc:
            return opt
    return options[-1]


def build_campaigns():
    mapping = read_campaign_mapping()
    names = read_campaign_names()
    campaigns, by_key = [], {}
    created = datetime(2026, 4, 1, 9, 0, 0)

    def add(key, name, ctype, utm_source, utm_medium, platform="", ad_id="", product=""):
        cid = sfid("701", len(campaigns) + 1)
        campaigns.append({
            "id": cid, "name": name, "type": ctype, "status": "In Progress", "is_active": "true",
            "start_date": "2026-04-01", "parent_id": "", "product_line__c": product,
            "utm_source__c": utm_source, "utm_medium__c": utm_medium,
            "ad_platform__c": platform, "ad_campaign_id__c": ad_id,
            "created_date": fmt(created), "is_deleted": "false", "_fivetran_synced": SYNCED,
        })
        by_key[key] = cid

    for (platform, ad_id), m in mapping.items():
        source, medium = CANONICAL_UTM[platform]
        add(f"ad:{platform}:{ad_id}", names.get((platform, ad_id), f"{platform} {ad_id}"),
            CAMPAIGN_TYPE[platform], source, medium, platform, ad_id, m["product_line"])
    for name, ctype, source, medium, _ in INBOUND:
        add(f"inbound:{name}", name, ctype, source, medium)
    for name, ctype, medium in PROGRAMS:
        product = "new_product" if "New Product" in name else "core"
        add(f"prog:{name}", name, ctype, "marketo", medium, product=product)
    return campaigns, by_key


def inbound_key(source, medium):
    for name, _, _, _, pairs in INBOUND:
        if (source, medium) in pairs:
            return f"inbound:{name}"
    raise ValueError(f"no inbound campaign for {source}/{medium}")


def main():
    leads = generate_leads()
    campaigns, campaign_id = build_campaigns()

    sf_lead, sf_account, sf_contact, sf_opp, sf_hist = [], [], [], [], []
    sf_ocr, sf_member, trial_events = [], [], []
    counters = {k: 0 for k in ("acct", "contact", "opp", "hist", "ocr", "member", "trial", "dup")}

    def next_id(kind, prefix):
        counters[kind] += 1
        return sfid(prefix, counters[kind])

    def add_member(campaign_key, responded, lead_id="", contact_id=""):
        sf_member.append({
            "id": next_id("member", "00v"), "campaign_id": campaign_id[campaign_key],
            "lead_id": lead_id, "contact_id": contact_id, "status": "Responded",
            "has_responded": "true", "first_responded_date": fmt(responded),
            "created_date": fmt(responded), "is_deleted": "false", "_fivetran_synced": SYNCED,
        })

    for lead in leads:
        lead_id = sfid("00Q", lead["n"])
        stages = lead["stages"]
        created = lead["created"]
        company = f"Company {crm.randint(1000, 99999)}"
        domain = company.lower().replace(" ", "") + ".example.com"
        email = f"person{lead['n']}@{domain}"
        form_campaign = (f"ad:{lead['ad_platform']}:{lead['utm_campaign']}" if lead["ad_platform"]
                         else inbound_key(lead["utm_source"], lead["utm_medium"]))

        row = {
            "id": lead_id, "is_deleted": "false", "master_record_id": "",
            "created_date": fmt(created), "email": email, "company": company, "title": crm.choice(TITLES),
            "lead_source": LEAD_SOURCE[lead["landing_form"]],
            "status": "", "product_interest__c": PRODUCT_INTEREST[lead["product_line"]],
            "segment_type__c": lead["segment_type"], "segment__c": lead["segment"],
            "utm_source__c": lead["utm_source"], "utm_medium__c": lead["utm_medium"],
            "utm_campaign__c": lead["utm_campaign"], "gclid__c": lead["click_id"],
            "meeting_booked_date__c": "", "meeting_held_date__c": "",
            "is_converted": "false", "converted_date": "", "converted_account_id": "",
            "converted_contact_id": "", "converted_opportunity_id": "",
            "_fivetran_synced": SYNCED,
        }
        add_member(form_campaign, created, lead_id=lead_id)

        if lead["motion"] == "plg":
            row["status"] = "Trial"
            for stage in ("trial_started", "activated", "converted_paid"):
                if stage in stages:
                    t, amount = stages[stage]
                    trial_events.append({
                        "event_id": next_id("trial", "TE"), "sfdc_lead_id": lead_id,
                        "event_type": stage, "event_ts": fmt(t),
                        "arr": f"{amount:.2f}" if amount is not None else "",
                    })
            if "converted_paid" in stages:
                row["status"] = "Customer"
        else:
            row["status"] = "Open"
            if "meeting_booked" in stages:
                row["status"] = "Meeting Booked"
                row["meeting_booked_date__c"] = fmt(stages["meeting_booked"][0])
            if "meeting_held" in stages:
                row["status"] = "Qualified"
                row["meeting_held_date__c"] = fmt(stages["meeting_held"][0])
            elif "meeting_booked" in stages and stages["meeting_booked"][0] < END_DT - timedelta(days=10):
                row["status"] = "Disqualified"

        if "opportunity_created" in stages:
            opp_created, amount = stages["opportunity_created"]
            close, won_amount, won = stages["_close"]
            account_id = next_id("acct", "001")
            contact_id = next_id("contact", "003")
            opp_id = next_id("opp", "006")
            product = lead["product_line"]
            row.update({"status": "Converted", "is_converted": "true",
                        "converted_date": opp_created.strftime("%Y-%m-%d"),
                        "converted_account_id": account_id, "converted_contact_id": contact_id,
                        "converted_opportunity_id": opp_id})

            employees = {"2-10": 6, "11-50": 30, "51-200": 120, "201+": 400}.get(lead["segment"])
            sf_account.append({
                "id": account_id, "name": company, "website": domain,
                "industry": crm.choice(INDUSTRIES),
                "number_of_employees": employees or crm.randint(5, 300),
                "segment__c": lead["segment"], "type": "Prospect",
                "created_date": fmt(opp_created), "is_deleted": "false", "_fivetran_synced": SYNCED,
            })
            sf_contact.append({
                "id": contact_id, "account_id": account_id, "email": email, "title": row["title"],
                "lead_source": row["lead_source"], "created_date": fmt(opp_created),
                "is_deleted": "false", "_fivetran_synced": SYNCED,
            })
            # Salesforce moves the lead's campaign membership onto the new contact.
            sf_member[-1]["contact_id"] = contact_id

            # Stage history: open at Discovery; won deals pass every stage, lost deals drop
            # out partway; open deals stop wherever END falls.
            span = (close - opp_created).total_seconds()
            if won:
                last_open = len(OPP_STAGES) - 1
            else:
                last_open = weighted(crm, [(w, i) for i, w in LOST_AT])[1]
            fractions = sorted(crm.uniform(0.05, 0.9) for _ in range(last_open))
            stage_times = [opp_created] + [opp_created + timedelta(seconds=span * f) for f in fractions]
            current_stage, prob = OPP_STAGES[0]
            for (stage, p), t in zip(OPP_STAGES, stage_times):
                if t > END_DT:
                    break
                current_stage, prob = stage, p
                sf_hist.append({
                    "id": next_id("hist", "008"), "opportunity_id": opp_id, "created_date": fmt(t),
                    "stage_name": stage, "amount": f"{amount:.2f}", "probability": p,
                    "close_date": close.strftime("%Y-%m-%d"), "is_deleted": "false",
                    "_fivetran_synced": SYNCED,
                })
            is_closed = close <= END_DT
            if is_closed:
                current_stage, prob = ("Closed Won", 100) if won else ("Closed Lost", 0)
                sf_hist.append({
                    "id": next_id("hist", "008"), "opportunity_id": opp_id, "created_date": fmt(close),
                    "stage_name": current_stage, "amount": f"{amount:.2f}", "probability": prob,
                    "close_date": close.strftime("%Y-%m-%d"), "is_deleted": "false",
                    "_fivetran_synced": SYNCED,
                })
            sf_opp.append({
                "id": opp_id, "account_id": account_id, "name": f"{company} - {PRODUCT_INTEREST[product]}",
                "type": "New Business", "lead_source": row["lead_source"],
                "campaign_id": campaign_id[form_campaign], "amount": f"{amount:.2f}",
                "stage_name": current_stage, "probability": prob,
                "created_date": fmt(opp_created), "close_date": close.strftime("%Y-%m-%d"),
                "is_closed": str(is_closed).lower(), "is_won": str(is_closed and won).lower(),
                "forecast_category": ("Closed" if current_stage == "Closed Won" else
                                      "Omitted" if current_stage == "Closed Lost" else
                                      "Commit" if prob >= 80 else "Pipeline"),
                "product_line__c": product, "is_deleted": "false", "_fivetran_synced": SYNCED,
            })

            # Buying committee: the converting contact plus 0 to 3 colleagues.
            roles = crm.sample(CONTACT_ROLES, 4)
            sf_ocr.append({"id": next_id("ocr", "00K"), "opportunity_id": opp_id, "contact_id": contact_id,
                           "role": roles[0], "is_primary": "true", "created_date": fmt(opp_created),
                           "is_deleted": "false", "_fivetran_synced": SYNCED})
            n_colleagues = crm.choices([0, 1, 2, 3], [0.25, 0.35, 0.25, 0.15])[0]
            if product == "new_product":
                n_colleagues = min(3, n_colleagues + 1)
            for role in roles[1:1 + n_colleagues]:
                colleague = next_id("contact", "003")
                sf_contact.append({
                    "id": colleague, "account_id": account_id,
                    "email": f"colleague{counters['contact']}@{domain}", "title": crm.choice(TITLES),
                    "lead_source": "", "created_date": fmt(opp_created),
                    "is_deleted": "false", "_fivetran_synced": SYNCED,
                })
                sf_ocr.append({"id": next_id("ocr", "00K"), "opportunity_id": opp_id, "contact_id": colleague,
                               "role": role, "is_primary": "false", "created_date": fmt(opp_created),
                               "is_deleted": "false", "_fivetran_synced": SYNCED})
                _, key, max_days = weighted(crm, COMMITTEE_TOUCH[product])
                if key:
                    # Mostly before the opportunity; about 15% after, which influence must exclude.
                    if crm.random() < 0.15:
                        t = opp_created + timedelta(days=crm.uniform(1, 20))
                    else:
                        t = opp_created - timedelta(days=crm.uniform(0.5, max_days))
                    if t <= END_DT:
                        add_member(key, t, contact_id=colleague)

        sf_lead.append(row)

        # Merged duplicates: the same person submits again; the duplicate is merged into the
        # original, so Salesforce soft-deletes it and points it at the master record.
        if crm.random() < 0.015:
            counters["dup"] += 1
            dup = dict(row)
            dup.update({
                "id": sfid("00Q", 900000 + counters["dup"]), "is_deleted": "true",
                "master_record_id": lead_id,
                "created_date": fmt(created + timedelta(hours=crm.uniform(1, 72))),
                "status": "Open", "is_converted": "false", "converted_date": "",
                "converted_account_id": "", "converted_contact_id": "", "converted_opportunity_id": "",
                "meeting_booked_date__c": "", "meeting_held_date__c": "",
            })
            sf_lead.append(dup)

    # Test opportunities created by hand and deleted.
    for i in range(3):
        sf_opp.append({
            "id": next_id("opp", "006"), "account_id": "", "name": f"TEST - do not use {i + 1}",
            "type": "New Business", "lead_source": "", "campaign_id": "", "amount": "1.00",
            "stage_name": "Discovery", "probability": 10, "created_date": fmt(datetime(2026, 8, 3 + i, 12)),
            "close_date": "2026-12-31", "is_closed": "false", "is_won": "false",
            "forecast_category": "Pipeline", "product_line__c": "core", "is_deleted": "true",
            "_fivetran_synced": SYNCED,
        })

    outputs = [
        ("sf_lead.csv", sf_lead), ("sf_account.csv", sf_account), ("sf_contact.csv", sf_contact),
        ("sf_opportunity.csv", sf_opp), ("sf_opportunity_history.csv", sf_hist),
        ("sf_opportunity_contact_role.csv", sf_ocr), ("sf_campaign.csv", campaigns),
        ("sf_campaign_member.csv", sf_member), ("app_trial_events.csv", trial_events),
    ]
    for name, rows in outputs:
        with open(os.path.join(SEEDS, name), "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {name}: {len(rows):,} rows")


if __name__ == "__main__":
    main()
