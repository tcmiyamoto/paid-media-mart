
WITH leads AS (
    SELECT * FROM {{ ref('stg_crm_leads') }}
),

touchpoints AS (
    SELECT * FROM {{ ref('stg_marketing_touchpoints') }}
)

SELECT
    l.lead_id,
    l.anonymous_id,
    l.lead_created_at,
    t.touchpoint_id,
    t.touchpoint_at,
    t.platform,
    t.campaign_id
FROM leads l
LEFT JOIN touchpoints t
    ON l.anonymous_id = t.anonymous_id
    AND t.touchpoint_at <= l.lead_created_at
