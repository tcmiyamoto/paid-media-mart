-- One row per lead with the timestamp of each standard funnel stage.
-- Motion-specific stages (activated, meeting_held, ...) map to standard stages through
-- the funnel_stage_definitions seed, so PLG and SLG can be reported side by side.
with leads as (
    select * from {{ ref('int_leads__channel_classified') }}
),

events as (
    select * from {{ ref('int_crm__funnel_events') }}
),

stages as (
    select * from {{ ref('funnel_stage_definitions') }}
),

events_mapped as (
    select
        e.lead_id,
        s.funnel_stage,
        e.event_ts,
        e.amount
    from events e
    join leads l
        on e.lead_id = l.lead_id
    join stages s
        on  l.motion = s.motion
        and e.stage  = s.stage
),

pivoted as (
    select
        lead_id,
        min(case when funnel_stage = 'lead'        then event_ts end) as lead_at,
        min(case when funnel_stage = 'engaged'     then event_ts end) as engaged_at,
        min(case when funnel_stage = 'qualified'   then event_ts end) as qualified_at,
        min(case when funnel_stage = 'opportunity' then event_ts end) as opportunity_at,
        max(case when funnel_stage = 'opportunity' then amount   end) as pipeline_amount,
        min(case when funnel_stage = 'won'         then event_ts end) as won_at,
        max(case when funnel_stage = 'won'         then amount   end) as won_arr,
        min(case when funnel_stage = 'lost'        then event_ts end) as lost_at
    from events_mapped
    group by 1
)

select
    l.lead_id,
    l.created_ts,
    l.created_date,
    l.product_line,
    l.motion,
    l.landing_form,
    l.segment_type,
    l.segment,
    l.channel,
    l.ad_platform,
    l.utm_campaign,
    l.click_id,
    p.lead_at,
    p.engaged_at,
    p.qualified_at,
    p.opportunity_at,
    p.pipeline_amount,
    p.won_at,
    p.won_arr,
    p.lost_at
from leads l
left join pivoted p
    on l.lead_id = p.lead_id
