-- Accumulating snapshot: one row per lead, updated as it moves through the funnel.
with funnel as (
    select * from {{ ref('int_lead_funnel') }}
),

campaigns as (
    select * from {{ ref('dim_campaign') }}
)

select
    f.lead_id,
    f.created_ts,
    f.created_date,
    f.product_line,
    f.motion,
    f.landing_form,
    f.segment_type,
    f.segment,
    {{ dbt_utils.generate_surrogate_key(['f.channel']) }}   as channel_key,
    c.campaign_key,
    f.click_id is not null                                  as has_click_id,
    f.qualified_at,
    f.opportunity_at,
    f.pipeline_amount,
    f.won_at,
    f.won_arr,
    f.lost_at,
    f.qualified_at   is not null                            as is_qualified,
    f.opportunity_at is not null                            as is_opportunity,
    f.won_at         is not null                            as is_won,
    {{ dbt.datediff('f.created_ts', 'f.qualified_at', 'day') }} as days_to_qualified,
    {{ dbt.datediff('f.created_ts', 'f.won_at', 'day') }}       as days_to_won
from funnel f
left join campaigns c
    on  f.ad_platform  = c.platform
    and f.utm_campaign = c.campaign_id
