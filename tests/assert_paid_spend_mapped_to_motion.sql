-- Fails if any campaign with spend has no motion mapping, which would drop it from the funnel report.
select distinct c.platform, c.campaign_id
from {{ ref('fct_ad_spend') }} s
join {{ ref('dim_campaign') }} c
    on s.campaign_key = c.campaign_key
left join {{ ref('campaign_motion_mapping') }} m
    on  c.platform    = m.platform
    and c.campaign_id = m.campaign_id
where m.motion is null
