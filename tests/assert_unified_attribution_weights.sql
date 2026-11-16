with source as (
    select * from {{ ref('int_unified_attribution') }}
),

final as (
    select
        lead_id,
        attribution_model,
        sum(attribution_weight) as total_weight
    from source
    group by 1,2
    having abs(sum(attribution_weight) - 1) > .00000001
)

select * from final