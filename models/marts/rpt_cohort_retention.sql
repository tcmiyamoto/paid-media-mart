-- Logo and net revenue retention by acquisition cohort (quarter of first payment) x motion x
-- acquisition channel x months since first payment. Only months every customer in the cohort
-- has reached are kept, so the latest point for each cohort is never a partial month.
{% set last_month = "2026-09-01" %}

with customer_months as (
    select
        m.*,
        c.motion,
        c.acquisition_channel,
        c.first_mrr,
        {{ dbt.date_trunc('quarter', 'm.first_paid_month') }}  as cohort_quarter
    from {{ ref('int_customer_mrr_monthly') }} m
    join {{ ref('dim_customer') }} c on m.workspace_id = c.customer_id
)

select
    cohort_quarter,
    motion,
    acquisition_channel,
    months_since_first_paid,
    count(*)                                            as cohort_customers,
    sum(case when mrr > 0 then 1 else 0 end)            as active_customers,
    sum(first_mrr)                                      as starting_mrr,
    sum(mrr)                                            as mrr,
    round(avg(case when mrr > 0 then 1.0 else 0 end), 4) as logo_retention,
    round(sum(mrr) / nullif(sum(first_mrr), 0), 4)      as net_mrr_retention
from customer_months
where months_since_first_paid
      <= {{ dbt.datediff('cast(' ~ dbt.dateadd('month', 2, 'cohort_quarter') ~ ' as date)', "cast('" ~ last_month ~ "' as date)", 'month') }}
group by 1, 2, 3, 4
