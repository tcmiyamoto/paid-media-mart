with source as (
    select *
    from {{ ref('fct_unified_revenue_attribution') }}
),

final as (
    select
        opportunity_id,
        attribution_model,
        touchpoint_id,
        count(*) as row_count
    from source
    group by 1,2,3
    having count(*) > 1
)

select * from final