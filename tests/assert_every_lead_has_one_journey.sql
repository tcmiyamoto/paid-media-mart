-- Fails if a lead is missing from fct_attribution or has other than exactly one
-- lead-creation touch. Every lead must be attributable, even with web tracking blocked.
select
    l.lead_id,
    sum(case when a.is_lead_creation_touch then 1 else 0 end) as lead_creation_touches
from {{ ref('fct_leads') }} l
left join {{ ref('fct_attribution') }} a
    on l.lead_id = a.lead_id
group by 1
having sum(case when a.is_lead_creation_touch then 1 else 0 end) != 1
