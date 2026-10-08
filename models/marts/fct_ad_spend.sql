with spend as (
    select * from {{ ref('int_ad_spend__unioned') }}
),

campaigns as (
    select * from {{ ref('dim_campaign') }}
)

select
    s.spend_date,
    c.campaign_key,
    c.channel_key,
    s.spend_usd,
    s.impressions,
    s.clicks
from spend s
left join campaigns c
    on  s.platform    = c.platform
    and s.campaign_id = c.campaign_id
