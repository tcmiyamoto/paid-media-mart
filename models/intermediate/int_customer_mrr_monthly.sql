-- MRR per paying workspace per month, as a month-end snapshot: a line counts toward a month if
-- its service period covers the last second of that month. Each customer gets a row for every
-- month from its first paid month through the last month of data, with zeros after it
-- churns, so the movements model can compare each month to the one before.
{% set first_month = "2024-10-01" %}
{% set last_month_exclusive = "2026-10-01" %}

with months as (
    {{ dbt_utils.date_spine(
        datepart="month",
        start_date="cast('" ~ first_month ~ "' as date)",
        end_date="cast('" ~ last_month_exclusive ~ "' as date)"
    ) }}
),

month_ends as (
    select
        cast(date_month as date)                                                        as mrr_month,
        cast({{ dbt.dateadd('second', -1, dbt.dateadd('month', 1, 'cast(date_month as timestamp)')) }} as timestamp) as month_end_ts
    from months
),

lines as (
    select * from {{ ref('int_billing__line_item_mrr') }}
),

active as (
    select
        l.workspace_id,
        m.mrr_month,
        sum(l.mrr)                                                                  as mrr,
        sum(l.list_mrr)                                                             as list_mrr,
        sum(case when l.product_line = 'core'        then l.mrr else 0 end)         as core_mrr,
        sum(case when l.product_line = 'new_product' then l.mrr else 0 end)         as new_product_mrr,
        max(case when l.product_line = 'core' then l.plan_tier end)                 as core_plan_tier,
        max(case when l.product_line = 'core' then l.billing_interval end)          as core_billing_interval
    from lines l
    join month_ends m
        on  l.period_start_ts <= m.month_end_ts
        and l.period_end_ts   >  m.month_end_ts
    group by 1, 2
),

first_month as (
    select workspace_id, min(mrr_month) as first_paid_month
    from active
    group by 1
),

spine as (
    select f.workspace_id, f.first_paid_month, m.mrr_month
    from first_month f
    join month_ends m
        on m.mrr_month >= f.first_paid_month
)

select
    s.workspace_id,
    s.mrr_month,
    s.first_paid_month,
    {{ dbt.datediff('s.first_paid_month', 's.mrr_month', 'month') }}   as months_since_first_paid,
    coalesce(a.mrr, 0)                  as mrr,
    coalesce(a.list_mrr, 0)             as list_mrr,
    coalesce(a.core_mrr, 0)             as core_mrr,
    coalesce(a.new_product_mrr, 0)      as new_product_mrr,
    a.core_plan_tier,
    a.core_billing_interval
from spine s
left join active a
    on  s.workspace_id = a.workspace_id
    and s.mrr_month    = a.mrr_month
