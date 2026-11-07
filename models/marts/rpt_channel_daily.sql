-- Grain: one row per date x channel. Feeds the scorecard dashboard.
-- Stores additive measures only, so CAC, cost per signup, and ROAS can be computed in the BI
-- tool as ratios of sums and stay correct at any date range.
--   signups / paid_plan_signups  app signups by signup date; paid_plan = starter or pro at signup
--   leads / customers_won        CRM leads by lead created date (cohort view), the same basis as
--                                rpt_funnel_monthly, so spend / customers_won reconciles to its CAC.
--                                Recent cohorts are still maturing.

with spend as (

    select
        spend_date as report_date,
        channel_key,
        spend_usd,
        impressions,
        clicks,
        0 as signups,
        0 as paid_plan_signups,
        0 as revenue,
        0 as leads,
        0 as customers_won
    from {{ ref('fct_ad_spend') }}

),

signups as (

    select
        signup_date as report_date,
        channel_key,
        0 as spend_usd,
        0 as impressions,
        0 as clicks,
        1 as signups,
        case when is_paid_plan then 1 else 0 end as paid_plan_signups,
        revenue,
        0 as leads,
        0 as customers_won
    from {{ ref('fct_signups') }}

),

leads as (

    select
        created_date as report_date,
        channel_key,
        0 as spend_usd,
        0 as impressions,
        0 as clicks,
        0 as signups,
        0 as paid_plan_signups,
        0 as revenue,
        1 as leads,
        case when is_won then 1 else 0 end as customers_won
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
        sum(spend_usd)         as spend_usd,
        sum(impressions)       as impressions,
        sum(clicks)            as clicks,
        sum(signups)           as signups,
        sum(paid_plan_signups) as paid_plan_signups,
        sum(revenue)           as revenue,
        sum(leads)             as leads,
        sum(customers_won)     as customers_won
    from unioned
    group by 1, 2

)

select
    d.report_date,
    date_trunc(d.report_date, isoweek) as report_week,
    c.channel_name,
    c.channel_group,
    c.is_paid,
    d.spend_usd,
    d.impressions,
    d.clicks,
    d.signups,
    d.paid_plan_signups,
    d.revenue,
    d.leads,
    d.customers_won
from daily as d
left join {{ ref('dim_channel') }} as c
    on d.channel_key = c.channel_key
