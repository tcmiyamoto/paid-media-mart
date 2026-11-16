with

linear_attribution as (select * from {{ ref('int_linear_attribution') }}),
last_touch_attribution as (select * from {{ ref('int_last_touch') }}),
first_touch_attribution as (select * from {{ ref('int_first_touch') }}),

final as (
    select
        lead_id,
        anonymous_id,
        lead_created_at,
        touchpoint_id,
        touchpoint_at,
        platform,
        campaign_id,
        'linear_touch' as attribution_model,
        attribution_weight
    from linear_attribution
    union all
    select
        lead_id,
        anonymous_id,
        lead_created_at,
        touchpoint_id,
        touchpoint_at,
        platform,
        campaign_id,
        'last_touch' as attribution_model,
        1.0 as attribution_weight
    from last_touch_attribution
    union all
    select
        lead_id,
        anonymous_id,
        lead_created_at,
        touchpoint_id,
        touchpoint_at,
        platform,
        campaign_id,
        'first_touch' as attribution_model,
        1.0 as attribution_weight
    from first_touch_attribution
)

select * from final