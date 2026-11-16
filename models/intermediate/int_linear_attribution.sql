with lead_touchpoints as (
    select * from {{ ref('int_lead_touchpoints')}}
),

final as (
    select
        lead_id,
        anonymous_id,
        lead_created_at,
        touchpoint_id,
        touchpoint_at,
        platform,
        campaign_id,
        1 / count(*) over (partition by lead_id) as attribution_weight
    from lead_touchpoints
    where touchpoint_id is not null
)

select * from final