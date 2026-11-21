
with paid_media as (
    select *
    from {{ ref('int_paid_media_unified') }}
),

channels as (
    select *
    from {{ ref('dim_channel') }}
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
        {{ dbt_utils.generate_surrogate_key([
            'c.platform',
            'c.campaign_id'
        ]) }} as campaign_key,

        ch.channel_key,
        c.platform,
        c.campaign_id,
        c.campaign_name

    from campaigns c
    left join channels ch
        on ch.channel_name = case
            when c.platform = 'google' then 'Paid Search'
            when c.platform = 'meta' then 'Paid Social - Meta'
        end
    where c.rn = 1
)

select * from final
