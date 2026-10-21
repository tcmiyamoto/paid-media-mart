-- Each month's beginning MRR must equal the prior month's ending MRR, by motion, so the bridge
-- has no gaps: nothing appears or disappears between months.
with bridge as (
    select
        mrr_month,
        motion,
        beginning_mrr,
        lag(ending_mrr) over (partition by motion order by mrr_month) as prior_ending_mrr
    from {{ ref('rpt_mrr_monthly') }}
)

select *
from bridge
where prior_ending_mrr is not null
  and abs(beginning_mrr - prior_ending_mrr) > 0.01
