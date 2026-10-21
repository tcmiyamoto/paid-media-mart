-- One row per paying workspace (the customer). Keyed on the workspace, not the Salesforce
-- account: customers acquired before Salesforce went live in July 2026 exist only in billing
-- and the product database. Motion comes from billing, since a sales-led contract is billed on
-- a one-off quote price and self-serve customers on list prices.
with workspaces as (
    select * from {{ ref('int_workspaces__channel_classified') }}
),

customer_months as (
    select * from {{ ref('int_customer_mrr_monthly') }}
),

first_lines as (
    select
        workspace_id,
        min(period_start_ts)    as first_period_start_ts
    from {{ ref('int_billing__line_item_mrr') }}
    group by 1
),

first_billing as (
    select
        l.workspace_id,
        max(case when l.is_contract_price then 1 else 0 end) = 1   as is_contract,
        sum(l.discount_usd) > 0                                    as had_first_invoice_discount,
        max(l.billing_interval)                                    as first_billing_interval
    from {{ ref('int_billing__line_item_mrr') }} l
    join first_lines f
        on  l.workspace_id    = f.workspace_id
        and l.period_start_ts = f.first_period_start_ts
    group by 1
),

first_month as (
    select
        workspace_id,
        first_paid_month,
        mrr                                                 as first_mrr,
        case when core_mrr > 0 then 'core' else 'new_product' end as first_product_line,
        core_plan_tier                                      as first_plan_tier
    from customer_months
    where months_since_first_paid = 0
),

lifetime as (
    select
        workspace_id,
        max(case when mrr_month = cast('2026-09-01' as date) then mrr end)              as current_mrr,
        max(case when mrr_month = cast('2026-09-01' as date) then core_plan_tier end)   as current_plan_tier,
        max(case when new_product_mrr > 0 then 1 else 0 end) = 1                       as has_had_new_product,
        sum(case when mrr > 0 then 1 else 0 end)                                       as months_paid,
        max(case when mrr > 0 then mrr_month end)                                      as last_paid_month
    from customer_months
    group by 1
)

select
    w.workspace_id                                                  as customer_id,
    w.stripe_customer_id,
    w.lead_id,
    w.account_id,
    w.created_ts                                                    as workspace_created_ts,
    case when b.is_contract then 'slg' else 'plg' end               as motion,
    f.first_product_line,
    w.segment_type,
    w.segment,
    w.channel                                                       as acquisition_channel,
    {{ dbt_utils.generate_surrogate_key(['w.channel']) }}           as channel_key,
    w.utm_campaign                                                  as acquisition_utm_campaign,
    w.lead_id is not null or w.account_id is not null               as is_linked_to_crm,
    b.had_first_invoice_discount                                    as is_promo_acquired,
    b.first_billing_interval,
    f.first_paid_month,
    f.first_plan_tier,
    f.first_mrr,
    coalesce(l.current_mrr, 0)                                      as current_mrr,
    l.current_plan_tier,
    coalesce(l.current_mrr, 0) > 0                                  as is_active,
    l.has_had_new_product,
    l.months_paid,
    l.last_paid_month
from workspaces w
join first_month f   on w.workspace_id = f.workspace_id
join first_billing b on w.workspace_id = b.workspace_id
join lifetime l      on w.workspace_id = l.workspace_id
