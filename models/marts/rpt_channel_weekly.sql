with spend as (
    select
        date_trunc(spend_date, week(monday)) as week_start,
        channel_key,
        sum(spend_usd) as spend_usd
    from {{ ref('fct_ad_spend') }}
    group by 1, 2
),

signups as (
    select
        date_trunc(signup_date, week(monday)) as week_start,
        channel_key,
        count(*)     as signups,
        sum(revenue) as revenue
    from {{ ref('fct_signups') }}
    group by 1, 2
),

joined as (
    select
        coalesce(sp.week_start, su.week_start)   as week_start,
        coalesce(sp.channel_key, su.channel_key) as channel_key,
        coalesce(sp.spend_usd, 0)                as spend_usd,
        coalesce(su.signups, 0)                  as signups,
        coalesce(su.revenue, 0)                  as revenue
    from spend sp
    full outer join signups su
        on  sp.week_start  = su.week_start
        and sp.channel_key = su.channel_key
)

select
    j.week_start,
    ch.channel_name,
    ch.channel_group,
    j.spend_usd,
    j.signups,
    j.revenue,
    round(safe_divide(j.spend_usd, nullif(j.signups, 0)), 2) as cac,
    round(safe_divide(j.revenue, nullif(j.spend_usd, 0)), 2) as roas
from joined j
left join {{ ref('dim_channel') }} ch
    on j.channel_key = ch.channel_key
