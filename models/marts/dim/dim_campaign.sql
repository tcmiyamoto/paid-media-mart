
with paid_media as (
    select *
    from {{ ref('int_paid_media_unified') }}
),

campaigns as (
    select
        platform,
        campaign_id,
        campaign_name,
        row_number() over (
            partition by platform, campaign_id
            order by date desc, campaign_name desc
        ) as rn
    from paid_media
),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['platform', 'campaign_id']) }}
            as campaign_key,

        {{ dbt_utils.generate_surrogate_key([
            "case
                when platform = 'google' then 'Paid Search'
                when platform = 'meta' then 'Paid Social - Meta'
            end"
        ]) }} as channel_key,

        platform,
        campaign_id,
        campaign_name

    from campaigns
    where rn = 1

)

select * from final
