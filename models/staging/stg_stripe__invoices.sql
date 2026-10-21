-- One row per Stripe invoice, including void and uncollectible ones (filtered in the MRR model,
-- where the reason is documented). Amounts arrive in cents.
select
    id                                                  as invoice_id,
    customer_id                                         as stripe_customer_id,
    subscription_id,
    status                                              as invoice_status,
    collection_method,
    cast(created as timestamp)                          as created_ts,
    cast(amount_due as {{ dbt.type_numeric() }}) / 100  as amount_due_usd,
    cast(amount_paid as {{ dbt.type_numeric() }}) / 100 as amount_paid_usd
from {{ ref('stripe_invoices') }}
