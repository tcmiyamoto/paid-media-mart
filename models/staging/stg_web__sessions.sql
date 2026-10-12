-- One row per web session from the GA4-style export.
-- UTMs get the same cleanup as leads and signups (lowercase, trim, blank to '(none)'),
-- which also fixes casing variants like 'LinkedIn' and 'Google '.
with raw_sessions as (
    select * from {{ ref('web_sessions') }}
)

select
    session_id,
    cast(user_pseudo_id as {{ dbt.type_string() }})               as user_pseudo_id,
    cast(session_start_ts as timestamp)                           as session_start_ts,
    coalesce(nullif(lower(trim(source)), ''), '(none)')           as utm_source,
    coalesce(nullif(lower(trim(medium)), ''), '(none)')           as utm_medium,
    nullif(trim(cast(campaign as {{ dbt.type_string() }})), '')   as utm_campaign,
    landing_page,
    device_category
from raw_sessions
