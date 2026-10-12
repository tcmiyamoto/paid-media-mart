-- Funnel performance by lead cohort month x product line x motion x channel.
-- Stages are counted against the month the lead was created (cohort view), so conversion
-- rates compare like with like. Recent cohorts are still maturing; read them as open pipeline.
-- Spend is split by motion through campaign_motion_mapping (each campaign's landing form).
with leads as (
    select
        {{ dbt.date_trunc('month', 'l.created_date') }}  as cohort_month,
        l.product_line,
        l.motion,
        ch.channel_name,
        count(*)                                         as leads,
        sum(case when l.is_qualified   then 1 else 0 end) as qualified,
        sum(case when l.is_opportunity then 1 else 0 end) as opportunities,
        sum(case when l.is_won         then 1 else 0 end) as won,
        sum(coalesce(l.pipeline_amount, 0))              as pipeline_amount,
        sum(coalesce(l.won_arr, 0))                      as won_arr
    from {{ ref('fct_leads') }} l
    left join {{ ref('dim_channel') }} ch
        on l.channel_key = ch.channel_key
    group by 1, 2, 3, 4
),

spend as (
    select
        {{ dbt.date_trunc('month', 's.spend_date') }}    as cohort_month,
        m.product_line,
        m.motion,
        ch.channel_name,
        sum(s.spend_usd)                                 as spend_usd
    from {{ ref('fct_ad_spend') }} s
    join {{ ref('dim_campaign') }} c
        on s.campaign_key = c.campaign_key
    join {{ ref('campaign_motion_mapping') }} m
        on  c.platform    = m.platform
        and c.campaign_id = m.campaign_id
    join {{ ref('dim_channel') }} ch
        on s.channel_key = ch.channel_key
    group by 1, 2, 3, 4
),

joined as (
    select
        coalesce(l.cohort_month, s.cohort_month)   as cohort_month,
        coalesce(l.product_line, s.product_line)   as product_line,
        coalesce(l.motion, s.motion)               as motion,
        coalesce(l.channel_name, s.channel_name)   as channel_name,
        coalesce(s.spend_usd, 0)                   as spend_usd,
        coalesce(l.leads, 0)                       as leads,
        coalesce(l.qualified, 0)                   as qualified,
        coalesce(l.opportunities, 0)               as opportunities,
        coalesce(l.won, 0)                         as won,
        coalesce(l.pipeline_amount, 0)             as pipeline_amount,
        coalesce(l.won_arr, 0)                     as won_arr
    from leads l
    full outer join spend s
        on  l.cohort_month = s.cohort_month
        and l.product_line = s.product_line
        and l.motion       = s.motion
        and l.channel_name = s.channel_name
)

select
    *,
    round(spend_usd / nullif(leads, 0), 2)                 as cost_per_lead,
    round(spend_usd / nullif(qualified, 0), 2)             as cost_per_qualified,
    round(spend_usd / nullif(won, 0), 2)                   as cac,
    round(spend_usd / nullif(pipeline_amount, 0), 4)       as cost_per_pipeline_dollar,
    round(qualified / nullif(leads, 0), 4)                 as lead_to_qualified_rate,
    round(won / nullif(leads, 0), 4)                       as lead_to_won_rate
from joined
