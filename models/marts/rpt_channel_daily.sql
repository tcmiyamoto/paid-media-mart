-- Grain: one row per date x channel x motion. Feeds the scorecard dashboard.
-- Stores additive measures only, so CAC, payback, cost per signup, and ROAS can be computed in
-- the BI tool as ratios of sums and stay correct at any date range or motion filter.
--   motion                       plg / slg. Spend and signups take the motion of their campaign
--                                (campaign_motion_mapping, as in rpt_funnel_monthly); leads carry
--                                their own. Signups with no campaign (organic, broken tagging) are
--                                'unassigned' rather than guessed.
--   signups / paid_plan_signups  app signups by signup date; paid_plan = starter or pro at signup
--   leads / customers_won /      CRM leads by lead created date (cohort view), the same basis as
--   new_arr                      rpt_funnel_monthly, so spend / customers_won reconciles to its CAC.
--                                new_arr is ARR at win: contracted for SLG, MRR x 12 for PLG.
--                                Recent cohorts are still maturing.

with campaign_motion as (

    select
        c.campaign_key,
        m.motion
    from {{ ref('dim_campaign') }} as c
    join {{ ref('campaign_motion_mapping') }} as m
        on  c.platform    = m.platform
        and c.campaign_id = m.campaign_id

),

spend as (

    select
        s.spend_date as report_date,
        s.channel_key,
        cm.motion,
        s.spend_usd,
        s.impressions,
        s.clicks,
        0 as signups,
        0 as paid_plan_signups,
        0 as revenue,
        0 as leads,
        0 as customers_won,
        0 as new_arr
    from {{ ref('fct_ad_spend') }} as s
    left join campaign_motion as cm
        on s.campaign_key = cm.campaign_key

),

signups as (

    select
        s.signup_date as report_date,
        s.channel_key,
        coalesce(cm.motion, 'unassigned') as motion,
        0 as spend_usd,
        0 as impressions,
        0 as clicks,
        1 as signups,
        case when s.is_paid_plan then 1 else 0 end as paid_plan_signups,
        s.revenue,
        0 as leads,
        0 as customers_won,
        0 as new_arr
    from {{ ref('fct_signups') }} as s
    left join campaign_motion as cm
        on s.campaign_key = cm.campaign_key

),

leads as (

    select
        created_date as report_date,
        channel_key,
        motion,
        0 as spend_usd,
        0 as impressions,
        0 as clicks,
        0 as signups,
        0 as paid_plan_signups,
        0 as revenue,
        1 as leads,
        case when is_won then 1 else 0 end as customers_won,
        case when is_won then coalesce(won_arr, 0) else 0 end as new_arr
    from {{ ref('fct_leads') }}

),

unioned as (

    select * from spend
    union all
    select * from signups
    union all
    select * from leads

),

daily as (

    select
        report_date,
        channel_key,
        motion,
        sum(spend_usd)         as spend_usd,
        sum(impressions)       as impressions,
        sum(clicks)            as clicks,
        sum(signups)           as signups,
        sum(paid_plan_signups) as paid_plan_signups,
        sum(revenue)           as revenue,
        sum(leads)             as leads,
        sum(customers_won)     as customers_won,
        sum(new_arr)           as new_arr
    from unioned
    group by 1, 2, 3

)

select
    d.report_date,
    date_trunc(d.report_date, isoweek) as report_week,
    c.channel_name,
    c.channel_group,
    c.is_paid,
    d.motion,
    d.spend_usd,
    d.impressions,
    d.clicks,
    d.signups,
    d.paid_plan_signups,
    d.revenue,
    d.leads,
    d.customers_won,
    d.new_arr
from daily as d
left join {{ ref('dim_channel') }} as c
    on d.channel_key = c.channel_key
