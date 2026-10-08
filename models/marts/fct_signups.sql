with signups as (
    select * from {{ ref('int_signups__channel_classified') }}
),

campaigns as (
    select * from {{ ref('dim_campaign') }}
)

select
    s.user_id,
    s.signup_ts,
    s.signup_date,
    c.campaign_key,
    {{ dbt_utils.generate_surrogate_key(['s.channel']) }} as channel_key,
    s.plan,
    s.revenue
from signups s
left join campaigns c
    on  s.ad_platform  = c.platform
    and s.utm_campaign = c.campaign_id
