-- Fails if a credited touch happened after the lead's journey ended (the opportunity, or
-- lead creation for leads without one). Post-trial onboarding and post-opportunity touches
-- must not get credit.
select a.touchpoint_id
from {{ ref('fct_attribution') }} a
join {{ ref('fct_leads') }} l
    on a.lead_id = l.lead_id
where a.touch_ts > coalesce(l.opportunity_at, l.created_ts)
