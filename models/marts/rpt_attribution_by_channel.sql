-- Attributed leads, pipeline, and won ARR by channel under each attribution model, next to
-- channel spend, so the models can be compared side by side. Grain: model x channel.
{% set models = ['first_touch', 'last_touch', 'linear', 'position_based'] %}

with attributed as (
    {% for m in models %}
    select
        '{{ m }}'                                                                   as attribution_model,
        channel_key,
        sum(credit_{{ m }})                                                         as leads,
        sum(credit_{{ m }} * case when is_qualified   then 1 else 0 end)            as qualified,
        sum(credit_{{ m }} * case when is_opportunity then 1 else 0 end)            as opportunities,
        sum(credit_{{ m }} * coalesce(pipeline_amount, 0))                          as pipeline_amount,
        sum(credit_{{ m }} * case when is_won         then 1 else 0 end)            as won,
        sum(credit_{{ m }} * coalesce(won_arr, 0))                                  as won_arr
    from {{ ref('fct_attribution') }}
    group by 2
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

spend as (
    select channel_key, sum(spend_usd) as spend_usd
    from {{ ref('fct_ad_spend') }}
    group by 1
),

totals as (
    select
        attribution_model,
        sum(pipeline_amount) as total_pipeline,
        sum(won_arr)         as total_won_arr
    from attributed
    group by 1
)

select
    a.attribution_model,
    ch.channel_name,
    ch.channel_group,
    coalesce(s.spend_usd, 0)                                   as spend_usd,
    round(a.leads, 1)                                          as leads,
    round(a.qualified, 1)                                      as qualified,
    round(a.opportunities, 1)                                  as opportunities,
    round(a.pipeline_amount, 2)                                as pipeline_amount,
    round(a.won, 1)                                            as won,
    round(a.won_arr, 2)                                        as won_arr,
    round(a.pipeline_amount / nullif(t.total_pipeline, 0), 4)  as share_of_pipeline,
    round(a.won_arr / nullif(t.total_won_arr, 0), 4)           as share_of_won_arr,
    round(s.spend_usd / nullif(a.leads, 0), 2)                 as cost_per_lead,
    round(s.spend_usd / nullif(a.opportunities, 0), 2)         as cost_per_opportunity,
    round(a.pipeline_amount / nullif(s.spend_usd, 0), 2)       as pipeline_per_spend_dollar
from attributed a
join totals t
    on a.attribution_model = t.attribution_model
join {{ ref('dim_channel') }} ch
    on a.channel_key = ch.channel_key
left join spend s
    on a.channel_key = s.channel_key
