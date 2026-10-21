-- One row per Stripe price. Amounts arrive in cents.
-- List prices carry a lookup_key (core_<tier>_<interval>); sales-led contracts get a one-off
-- price from the quote with no lookup_key, so their tier is 'contract'.
select
    id                                                              as price_id,
    product_id,
    nickname                                                        as price_nickname,
    nullif(trim(cast(lookup_key as {{ dbt.type_string() }})), '')   as lookup_key,
    coalesce(
        {{ dbt.split_part("nullif(trim(cast(lookup_key as " ~ dbt.type_string() ~ ")), '')", "'_'", 2) }},
        'contract'
    )                                                               as plan_tier,
    cast(unit_amount as {{ dbt.type_numeric() }}) / 100             as unit_amount_usd,
    recurring_interval                                              as billing_interval,
    cast(created as timestamp)                                      as created_ts
from {{ ref('stripe_prices') }}
