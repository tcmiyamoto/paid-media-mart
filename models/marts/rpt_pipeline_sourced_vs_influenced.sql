-- Sourced vs. influenced pipeline by product line x channel.
--
-- Sourced: the channel of the opportunity's Primary Campaign Source (the converting lead's
--   form fill). Each opportunity is sourced by exactly one channel, so sourced pipeline adds
--   up to total pipeline.
-- Influenced: any channel with a campaign response from anyone on the deal in the 90 days before
--   the opportunity opened (int_opportunity_influence). One opportunity can be influenced by
--   several channels, so influenced pipeline does NOT add up across channels.
--
-- They answer different questions. Sourced: which channels create pipeline (budget for new
-- demand). Influenced: which channels are present on deals (support for pipeline already in
-- motion). A channel with a high influence multiplier is doing more than its sourced number shows.
with opportunities as (
    select * from {{ ref('fct_opportunities') }}
),

channels as (
    select * from {{ ref('dim_channel') }}
),

sourced as (
    select
        o.product_line,
        ch.channel_name,
        count(*)                                  as sourced_opportunities,
        sum(o.pipeline_amount)                    as sourced_pipeline,
        sum(coalesce(o.won_arr, 0))               as sourced_won_arr
    from opportunities o
    join channels ch
        on o.sourced_channel_key = ch.channel_key
    group by 1, 2
),

influenced as (
    select
        o.product_line,
        i.channel                                 as channel_name,
        count(*)                                  as influenced_opportunities,
        sum(o.pipeline_amount)                    as influenced_pipeline,
        sum(coalesce(o.won_arr, 0))               as influenced_won_arr,
        sum(case when not i.is_primary_campaign_channel then 1 else 0 end) as influenced_only_opportunities
    from (
        -- One row per opportunity x channel (a deal touched by two webinars counts once).
        select
            opportunity_id,
            channel,
            max(case when is_primary_campaign then 1 else 0 end) = 1 as is_primary_campaign_channel
        from {{ ref('int_opportunity_influence') }}
        group by 1, 2
    ) i
    join opportunities o
        on i.opportunity_id = o.opportunity_id
    group by 1, 2
),

totals as (
    select product_line, sum(pipeline_amount) as total_pipeline
    from opportunities
    group by 1
)

select
    coalesce(s.product_line, i.product_line)                       as product_line,
    coalesce(s.channel_name, i.channel_name)                       as channel_name,
    coalesce(s.sourced_opportunities, 0)                           as sourced_opportunities,
    coalesce(s.sourced_pipeline, 0)                                as sourced_pipeline,
    coalesce(s.sourced_won_arr, 0)                                 as sourced_won_arr,
    coalesce(i.influenced_opportunities, 0)                        as influenced_opportunities,
    coalesce(i.influenced_only_opportunities, 0)                   as influenced_only_opportunities,
    coalesce(i.influenced_pipeline, 0)                             as influenced_pipeline,
    coalesce(i.influenced_won_arr, 0)                              as influenced_won_arr,
    round(coalesce(s.sourced_pipeline, 0) / nullif(t.total_pipeline, 0), 4)    as sourced_share,
    round(coalesce(i.influenced_pipeline, 0) / nullif(t.total_pipeline, 0), 4) as influenced_share,
    round(coalesce(i.influenced_pipeline, 0) / nullif(s.sourced_pipeline, 0), 2) as influence_multiplier
from sourced s
full outer join influenced i
    on  s.product_line = i.product_line
    and s.channel_name = i.channel_name
join totals t
    on coalesce(s.product_line, i.product_line) = t.product_line
