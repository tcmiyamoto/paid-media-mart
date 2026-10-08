with source as (
    select * from {{ ref('signups') }}
)

select
    user_id,
    cast(signup_ts as timestamp)                              as signup_ts,
    date(cast(signup_ts as timestamp))                        as signup_date,
    coalesce(nullif(lower(trim(utm_source)), ''), '(none)')   as utm_source,
    coalesce(nullif(lower(trim(utm_medium)), ''), '(none)')   as utm_medium,
    nullif(trim(utm_campaign), '')                            as utm_campaign,
    plan,
    cast(revenue as numeric)                                  as revenue
from source
