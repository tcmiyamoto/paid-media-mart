-- Fails if a lead reaches a later stage before an earlier one.
select lead_id
from {{ ref('fct_leads') }}
where (qualified_at   < created_ts)
   or (opportunity_at < qualified_at)
   or (won_at         < coalesce(opportunity_at, qualified_at))
   or (won_at is not null and lost_at is not null)
