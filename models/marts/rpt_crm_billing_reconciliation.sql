-- Does billing match what the CRM says was won? One row per lead won Jul-Sep 2026 (closed-won
-- deals and trial conversions), comparing CRM won ARR to the ARR on the customer's first
-- invoice. CRM ARR is list price; billing is net of coupons and the annual-plan discount, so
-- self-serve gaps carry a reason. Sales-led gaps mean the contract changed after the
-- opportunity closed, or the deal hasn't been invoiced yet; both need a RevOps follow-up.
with won as (
    select lead_id, motion, product_line, won_at, won_arr
    from {{ ref('fct_leads') }}
    where is_won
),

workspaces as (
    select workspace_id, lead_id, stripe_customer_id
    from {{ ref('int_workspaces__channel_classified') }}
    where lead_id is not null
),

lines as (
    select * from {{ ref('int_billing__line_item_mrr') }}
),

first_period as (
    select workspace_id, min(period_start_ts) as first_period_start_ts
    from lines
    group by 1
),

first_invoice as (
    select
        l.workspace_id,
        sum(l.mrr) * 12             as billed_arr,
        sum(l.list_mrr) * 12        as billed_list_arr,
        sum(l.discount_usd)         as discount_usd,
        max(l.billing_interval)     as billing_interval
    from lines l
    join first_period f
        on  l.workspace_id    = f.workspace_id
        and l.period_start_ts = f.first_period_start_ts
    group by 1
)

select
    w.lead_id,
    w.workspace_id                                      as customer_id,
    w.motion,
    w.product_line,
    w.won_at,
    round(w.won_arr, 2)                                 as crm_won_arr,
    round(i.billed_arr, 2)                              as billed_arr,
    round(i.billed_arr - w.won_arr, 2)                  as arr_difference,
    case
        when i.workspace_id is null                             then 'not_billed'
        when abs(i.billed_arr - w.won_arr) < 1                  then 'matched'
        when w.motion = 'plg' and i.discount_usd > 0            then 'promo_discount'
        when w.motion = 'plg' and i.billing_interval = 'year'   then 'annual_plan_discount'
        when i.billed_arr < w.won_arr                           then 'billed_below_crm'
        else 'billed_above_crm'
    end                                                 as reconciliation_status
from (
    select won.*, ws.workspace_id
    from won
    left join workspaces ws on won.lead_id = ws.lead_id
) w
left join first_invoice i
    on w.workspace_id = i.workspace_id
