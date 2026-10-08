with source as (
    select * from {{ ref('google_ads_spend') }}
)

select
    cast(`date` as date)                         as spend_date,
    'google'                                     as platform,
    cast(campaign_id as string)                  as campaign_id,
    campaign_name,
    cast(cost_micros as numeric) / 1000000       as spend_usd,
    cast(impressions as int64)                   as impressions,
    cast(clicks as int64)                        as clicks
from source
