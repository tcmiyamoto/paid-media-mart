with spend as (
    select * from {{ ref('int_ad_spend__unioned') }}
),

latest_name as (
    select platform, campaign_id, campaign_name
    from spend
    qualify row_number() over (partition by platform, campaign_id order by spend_date desc) = 1
)

select
    {{ dbt_utils.generate_surrogate_key(['platform', 'campaign_id']) }} as campaign_key,
    campaign_id,
    campaign_name,
    platform,
    {{ dbt_utils.generate_surrogate_key([
        "case platform when 'google' then 'Paid Search' when 'meta' then 'Paid Social - Meta' when 'linkedin' then 'Paid Social - LinkedIn' end"
    ]) }} as channel_key
from latest_name
