with source as (
    select * from {{ ref('raw_meta_ads') }}
),

transformed as (
    select
        day as date,
        'meta' as platform,
        campaign_id,
        campaign_name,
        spend as spend_usd,
        impressions,
        link_clicks as clicks,
        purchases as conversions
    from source
)

select * from transformed