-- Grain: one row per date x channel.
-- Feeds the Tableau scorecard. Stores additive measures only (spend, signups,
-- revenue); CAC and ROAS are computed in Tableau as ratios of sums so they
-- stay correct at any date range.

with spend as (

    select
        spend_date as report_date,
        channel_key,
        sum(spend_usd) as spend_usd,
        sum(impressions) as impressions,
        sum(clicks) as clicks
    from {{ ref('fct_ad_spend') }}
    group by 1, 2

),

signups as (

    select
        signup_date as report_date,
        channel_key,
        count(*) as signups,
        sum(revenue) as revenue
    from {{ ref('fct_signups') }}
    group by 1, 2

),

joined as (

    select
        coalesce(sp.report_date, su.report_date) as report_date,
        coalesce(sp.channel_key, su.channel_key) as channel_key,
        coalesce(sp.spend_usd, 0) as spend_usd,
        coalesce(sp.impressions, 0) as impressions,
        coalesce(sp.clicks, 0) as clicks,
        coalesce(su.signups, 0) as signups,
        coalesce(su.revenue, 0) as revenue
    from spend as sp
    full outer join signups as su
        on sp.report_date = su.report_date
        and sp.channel_key = su.channel_key

)

select
    j.report_date,
    date_trunc(j.report_date, isoweek) as report_week,
    c.channel_name,
    c.channel_group,
    c.is_paid,
    j.spend_usd,
    j.impressions,
    j.clicks,
    j.signups,
    j.revenue
from joined as j
left join {{ ref('dim_channel') }} as c
    on j.channel_key = c.channel_key
