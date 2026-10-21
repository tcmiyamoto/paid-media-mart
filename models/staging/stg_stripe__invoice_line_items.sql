-- One row per invoice line: the price billed and the service period it covers.
-- Amounts arrive in cents; net amount is after line-level discounts (coupons).
select
    id                                                          as line_item_id,
    invoice_id,
    subscription_id,
    price_id,
    proration                                                   as is_proration,
    cast(amount as {{ dbt.type_numeric() }}) / 100              as amount_usd,
    cast(discount_amount as {{ dbt.type_numeric() }}) / 100     as discount_usd,
    cast(amount - discount_amount as {{ dbt.type_numeric() }}) / 100 as net_amount_usd,
    cast(period_start as timestamp)                             as period_start_ts,
    cast(period_end as timestamp)                               as period_end_ts
from {{ ref('stripe_invoice_line_items') }}
