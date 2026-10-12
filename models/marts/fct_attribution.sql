-- Multi-touch attribution: one row per touch in a lead's attribution window, with the share
-- of the lead's outcomes each model gives that touch. Credits sum to 1 per lead per model.
--
--   first_touch     100% to the earliest touch
--   last_touch      100% to the lead-creation touch (the form fill). This is the single-touch
--                   view in fct_leads, so it reconciles to the existing funnel reporting.
--   linear          equal share to every touch
--   position_based  W-shaped for leads with an opportunity: 30% first touch, 30% lead
--                   creation, 30% the last touch before the opportunity, 10% split across the
--                   rest. U-shaped (40 / 40 / 20) for leads without one. When one touch fills
--                   two roles it gets both shares; with no middle touches, shares are rescaled
--                   to sum to 1.
--
-- Outcome columns (pipeline, won ARR, ...) repeat on every touch of a lead. Multiply them by
-- a credit column to get attributed amounts.
with journey as (
    select * from {{ ref('int_touchpoints') }}
    where in_attribution_window
),

ordered as (
    select
        *,
        row_number() over (
            partition by lead_id
            order by touch_ts, case when touch_source = 'crm' then 1 else 0 end, touchpoint_id
        ) as touch_position,
        row_number() over (
            partition by lead_id
            order by touch_ts desc, case when touch_source = 'crm' then 0 else 1 end, touchpoint_id desc
        ) as reverse_position,
        count(*) over (partition by lead_id) as touches_in_journey
    from journey
),

roles as (
    select
        *,
        touch_position = 1                                            as is_first_touch,
        opportunity_at is not null and reverse_position = 1          as is_opportunity_touch,
        case when opportunity_at is not null then 0.3 else 0.4 end    as milestone_share,
        case when opportunity_at is not null then 0.9 else 0.8 end    as milestone_total
    from ordered
),

weighted as (
    select
        *,
        (case when is_first_touch         then milestone_share else 0 end)
      + (case when is_lead_creation_touch then milestone_share else 0 end)
      + (case when is_opportunity_touch   then 0.3             else 0 end) as milestone_weight
    from roles
),

with_middle as (
    select
        *,
        sum(case when milestone_weight = 0 then 1 else 0 end) over (partition by lead_id) as middle_touches
    from weighted
),

leads as (
    select * from {{ ref('fct_leads') }}
),

campaigns as (
    select * from {{ ref('dim_campaign') }}
)

select
    t.touchpoint_id,
    t.lead_id,
    t.touch_ts,
    t.touch_source,
    t.touch_type,
    t.touch_position,
    t.touches_in_journey,
    {{ dbt_utils.generate_surrogate_key(['t.channel']) }}   as channel_key,
    c.campaign_key,
    t.is_first_touch,
    t.is_lead_creation_touch,
    t.is_opportunity_touch,

    case when t.is_first_touch then 1.0 else 0.0 end          as credit_first_touch,
    case when t.is_lead_creation_touch then 1.0 else 0.0 end  as credit_last_touch,
    1.0 / t.touches_in_journey                                as credit_linear,
    case
        when t.middle_touches = 0   then t.milestone_weight / t.milestone_total
        when t.milestone_weight > 0 then t.milestone_weight
        else (1 - t.milestone_total) / t.middle_touches
    end                                                       as credit_position_based,

    l.product_line,
    l.motion,
    l.created_date                                            as lead_created_date,
    l.is_qualified,
    l.is_opportunity,
    l.is_won,
    l.pipeline_amount,
    l.won_arr
from with_middle t
join leads l
    on t.lead_id = l.lead_id
left join campaigns c
    on  t.ad_platform  = c.platform
    and t.utm_campaign = c.campaign_id
