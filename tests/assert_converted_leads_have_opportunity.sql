-- Fails if a converted lead has no opportunity, or an opportunity has no converting lead.
select l.lead_id, l.converted_opportunity_id, o.opportunity_id
from {{ ref('stg_salesforce__lead') }} l
full outer join {{ ref('stg_salesforce__opportunity') }} o
    on l.converted_opportunity_id = o.opportunity_id
where (l.is_converted and o.opportunity_id is null)
   or (o.opportunity_id is not null and l.lead_id is null)
