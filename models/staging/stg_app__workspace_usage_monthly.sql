-- One row per workspace per calendar month in which it had a paid subscription.
select
    workspace_id,
    cast(usage_month as date)       as usage_month,
    active_users,
    user_active_days,
    reports_created,
    connected_sources
from {{ ref('app_workspace_usage_monthly') }}
