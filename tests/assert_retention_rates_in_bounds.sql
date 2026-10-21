-- GRR can't exceed 100% or go below 0, and NRR can't be below GRR (expansion only adds).
select *
from {{ ref('rpt_mrr_monthly') }}
where grr_12m > 1
   or grr_12m < 0
   or nrr_12m < grr_12m
