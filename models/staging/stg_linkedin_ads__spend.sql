with source as (
    select * from {{ ref('linkedin_ads_spend') }}
)

select
    cast(day as date)                            as spend_date,
    'linkedin'                                   as platform,
    cast(campaign_id as string)                  as campaign_id,
    campaign_name,
    round(cast(cost_usd as numeric), 2)          as spend_usd,
    cast(impressions as int64)                   as impressions,
    cast(clicks as int64)                        as clicks
from source
