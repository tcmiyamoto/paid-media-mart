-- One row per opportunity with the first time it entered each stage, from stage history.
select
    opportunity_id,
    min(case when stage_name = 'Discovery'   then changed_ts end) as discovery_at,
    min(case when stage_name = 'Evaluation'  then changed_ts end) as evaluation_at,
    min(case when stage_name = 'Proposal'    then changed_ts end) as proposal_at,
    min(case when stage_name = 'Negotiation' then changed_ts end) as negotiation_at,
    min(case when stage_name in ('Closed Won', 'Closed Lost') then changed_ts end) as closed_at,
    count(*)                                                      as stage_changes
from {{ ref('stg_salesforce__opportunity_history') }}
group by 1
