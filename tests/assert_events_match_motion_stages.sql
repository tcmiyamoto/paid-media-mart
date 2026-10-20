-- Fails if a funnel event uses a stage that isn't defined for the lead's motion.
select e.lead_id, e.stage, l.motion
from {{ ref('int_crm__funnel_events') }} e
join {{ ref('stg_salesforce__lead') }} l
    on e.lead_id = l.lead_id
left join {{ ref('funnel_stage_definitions') }} s
    on  l.motion = s.motion
    and e.stage  = s.stage
where s.stage is null
