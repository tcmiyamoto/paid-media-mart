-- The month-end snapshot must count every completed recurring line in exactly as many months
-- as its service period covers, so an annual invoice adds up to its full amount over 12 months
-- (no month double-counted or skipped at billing-anchor boundaries).
{% set last_month_exclusive = "2026-10-01" %}

with months as (
    {{ dbt_utils.date_spine(
        datepart="month",
        start_date="cast('2024-10-01' as date)",
        end_date="cast('" ~ last_month_exclusive ~ "' as date)"
    ) }}
),

month_ends as (
    select cast({{ dbt.dateadd('second', -1, dbt.dateadd('month', 1, 'cast(date_month as timestamp)')) }} as timestamp) as month_end_ts
    from months
),

lines as (
    select *
    from {{ ref('int_billing__line_item_mrr') }}
    where period_end_ts < cast('{{ last_month_exclusive }}' as timestamp)
),

recognized as (
    select l.line_item_id, l.net_amount_usd, l.months_in_period, count(m.month_end_ts) as months_counted,
           sum(l.mrr) as recognized_usd
    from lines l
    left join month_ends m
        on  l.period_start_ts <= m.month_end_ts
        and l.period_end_ts   >  m.month_end_ts
    group by 1, 2, 3
)

select *
from recognized
where months_counted <> months_in_period
   or abs(recognized_usd - net_amount_usd) > 0.01
