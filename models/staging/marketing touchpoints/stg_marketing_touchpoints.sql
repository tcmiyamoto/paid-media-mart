with touchpoints as (
    select * from {{ ref('raw_marketing_touchpoints') }}
),

transformed as (
    select
        touchpoint_id,
        anonymous_id,
        cast(touchpoint_at as timestamp) as touchpoint_at,
        platform,
        campaign_id
    from touchpoints
)

select * from transformed