with signups as (
    select * from {{ ref('stg_app__signups') }}
),

channel_mapping as (
    select * from {{ ref('channel_mapping') }}
),

classified as (
    select
        s.*,
        case
            when m.channel is not null                                   then m.channel
            when s.utm_source = '(none)' and s.utm_medium = '(none)'     then 'Direct'
            when s.utm_medium = 'referral'                               then 'Referral'
            else 'Other'
        end as channel
    from signups s
    left join channel_mapping m
        on  s.utm_source = m.utm_source
        and s.utm_medium = m.utm_medium
)

select
    *,
    case channel
        when 'Paid Search'            then 'google'
        when 'Paid Social - Meta'     then 'meta'
        when 'Paid Social - LinkedIn' then 'linkedin'
    end as ad_platform
from classified
