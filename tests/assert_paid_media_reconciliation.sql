WITH source_data AS (
    SELECT * FROM {{ ref('stg_google_ads') }}
    UNION ALL
    SELECT * FROM {{ ref('stg_meta_ads') }}
),

fact_data AS (
    SELECT *
    FROM {{ ref('fct_paid_media_daily') }}
)

select *
from source_data s
full outer join fact_data f
    on f.date = s.date
    and f.campaign_id = s.campaign_id
    and f.platform = s.platform
WHERE s.campaign_id IS NULL
   OR f.campaign_id IS NULL
   OR s.spend_usd IS DISTINCT FROM f.spend_usd
   OR s.impressions IS DISTINCT FROM f.impressions
   OR s.clicks IS DISTINCT FROM f.clicks
   OR s.conversions IS DISTINCT FROM f.conversions