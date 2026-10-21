"""
Generate synthetic billing (Stripe) and product usage seeds for the paid_media_mart project.

Run from the dbt project root, after generate_salesforce_seeds.py:
    python scripts/generate_billing_seeds.py

Tables are shaped the way the Fivetran Stripe connector lands them (amounts in cents, one table
per object, invoice status on the invoice and service periods on the line item). Product
tables come from the application database. Standard library only, fixed random seed. Reads the
CRM seeds but never changes them, so every existing model and report is unaffected.

Customers come from two places:
  - In-window: every trial that converted to paid (app_trial_events) and every closed-won
    opportunity (sf_opportunity) from Jul 1 to Sep 30, 2026. Their workspaces carry the lead's
    UTMs and Salesforce IDs, so billing links back to the CRM funnel.
  - Legacy: customers acquired Oct 2024 to Jun 2026, before Salesforce went live in July 2026.
    They exist only in billing and the product database, which is why the revenue layer keys
    on the workspace, not the Salesforce account.

Pricing:
  core         self-serve (PLG) tiers by monthly expense band, billed monthly, or yearly at a
               20% discount; sales-led (SLG) customers sign annual contracts at a custom price
  new_product  annual contracts only: new logos from Jan 2026 and cross-sell to core customers

Behavior built into the simulation (what the revenue layer should be able to find):
  - Each customer has an engagement level that drifts month to month. It drives usage, tier
    upgrades and downgrades, cross-sell, and voluntary churn, so falling usage precedes churn.
  - Failed payments cause involuntary churn at a flat rate unrelated to engagement.
  - Acquisition channel shifts baseline engagement (referral and organic retain best, Meta
    worst), and a 50%-off-for-3-months coupon used mostly on Meta traffic adds churn when it ends.
  - Sales-led renewals carry list price uplifts, scope expansion, and some contraction.

Built-in messiness, handled in the models:
  - Annual invoices bill 12 months at once (must be spread to monthly MRR).
  - Mid-cycle plan changes create proration line items (one-off true-ups, not recurring revenue).
  - About 1% of invoices were voided and reissued, leaving duplicate line items on a void invoice.
  - Final invoices of failed-payment customers are marked uncollectible.
  - A few internal QA customers bill real invoices.
  - UTMs in the product database have the same casing and blank-value issues as the CRM.
  - Two closed-won deals were invoiced at a different amount than Salesforce, and the last
    deal of the quarter has a workspace but no invoice yet.

Objects written to seeds/:
  stripe_products, stripe_prices, stripe_customers, stripe_subscriptions,
  stripe_invoices, stripe_invoice_line_items          billing
  app_workspaces, app_workspace_usage_monthly         product database
"""

import csv
import math
import os
import random
import string
from datetime import date, datetime, timedelta

random.seed(42)
ids = random.Random(4242)     # Separate stream for IDs so changing behavior doesn't reshuffle keys.

SEEDS = "seeds"
FMT = "%Y-%m-%d %H:%M:%S"
BILLING_START = date(2024, 10, 1)
CRM_START = date(2026, 7, 1)
NEW_PRODUCT_LAUNCH = date(2026, 1, 1)
END = date(2026, 9, 30)
END_DT = datetime(2026, 9, 30, 23, 59, 59)
SYNCED = "2026-10-01 06:00:00"

# Core self-serve tiers, in the same order as the CRM's monthly expense bands.
TIERS = [("starter", "<15k", 99), ("growth", "15k-60k", 349), ("scale", "60k-200k", 799),
         ("pro", "200k-500k", 1499), ("premium", "500k+", 2999)]
TIER_BY_ARR = {t[2] * 12: i for i, t in enumerate(TIERS)}
TIER_MIX = [0.38, 0.31, 0.16, 0.09, 0.06]          # Matches the in-window PLG conversion mix.
ANNUAL_DISCOUNT = 0.20
SLG_ACV = [("<15k", 0.35, 6000), ("15k-60k", 0.30, 15000), ("60k-200k", 0.20, 36000),
           ("200k-500k", 0.10, 75000), ("500k+", 0.05, 120000)]
NEW_PRODUCT_ACV = [("2-10", 0.30, 30000), ("11-50", 0.40, 60000), ("51-200", 0.22, 110000),
                   ("201+", 0.08, 180000)]

# Baseline engagement shift by acquisition channel.
CHANNEL_ENGAGEMENT = {"Paid Search": -0.10, "Paid Social - Meta": -0.40, "Paid Social - LinkedIn": 0.10,
                      "Organic Search": 0.20, "Direct": 0.10, "Referral": 0.35, "Email": 0.0,
                      "Events": 0.1, "Other": 0.0}
LEGACY_UTMS = {
    "Paid Search": [("google", "cpc"), ("google", "paid_search"), ("Google ", "cpc")],
    "Paid Social - Meta": [("facebook", "paid_social"), ("meta", "paid_social"), ("instagram", "paid_social")],
    "Paid Social - LinkedIn": [("linkedin", "paid_social"), ("li", "paid_social")],
    "Organic Search": [("google", "organic"), ("bing", "organic")],
    "Direct": [("", "")],
    "Referral": [("g2.com", "referral"), ("capterra.com", "referral")],
    "Email": [("newsletter", "email")],
}
PLG_CHANNEL_MIX = [("Paid Search", 0.40), ("Paid Social - Meta", 0.24), ("Organic Search", 0.16),
                   ("Direct", 0.12), ("Referral", 0.05), ("Email", 0.03)]
SLG_CHANNEL_MIX = [("Direct", 0.26), ("Paid Search", 0.22), ("Paid Social - LinkedIn", 0.18),
                   ("Organic Search", 0.12), ("Email", 0.10), ("Referral", 0.08), ("Paid Social - Meta", 0.04)]

PLG_CHURN = [0.032, 0.024, 0.018, 0.014, 0.012]     # Monthly voluntary churn hazard by tier.
INVOLUNTARY = 0.008                                 # Monthly failed-payment churn, any engagement.
USERS_BY_TIER = [2, 4, 8, 15, 30]

CORE_PRODUCT, NEW_PRODUCT = "prod_core", "prod_newproduct"


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

def sid(prefix, n=14, used=set()):
    while True:
        s = prefix + "".join(ids.choice(string.ascii_letters + string.digits) for _ in range(n))
        if s not in used:
            used.add(s)
            return s


def add_months(dt, k):
    """Same day k months later, clamped to month end (Stripe's billing anchor behavior)."""
    m = dt.month - 1 + k
    y, m = dt.year + m // 12, m % 12 + 1
    last = (date(y + (m == 12), m % 12 + 1, 1) - timedelta(days=1)).day
    return dt.replace(year=y, month=m, day=min(dt.day, last))


def pick(pairs):
    r, acc = random.random(), 0.0
    for item, w in pairs:
        acc += w
        if r <= acc:
            return item
    return pairs[-1][0]


def pick_band(bands):
    return pick([(b, b[1]) for b in bands])


def read(name):
    with open(os.path.join(SEEDS, name)) as fh:
        return list(csv.DictReader(fh))


def channel_of(source, medium, mapping):
    s, m = source.strip().lower(), medium.strip().lower()
    if (s, m) in mapping:
        return mapping[(s, m)]
    if s == "" and m == "":
        return "Direct"
    if m == "referral":
        return "Referral"
    return "Other"


def cents(x):
    return int(round(x * 100))


# ---------------------------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------------------------

products = [
    {"id": CORE_PRODUCT, "name": "Core", "active": "true", "created": "2023-01-10 00:00:00"},
    {"id": NEW_PRODUCT, "name": "New Product", "active": "true", "created": "2025-12-15 00:00:00"},
]
prices = []
LIST_PRICE = {}


def add_price(product_id, nickname, lookup_key, unit_amount_usd, interval, created):
    pid = sid("price_")
    prices.append({
        "id": pid, "product_id": product_id, "nickname": nickname, "lookup_key": lookup_key,
        "unit_amount": cents(unit_amount_usd), "currency": "usd", "recurring_interval": interval,
        "recurring_interval_count": 1, "type": "recurring", "active": "true",
        "created": created, "_fivetran_synced": SYNCED,
    })
    return pid


for i, (tier, _, monthly) in enumerate(TIERS):
    LIST_PRICE[(i, "month")] = add_price(CORE_PRODUCT, f"Core {tier.title()} Monthly",
                                         f"core_{tier}_monthly", monthly, "month", "2023-01-10 00:00:00")
    LIST_PRICE[(i, "year")] = add_price(CORE_PRODUCT, f"Core {tier.title()} Annual",
                                        f"core_{tier}_annual", monthly * 12 * (1 - ANNUAL_DISCOUNT),
                                        "year", "2023-01-10 00:00:00")


def custom_price(product_id, label, acv, created):
    """Sales-led contracts get a one-off price, as Stripe quotes create them (no lookup_key)."""
    return add_price(product_id, label, "", acv, "year", created.strftime(FMT))


# ---------------------------------------------------------------------------------------------
# Customers
# ---------------------------------------------------------------------------------------------

mapping = {(r["utm_source"], r["utm_medium"]): r["channel"] for r in read("channel_mapping.csv")}
leads = {r["id"]: r for r in read("sf_lead.csv") if r["is_deleted"] == "false"}
trial = read("app_trial_events.csv")
opps = [r for r in read("sf_opportunity.csv") if r["is_deleted"] == "false"]
history = read("sf_opportunity_history.csv")

customers = []   # Simulation inputs, one per paying workspace.


def new_customer(start_ts, motion, product_line, channel, utm, **kw):
    c = {"start": start_ts, "motion": motion, "product_line": product_line, "channel": channel,
         "utm_source": utm[0], "utm_medium": utm[1], "utm_campaign": utm[2] if len(utm) > 2 else "",
         "lead_id": "", "account_id": "", "opp_id": "", "promo": False, "interval": "year",
         "tier": None, "acv": None, "segment": "", "segment_type": "", "invoice_override": None}
    c.update(kw)
    customers.append(c)
    return c


# In-window self-serve conversions: tier from the CRM's won ARR.
started = {r["sfdc_lead_id"]: r["event_ts"] for r in trial if r["event_type"] == "trial_started"}
for r in sorted((r for r in trial if r["event_type"] == "converted_paid"), key=lambda r: r["event_ts"]):
    lead = leads[r["sfdc_lead_id"]]
    ch = channel_of(lead["utm_source__c"], lead["utm_medium__c"], mapping)
    tier = TIER_BY_ARR[int(float(r["arr"]))]
    new_customer(datetime.strptime(r["event_ts"], FMT), "plg", "core", ch,
                 (lead["utm_source__c"], lead["utm_medium__c"], lead["utm_campaign__c"]),
                 lead_id=lead["id"], tier=tier, interval="year" if random.random() < 0.20 else "month",
                 promo=random.random() < (0.30 if ch == "Paid Social - Meta" else 0.04),
                 segment=TIERS[tier][1], segment_type="monthly_expenses",
                 workspace_created=started[lead["id"]])

# In-window closed-won deals. Invoice on the close date at the opportunity amount, except the
# planted mismatches and the deal that hasn't been invoiced yet.
closed_at = {}
for h in history:
    if h["stage_name"] == "Closed Won":
        closed_at[h["opportunity_id"]] = min(closed_at.get(h["opportunity_id"], h["created_date"]), h["created_date"])
lead_by_opp = {l["converted_opportunity_id"]: l for l in leads.values() if l["converted_opportunity_id"]}
won = sorted((o for o in opps if o["is_won"] == "true"), key=lambda o: closed_at[o["id"]])
for k, o in enumerate(won):
    lead = lead_by_opp[o["id"]]
    ch = channel_of(lead["utm_source__c"], lead["utm_medium__c"], mapping)
    override = None
    if k == 5:
        override = ("ramp", 0.80)        # Year-one ramp agreed after the opportunity closed.
    elif k == 17:
        override = ("discount", 0.10)    # Extra 10% discount applied in billing, not in Salesforce.
    elif k == len(won) - 1:
        override = ("not_invoiced", None)
    new_customer(datetime.strptime(closed_at[o["id"]], FMT), "slg", o["product_line__c"], ch,
                 (lead["utm_source__c"], lead["utm_medium__c"], lead["utm_campaign__c"]),
                 lead_id=lead["id"], account_id=o["account_id"], opp_id=o["id"], acv=float(o["amount"]),
                 segment=lead["segment__c"], segment_type=lead["segment_type__c"], invoice_override=override,
                 workspace_created=closed_at[o["id"]])


def random_ts(month_start):
    days = (add_months(month_start, 1) - month_start).days
    d = month_start + timedelta(days=random.randrange(days))
    return datetime(d.year, d.month, d.day) + timedelta(seconds=random.randint(28800, 72000))


def legacy_utm(channel):
    s, m = random.choice(LEGACY_UTMS[channel])
    return (s, m, "")


# Legacy customers, Oct 2024 to Jun 2026, with volume growing toward the in-window run rate.
m, idx = BILLING_START, 0
while m < CRM_START:
    for _ in range(round(70 + 4.2 * idx + random.uniform(-6, 6))):
        ch = pick(PLG_CHANNEL_MIX)
        tier = pick(list(zip(range(5), TIER_MIX)))
        new_customer(random_ts(m), "plg", "core", ch, legacy_utm(ch), tier=tier,
                     interval="year" if random.random() < 0.22 else "month",
                     promo=random.random() < (0.30 if ch == "Paid Social - Meta" else 0.04),
                     segment=TIERS[tier][1], segment_type="monthly_expenses")
    for _ in range(round(4 + 0.3 * idx + random.uniform(-1, 1))):
        ch = pick(SLG_CHANNEL_MIX)
        band = pick_band(SLG_ACV)
        new_customer(random_ts(m), "slg", "core", ch, legacy_utm(ch),
                     acv=round(band[2] * random.uniform(0.8, 1.25), 2), segment=band[0],
                     segment_type="monthly_expenses")
    if m >= NEW_PRODUCT_LAUNCH:
        for _ in range(1 if random.random() < 0.8 else 2):
            ch = pick(SLG_CHANNEL_MIX)
            band = pick_band(NEW_PRODUCT_ACV)
            new_customer(random_ts(m), "slg", "new_product", ch, legacy_utm(ch),
                         acv=round(band[2] * random.uniform(0.8, 1.25), 2), segment=band[0],
                         segment_type="employees")
    m, idx = add_months(m, 1), idx + 1

# ---------------------------------------------------------------------------------------------
# Billing simulation
# ---------------------------------------------------------------------------------------------

stripe_customers, subscriptions, invoices, lines, workspaces, usage = [], [], [], [], [], []


def emit_invoice(cust_id, sub_id, created, line_specs, collection, status=None):
    """line_specs: list of (price_id, amount_usd, discount_usd, period_start, period_end, proration)."""
    total = sum(a - d for _, a, d, _, _, _ in line_specs)
    if status is None:
        open_days = 30 if collection == "send_invoice" else 3
        status = "open" if created > END_DT - timedelta(days=open_days) else "paid"
    copies = [status]
    if status == "paid" and random.random() < 0.01:
        copies = ["void", "paid"]         # Voided and reissued: same lines on two invoices.
    for st in copies:
        inv = sid("in_")
        invoices.append({
            "id": inv, "customer_id": cust_id, "subscription_id": sub_id, "status": st,
            "collection_method": collection, "billing_reason": "subscription_cycle",
            "created": created.strftime(FMT), "amount_due": cents(total),
            "amount_paid": cents(total) if st == "paid" else 0, "currency": "usd",
            "_fivetran_synced": SYNCED,
        })
        for price_id, amount, disc, ps, pe, proration in line_specs:
            lines.append({
                "id": sid("il_"), "invoice_id": inv, "subscription_id": sub_id, "price_id": price_id,
                "type": "subscription", "proration": "true" if proration else "false",
                "amount": cents(amount), "discount_amount": cents(disc), "quantity": 1,
                "period_start": ps.strftime(FMT), "period_end": pe.strftime(FMT),
                "_fivetran_synced": SYNCED,
            })


def new_sub(cust_id, start, collection):
    s = {"id": sid("sub_"), "customer_id": cust_id, "status": "active", "collection_method": collection,
         "created": start.strftime(FMT), "start_date": start.strftime(FMT), "canceled_at": "",
         "ended_at": "", "cancel_at_period_end": "false", "cancellation_reason": "",
         "_fivetran_synced": SYNCED}
    subscriptions.append(s)
    return s


def end_sub(s, canceled_at, ended_at, reason, at_period_end):
    s["status"] = "canceled"
    s["canceled_at"] = canceled_at.strftime(FMT)
    s["ended_at"] = ended_at.strftime(FMT)
    s["cancellation_reason"] = reason
    s["cancel_at_period_end"] = "true" if at_period_end else "false"


def tier_price(tier, interval):
    return TIERS[tier][2] * (12 * (1 - ANNUAL_DISCOUNT) if interval == "year" else 1)


def simulate(c, n):
    cust_id = sid("cus_")
    ws_id = f"ws_{n:06d}"
    domain = f"customer{n:05d}.example.com"
    start = c["start"]
    stripe_customers.append({
        "id": cust_id, "email": f"billing@{domain}", "name": f"Customer {n:05d}",
        "created": start.strftime(FMT), "currency": "usd", "delinquent": "false",
        "is_deleted": "false", "_fivetran_synced": SYNCED,
    })
    ws_created = c.get("workspace_created") or (start - timedelta(days=random.uniform(10, 21))).strftime(FMT)
    workspaces.append({
        "workspace_id": ws_id, "workspace_name": f"Customer {n:05d}", "created_at": ws_created,
        "sfdc_lead_id": c["lead_id"], "sfdc_account_id": c["account_id"],
        "stripe_customer_id": "" if c["invoice_override"] and c["invoice_override"][0] == "not_invoiced" else cust_id,
        "signup_utm_source": c["utm_source"], "signup_utm_medium": c["utm_medium"],
        "signup_utm_campaign": c["utm_campaign"], "segment_type": c["segment_type"],
        "segment": c["segment"], "is_internal": "false",
    })
    if c["invoice_override"] and c["invoice_override"][0] == "not_invoiced":
        stripe_customers.pop()
        return

    baseline = random.gauss(0, 0.6) + CHANNEL_ENGAGEMENT.get(c["channel"], 0) + (0.3 if c["motion"] == "slg" else 0) \
        - (0.2 if c["promo"] else 0)
    e = baseline + random.gauss(0, 0.3)
    collection = "send_invoice" if c["motion"] == "slg" else "charge_automatically"
    users_base = USERS_BY_TIER[c["tier"]] if c["tier"] is not None else max(3, (c["acv"] or 20000) / 1500)

    core = c["product_line"] == "core"
    tier, interval = c["tier"], ("month" if c["motion"] == "plg" and c["interval"] == "month" else "year")
    acv = c["acv"]
    core_sub = new_sub(cust_id, start, collection) if core else None
    np_sub, np_acv, np_next = None, None, None
    if not core:
        np_sub, np_acv, np_next = new_sub(cust_id, start, collection), acv, 12
    core_active, np_active = core, not core
    next_core = 0
    reactivate_at = None
    core_price = None

    def core_line(i, ps):
        nonlocal core_price
        pe = add_months(start, i + (12 if interval == "year" else 1))
        if c["motion"] == "plg":
            pid = LIST_PRICE[(tier, interval)]
            amount = tier_price(tier, interval)
            disc = amount * 0.5 if (c["promo"] and interval == "month" and i < 3) else 0.0
        else:
            amount, disc = acv, 0.0
            if i == 0 and c["invoice_override"]:
                kind, x = c["invoice_override"]
                if kind == "ramp":
                    amount = acv * x
                elif kind == "discount":
                    disc = acv * x
            amount = round(amount, 2)
            core_price = custom_price(CORE_PRODUCT, "Core Enterprise - contract", amount, ps)
            pid = core_price
        return (pid, round(amount, 2), round(disc, 2), ps, pe, False)

    def np_line(i, ps):
        pid = custom_price(NEW_PRODUCT, "New Product - contract", np_acv, ps)
        return (pid, round(np_acv, 2), 0.0, ps, add_months(start, i + 12), False)

    i = 0
    while True:
        anchor = add_months(start, i)
        if anchor > END_DT:
            break
        if i > 0:
            e = 0.8 * e + 0.2 * baseline + random.gauss(0, 0.35)
        was_active = core_active or np_active
        h = math.exp(-1.1 * e)

        # Core subscription boundary.
        if core and core_active and i == next_core:
            churn, reason = False, ""
            if i > 0:
                if c["motion"] == "plg" and interval == "month":
                    hz = PLG_CHURN[tier] * h * (2.5 if c["promo"] and i == 3 else 1)
                    if random.random() < hz:
                        churn, reason = True, "cancellation_requested"
                    elif random.random() < INVOLUNTARY:
                        churn, reason = True, "payment_failed"
                elif c["motion"] == "plg":
                    if random.random() < (1 - (1 - PLG_CHURN[tier] * h) ** 12) * 0.75:
                        churn, reason = True, "cancellation_requested"
                else:
                    if random.random() < 0.10 * h:
                        churn, reason = True, "cancellation_requested"
            if churn and reason == "cancellation_requested":
                end_sub(core_sub, anchor - timedelta(days=random.uniform(2, 25)), anchor, reason, True)
                core_active = False
                if c["motion"] == "plg" and interval == "month" and random.random() < 0.06:
                    reactivate_at = i + random.randint(2, 8)
            elif churn:
                # Renewal invoice fails, dunning retries for two weeks, then the subscription ends.
                spec = core_line(i, anchor)
                emit_invoice(cust_id, core_sub["id"], anchor, [spec], collection, status="uncollectible")
                end_sub(core_sub, anchor + timedelta(days=14), anchor + timedelta(days=14), reason, False)
                core_active = False
            else:
                prorations = []
                if i > 0 and c["motion"] == "plg":
                    p_up = (0.022 if interval == "month" else 0.15) * math.exp(0.6 * e)
                    p_dn = (0.008 if interval == "month" else 0.08) * math.exp(-0.6 * e)
                    old = tier
                    if tier < 4 and random.random() < p_up:
                        tier += 1
                    elif tier > 0 and random.random() < p_dn:
                        tier -= 1
                    if tier != old and interval == "month":
                        prev = add_months(start, i - 1)
                        changed = prev + timedelta(days=random.uniform(3, (anchor - prev).days - 2))
                        frac = (anchor - changed) / (anchor - prev)
                        prorations.append((LIST_PRICE[(tier, interval)],
                                           round((TIERS[tier][2] - TIERS[old][2]) * frac, 2), 0.0,
                                           changed, anchor, True))
                elif i > 0:
                    # Sales-led renewal: list uplift, scope expansion, or contraction.
                    r = random.random()
                    if e > 0 and r < 0.30:
                        acv *= random.uniform(1.2, 1.6)
                    elif e < -0.2 and r < 0.25:
                        acv *= random.uniform(0.65, 0.9)
                    elif r < 0.75:
                        acv *= random.uniform(1.05, 1.08)
                    acv = round(acv, 2)
                emit_invoice(cust_id, core_sub["id"], anchor, prorations + [core_line(i, anchor)], collection)
                next_core = i + (12 if interval == "year" else 1)

        # Reactivation of a churned self-serve customer: a new monthly subscription.
        if core and not core_active and reactivate_at == i:
            core_sub = new_sub(cust_id, anchor, collection)
            tier, interval, core_active, reactivate_at = max(0, tier - (random.random() < 0.3)), "month", True, None
            e = baseline
            emit_invoice(cust_id, core_sub["id"], anchor, [core_line(i, anchor)], collection)
            next_core = i + 1

        # New product: renewal of an existing contract, then cross-sell to core customers.
        if np_active and i == np_next:
            if random.random() < 0.12 * math.exp(-0.7 * e) or (core and not core_active):
                end_sub(np_sub, anchor - timedelta(days=random.uniform(5, 30)), anchor, "cancellation_requested", True)
                np_active = False
            else:
                np_acv = round(np_acv * random.uniform(1.0, 1.08), 2)
                emit_invoice(cust_id, np_sub["id"], anchor, [np_line(i, anchor)], collection)
                np_next = i + 12
        if not core and i == 0:
            emit_invoice(cust_id, np_sub["id"], anchor, [np_line(0, anchor)], collection)
        if core and core_active and not np_active and np_sub is None and anchor.date() >= NEW_PRODUCT_LAUNCH \
                and (c["motion"] == "slg" or tier >= 2):
            p = (0.015 if c["motion"] == "slg" else 0.004) * math.exp(0.5 * e)
            if random.random() < p:
                band = NEW_PRODUCT_ACV[0] if c["motion"] == "plg" else pick_band(NEW_PRODUCT_ACV)
                np_acv = round(band[2] * random.uniform(0.35, 0.55), 2)
                np_sub, np_active, np_next = new_sub(cust_id, anchor, "send_invoice"), True, i + 12
                emit_invoice(cust_id, np_sub["id"], anchor, [np_line(i, anchor)], "send_invoice")

        # Product usage for the calendar month of this anchor, if the workspace paid at any point.
        if was_active or core_active or np_active:
            partial = 1.0 if (core_active or np_active) else min(1.0, anchor.day / 30)
            scale = users_base * (USERS_BY_TIER[tier] / USERS_BY_TIER[c["tier"]] if c["tier"] is not None else 1)
            users = max(1, round(scale * math.exp(0.35 * e) * random.uniform(0.85, 1.15)))
            days = min(22.0, max(1.0, 11 + 4 * e + random.gauss(0, 2))) * partial
            usage.append({
                "workspace_id": ws_id,
                "usage_month": date(anchor.year, anchor.month, 1).isoformat(),
                "active_users": users,
                "user_active_days": max(1, round(users * days)),
                "reports_created": max(0, round(users * max(0.0, 1.5 + 1.2 * e + random.gauss(0, 0.6)) * partial)),
                "connected_sources": min(6, max(1, round(2 + e + random.gauss(0, 0.5)))),
            })
        i += 1


for n, c in enumerate(sorted(customers, key=lambda c: c["start"]), start=1):
    simulate(c, n)

# Internal QA workspaces that bill real (small) invoices.
for q in range(1, 5):
    cust_id = sid("cus_")
    start = datetime(2025, 2 + q, 3, 10, 0, 0)
    stripe_customers.append({"id": cust_id, "email": f"qa+{q}@internal.example.com", "name": f"QA Workspace {q}",
                             "created": start.strftime(FMT), "currency": "usd", "delinquent": "false",
                             "is_deleted": "false", "_fivetran_synced": SYNCED})
    workspaces.append({"workspace_id": f"ws_qa{q:03d}", "workspace_name": f"QA Workspace {q}",
                       "created_at": start.strftime(FMT), "sfdc_lead_id": "", "sfdc_account_id": "",
                       "stripe_customer_id": cust_id, "signup_utm_source": "", "signup_utm_medium": "",
                       "signup_utm_campaign": "", "segment_type": "", "segment": "", "is_internal": "true"})
    sub = new_sub(cust_id, start, "charge_automatically")
    k = 0
    while add_months(start, k) <= END_DT:
        a = add_months(start, k)
        emit_invoice(cust_id, sub["id"], a, [(LIST_PRICE[(0, "month")], 99.0, 0.0, a, add_months(start, k + 1), False)],
                     "charge_automatically")
        k += 1

# Trials since the CRM went live that never paid still have workspaces in the product database.
paid_leads = {w["sfdc_lead_id"] for w in workspaces if w["sfdc_lead_id"]}
n = len(customers)
for lead_id, ts in sorted(started.items(), key=lambda kv: kv[1]):
    if lead_id in paid_leads:
        continue
    lead = leads[lead_id]
    n += 1
    workspaces.append({"workspace_id": f"ws_{n:06d}", "workspace_name": lead["company"], "created_at": ts,
                       "sfdc_lead_id": lead_id, "sfdc_account_id": "", "stripe_customer_id": "",
                       "signup_utm_source": lead["utm_source__c"], "signup_utm_medium": lead["utm_medium__c"],
                       "signup_utm_campaign": lead["utm_campaign__c"], "segment_type": lead["segment_type__c"],
                       "segment": lead["segment__c"], "is_internal": "false"})


def write(name, rows):
    with open(os.path.join(SEEDS, name + ".csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"{name}: {len(rows):,} rows")


write("stripe_products", products)
write("stripe_prices", prices)
write("stripe_customers", stripe_customers)
write("stripe_subscriptions", subscriptions)
write("stripe_invoices", sorted(invoices, key=lambda r: r["created"]))
write("stripe_invoice_line_items", lines)
write("app_workspaces", sorted(workspaces, key=lambda r: r["workspace_id"]))
write("app_workspace_usage_monthly", sorted(usage, key=lambda r: (r["workspace_id"], r["usage_month"])))
