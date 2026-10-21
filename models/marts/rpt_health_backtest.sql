-- How well the health score predicted churn: churn in the next three months by sample x
-- motion x health band, over every customer-month where the outcome is known.
--   calibration  customer-months through Dec 2025, used to set the score weights
--   holdout      Jan-Jun 2026, not used to set the weights: the honest read of the score
with health as (
    select
        h.*,
        c.motion,
        case when h.mrr_month <= cast('2025-12-01' as date) then 'calibration' else 'holdout' end as sample
    from {{ ref('fct_customer_health_monthly') }} h
    join {{ ref('dim_customer') }} c on h.customer_id = c.customer_id
    where h.churned_next_3m is not null
)

select
    sample,
    motion,
    health_band,
    count(*)                                                                    as customer_months,
    sum(mrr)                                                                    as mrr,
    sum(case when churned_next_3m then 1 else 0 end)                            as churned_next_3m,
    sum(case when churned_voluntary_next_3m then 1 else 0 end)                  as churned_voluntary_next_3m,
    sum(case when churned_involuntary_next_3m then 1 else 0 end)                as churned_involuntary_next_3m,
    round(avg(case when churned_next_3m then 1.0 else 0 end), 4)                as churn_rate_next_3m,
    round(avg(case when churned_voluntary_next_3m then 1.0 else 0 end), 4)      as voluntary_churn_rate_next_3m,
    round(avg(case when churned_involuntary_next_3m then 1.0 else 0 end), 4)    as involuntary_churn_rate_next_3m
from health
group by 1, 2, 3
