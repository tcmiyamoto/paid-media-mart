with opportunities as (
    select
        sum(amount_usd) as stg_revenue
    from {{ ref('stg_crm_opportunities')}}
    where stage = 'closed_won'
),

attribution as (
    select
        attribution_model,
        sum(attributed_revenue) as fct_revenue
    from {{ ref('fct_unified_revenue_attribution')}}
    group by attribution_model
),

final as (
    select
        attribution_model,
        stg_revenue,
        fct_revenue
    from opportunities o
    cross join attribution a
)

select * from final
where stg_revenue is distinct from fct_revenue