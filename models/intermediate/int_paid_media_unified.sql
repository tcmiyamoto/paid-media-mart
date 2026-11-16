
with google as (
    select * from {{ ref('stg_google_ads') }}
),

meta as (
    select * from {{ ref('stg_meta_ads') }}
),

combined as (
    select
        date,
        platform,
        campaign_id,
        campaign_name,
        spend_usd,
        impressions,
        clicks,
        conversions
    from google

    union all

    select
        date,
        platform,
        campaign_id,
        campaign_name,
        spend_usd,
        impressions,
        clicks,
        conversions
    from meta
)

select * from combined
