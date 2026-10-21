-- Every customer-month's movements must explain its change in MRR exactly:
--   beginning + new + reactivation + expansion - contraction - churned = ending
select *
from {{ ref('fct_mrr_movements') }}
where abs(beginning_mrr + new_mrr + reactivation_mrr + expansion_mrr
          - contraction_mrr - churned_mrr - ending_mrr) > 0.01
