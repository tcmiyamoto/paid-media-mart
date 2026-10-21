-- A customer can't be billed before its workspace exists.
select customer_id, workspace_created_ts, first_paid_month
from {{ ref('dim_customer') }}
where first_paid_month < cast({{ dbt.date_trunc('month', 'workspace_created_ts') }} as date)
