-- One row per Stripe subscription. A customer can have several: core, new product, and a new
-- core subscription if a churned customer comes back.
select
    id                                                  as subscription_id,
    customer_id                                         as stripe_customer_id,
    status,
    collection_method,
    cast(start_date as timestamp)                       as started_ts,
    cast(canceled_at as timestamp)                      as canceled_ts,
    cast(ended_at as timestamp)                         as ended_ts,
    cancel_at_period_end,
    nullif(trim(cast(cancellation_reason as {{ dbt.type_string() }})), '') as cancellation_reason
from {{ ref('stripe_subscriptions') }}
