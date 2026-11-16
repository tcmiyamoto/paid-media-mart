with source as (
    select * from {{ ref('raw_google_ads') }}
),

transformed as (
    select
        date,
        'google' as platform,
        campaignId as campaign_id,
        campaignName as campaign_name,
        spend_micros / 1000000.0 as spend_usd,
        impressions,
        clicks,
        conversions
    from source
)

select * from transformed