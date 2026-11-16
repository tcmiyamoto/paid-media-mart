with attribution as (
    select * from {{ ref('int_unified_attribution') }}
),

opportunities as (
    select *
    from {{ ref('stg_crm_opportunities') }}
),

final as (
    select
        a.lead_id,
        o.opportunity_id,
        a.touchpoint_id,
        a.touchpoint_at,
        a.platform,
        a.campaign_id,
        a.attribution_weight,
        a.attribution_model,
        o.amount_usd * a.attribution_weight AS attributed_revenue
    from attribution a
    join opportunities o on o.lead_id = a.lead_id
    where o.stage = 'closed_won'
)

select * from final