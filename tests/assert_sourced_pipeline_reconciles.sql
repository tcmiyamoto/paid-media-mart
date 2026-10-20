-- Sourced pipeline is a partition: it must add up to total opportunity pipeline in fct_leads,
-- and match fct_leads by channel, since the primary campaign is the lead's form fill.
with sourced as (
    select ch.channel_name, sum(o.pipeline_amount) as pipeline
    from {{ ref('fct_opportunities') }} o
    join {{ ref('dim_channel') }} ch on o.sourced_channel_key = ch.channel_key
    group by 1
),

leads as (
    select ch.channel_name, sum(l.pipeline_amount) as pipeline
    from {{ ref('fct_leads') }} l
    join {{ ref('dim_channel') }} ch on l.channel_key = ch.channel_key
    where l.is_opportunity
    group by 1
)

select coalesce(s.channel_name, l.channel_name) as channel_name, s.pipeline, l.pipeline
from sourced s
full outer join leads l
    on s.channel_name = l.channel_name
where abs(coalesce(s.pipeline, 0) - coalesce(l.pipeline, 0)) > 0.01
