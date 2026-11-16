
with paid_media as (

    select *
    from {{ ref('int_paid_media_unified') }}

),

campaigns as (

    select
        campaign_key,
        platform,
        campaign_id
    from {{ ref('dim_campaign') }}

),

final as (

    select
        p.date,
        c.campaign_key,
        p.platform,
        p.campaign_id,
        sum(p.spend_usd) as spend_usd,
        sum(p.impressions) as impressions,
        sum(p.clicks) as clicks,
        sum(p.conversions) as conversions

    from paid_media p

    left join campaigns c
        on p.platform = c.platform
        and p.campaign_id = c.campaign_id

    group by 1, 2, 3, 4

)

select * from final
