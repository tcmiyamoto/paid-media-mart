-- Salesforce campaigns with a channel from the shared UTM mapping (same rules as leads and
-- touchpoints) and, for ad campaigns, the key that joins to dim_campaign.
with campaigns as (
    select * from {{ ref('stg_salesforce__campaign') }}
),

channel_mapping as (
    select * from {{ ref('channel_mapping') }}
)

select
    c.*,
    {{ channel_from_utm('c.utm_source', 'c.utm_medium', 'm.channel') }} as channel,
    case when c.ad_platform is not null then
        {{ dbt_utils.generate_surrogate_key(['c.ad_platform', 'c.ad_campaign_id']) }}
    end                                                                 as ad_campaign_key
from campaigns c
left join channel_mapping m
    on  c.utm_source = m.utm_source
    and c.utm_medium = m.utm_medium
