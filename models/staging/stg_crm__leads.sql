-- One row per lead (form submission or trial start) from the CRM export.
-- UTMs get the same cleanup as stg_app__signups so the channel mapping join is exact.
with source as (
    select * from {{ ref('leads') }}
)

select
    lead_id,
    cast(created_ts as timestamp)                             as created_ts,
    cast(cast(created_ts as timestamp) as date)               as created_date,
    landing_form,
    product_line,
    motion,
    coalesce(nullif(lower(trim(utm_source)), ''), '(none)')   as utm_source,
    coalesce(nullif(lower(trim(utm_medium)), ''), '(none)')   as utm_medium,
    nullif(trim(cast(utm_campaign as {{ dbt.type_string() }})), '') as utm_campaign,
    nullif(trim(cast(click_id as {{ dbt.type_string() }})), '')     as click_id,
    segment_type,
    segment
from source
