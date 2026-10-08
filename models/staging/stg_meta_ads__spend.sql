with source as (
    select * from {{ ref('meta_ads_spend') }}
)

select
    cast(date_start as date)                     as spend_date,
    'meta'                                       as platform,
    cast(campaign_id as string)                  as campaign_id,
    campaign_name,
    round(cast(spend as numeric), 2)             as spend_usd,
    cast(impressions as int64)                   as impressions,
    cast(clicks as int64)                        as clicks
from source
