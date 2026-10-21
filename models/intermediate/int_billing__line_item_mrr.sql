-- Recurring revenue per invoice line, normalized to a monthly amount.
--   mrr = net amount (after coupons) / months in the service period
-- An annual invoice therefore counts as 1/12 per month for 12 months instead of a spike in the
-- month it was billed. Excluded, with reasons:
--   - void invoices: voided and reissued, so their lines duplicate the replacement invoice
--   - uncollectible invoices: the renewal a failed-payment customer never paid
--   - proration lines: one-off true-ups for mid-cycle plan changes; the new price shows up as
--     recurring revenue from the next billing period
--   - internal QA customers
with lines as (
    select * from {{ ref('stg_stripe__invoice_line_items') }}
    where not is_proration
),

invoices as (
    select * from {{ ref('stg_stripe__invoices') }}
    where invoice_status in ('paid', 'open')
),

customers as (
    select * from {{ ref('stg_stripe__customers') }}
    where not is_internal
),

prices as (
    select * from {{ ref('stg_stripe__prices') }}
),

products as (
    select * from {{ ref('stg_stripe__products') }}
),

workspaces as (
    select workspace_id, stripe_customer_id
    from {{ ref('int_workspaces__channel_classified') }}
    where stripe_customer_id is not null
),

joined as (
    select
        l.line_item_id,
        l.invoice_id,
        l.subscription_id,
        w.workspace_id,
        i.stripe_customer_id,
        pr.product_line,
        p.plan_tier,
        p.billing_interval,
        p.lookup_key is null                                    as is_contract_price,
        l.amount_usd,
        l.discount_usd,
        l.net_amount_usd,
        l.period_start_ts,
        l.period_end_ts,
        {{ dbt.datediff('cast(l.period_start_ts as date)', 'cast(l.period_end_ts as date)', 'month') }} as months_in_period
    from lines l
    join invoices i   on l.invoice_id = i.invoice_id
    join customers c  on i.stripe_customer_id = c.stripe_customer_id
    join workspaces w on i.stripe_customer_id = w.stripe_customer_id
    join prices p     on l.price_id = p.price_id
    join products pr  on p.product_id = pr.product_id
)

select
    *,
    net_amount_usd / months_in_period    as mrr,
    amount_usd / months_in_period        as list_mrr
from joined
