-- Fails if an opportunity entered a stage before an earlier one, or closed before it opened.
select opportunity_id
from {{ ref('fct_opportunities') }}
where evaluation_at  < discovery_at
   or proposal_at    < coalesce(evaluation_at, discovery_at)
   or negotiation_at < coalesce(proposal_at, evaluation_at, discovery_at)
   or closed_at      < coalesce(negotiation_at, proposal_at, evaluation_at, discovery_at)
   or discovery_at  <> created_at
   or (is_closed and closed_at is null)
   or (not is_closed and closed_at is not null)
