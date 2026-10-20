-- Leads with a channel from the shared UTM mapping (same rules as signups), plus ad_platform
-- so paid leads can join to dim_campaign.
with leads as (
    select * from {{ ref('stg_salesforce__lead') }}
),

channel_mapping as (
    select * from {{ ref('channel_mapping') }}
),

classified as (
    select
        l.*,
        case
            when m.channel is not null                                   then m.channel
            when l.utm_source = '(none)' and l.utm_medium = '(none)'     then 'Direct'
            when l.utm_medium = 'referral'                               then 'Referral'
            else 'Other'
        end as channel
    from leads l
    left join channel_mapping m
        on  l.utm_source = m.utm_source
        and l.utm_medium = m.utm_medium
)

select
    *,
    case channel
        when 'Paid Search'            then 'google'
        when 'Paid Social - Meta'     then 'meta'
        when 'Paid Social - LinkedIn' then 'linkedin'
    end as ad_platform
from classified
