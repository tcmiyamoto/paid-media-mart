
with

fact_totals as (
    select
        attribution_model,
        sum(attributed_leads) as total_leads
    from {{ ref('fct_campaign_attributed_leads_daily') }}
    group by 1
),

obt_totals as (
    select
        attribution_model,
        sum(attributed_leads) as total_leads
    from {{ ref('obt_marketing_performance_daily') }}
    group by 1
),

final as (
    select
        coalesce(f.attribution_model, o.attribution_model) as attribution_model,
        f.total_leads as fact_leads,
        o.total_leads as obt_leads
    from fact_totals f
    full outer join obt_totals o
        on f.attribution_model = o.attribution_model
    where
        f.total_leads is null
        or o.total_leads is null
        or abs(f.total_leads - o.total_leads) > 0.000001
)

select * from final
