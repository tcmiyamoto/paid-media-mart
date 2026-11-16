with

revenue_source as (
    select * from {{ ref('fct_unified_revenue_attribution') }}
),

lead_source as (
    select * from {{ ref('stg_crm_leads') }}
),

campaign_source as (
    select * from {{ ref('dim_campaign') }}
),

final as (
    select
        date(l.lead_created_at) as date,
        c.campaign_key,
        r.attribution_model,
        sum(r.attributed_revenue) as attributed_revenue
    from revenue_source r
    inner join lead_source l
        on r.lead_id = l.lead_id
    inner join campaign_source c
        on r.platform = c.platform
        and r.campaign_id = c.campaign_id
    group by 1, 2, 3
)

select * from final