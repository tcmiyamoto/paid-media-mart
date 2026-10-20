-- One row per lead per funnel stage reached, assembled from the systems that record each stage:
--   PLG  trial started, activated, converted to paid        product database (app_trial_events)
--   SLG  lead created                                       Salesforce lead
--        meeting booked, meeting held (SQL)                 lead date fields
--        opportunity created                                converted opportunity
--        closed won / closed lost                           opportunity stage history
-- Stage names match funnel_stage_definitions, which maps them to the standard funnel.
-- amount is the opportunity amount on opportunity_created and won ARR on closed_won / converted_paid.
with leads as (
    select * from {{ ref('stg_salesforce__lead') }}
),

opportunities as (
    select * from {{ ref('stg_salesforce__opportunity') }}
),

closes as (
    select
        opportunity_id,
        min(changed_ts) as closed_ts
    from {{ ref('stg_salesforce__opportunity_history') }}
    where stage_name in ('Closed Won', 'Closed Lost')
    group by 1
),

plg as (
    select
        t.lead_id,
        t.event_type                          as stage,
        t.event_ts,
        case when t.event_type = 'converted_paid' then t.arr end as amount
    from {{ ref('stg_app__trial_events') }} t
),

slg_lead as (
    select lead_id, 'lead_created' as stage, created_ts as event_ts, cast(null as numeric) as amount
    from leads
    where motion = 'slg'
    union all
    select lead_id, 'meeting_booked', meeting_booked_ts, cast(null as numeric)
    from leads
    where motion = 'slg' and meeting_booked_ts is not null
    union all
    select lead_id, 'meeting_held', meeting_held_ts, cast(null as numeric)
    from leads
    where motion = 'slg' and meeting_held_ts is not null
),

slg_opportunity as (
    select l.lead_id, 'opportunity_created' as stage, o.created_ts as event_ts, o.amount
    from leads l
    join opportunities o
        on l.converted_opportunity_id = o.opportunity_id
    union all
    select
        l.lead_id,
        case when o.is_won then 'closed_won' else 'closed_lost' end,
        c.closed_ts,
        case when o.is_won then o.amount end
    from leads l
    join opportunities o
        on l.converted_opportunity_id = o.opportunity_id
    join closes c
        on o.opportunity_id = c.opportunity_id
    where o.is_closed
)

select
    lead_id,
    stage,
    event_ts,
    cast(event_ts as date) as event_date,
    amount
from (
    select * from plg
    union all
    select * from slg_lead
    union all
    select * from slg_opportunity
) events
