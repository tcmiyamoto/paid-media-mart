-- Fails if last-touch attribution doesn't match the single-touch channel counts in fct_leads.
-- Keeps the new attribution layer consistent with existing funnel reporting.
with attributed as (
    select channel_key, sum(credit_last_touch) as leads
    from {{ ref('fct_attribution') }}
    group by 1
),

leads as (
    select channel_key, count(*) as leads
    from {{ ref('fct_leads') }}
    group by 1
)

select
    coalesce(a.channel_key, l.channel_key) as channel_key,
    a.leads as attributed_leads,
    l.leads as fct_leads_leads
from attributed a
full outer join leads l
    on a.channel_key = l.channel_key
where abs(coalesce(a.leads, 0) - coalesce(l.leads, 0)) > 0.000001
