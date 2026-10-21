-- Churn in the next three months is unknown for the last three months of data, so the
-- outcome must be null there, and known everywhere else.
select customer_health_key, mrr_month, churned_next_3m
from {{ ref('fct_customer_health_monthly') }}
where (mrr_month >  cast('2026-06-01' as date) and churned_next_3m is not null)
   or (mrr_month <= cast('2026-06-01' as date) and churned_next_3m is null)
