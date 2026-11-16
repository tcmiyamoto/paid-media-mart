
with

attribution_source as (
    select * from {{ ref('int_unified_attribution') }}
),

campaign_source as (
    select * from {{ ref('dim_campaign') }}
),

final as (
    select
        date(a.lead_created_at) as date,
        c.campaign_key,
        a.attribution_model,
        sum(a.attribution_weight) as attributed_leads
    from attribution_source a
    left join campaign_source c
        on a.platform = c.platform
        and a.campaign_id = c.campaign_id
    group by 1, 2, 3
)

select * from final
