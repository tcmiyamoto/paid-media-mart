-- One row per live Stripe customer. Internal QA workspaces bill real invoices, so they are
-- flagged here and excluded downstream. PII: the billing email is hashed and dropped.
select
    id                                                      as stripe_customer_id,
    cast(created as timestamp)                              as created_ts,
    lower(trim(email)) like '%@internal.example.com'        as is_internal,
    {{ dbt.hash('lower(trim(email))') }}                    as email_hash,
    delinquent                                              as is_delinquent
from {{ ref('stripe_customers') }}
where not is_deleted
