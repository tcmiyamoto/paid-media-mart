-- Every marketing touch stitched to a lead: one row per touch.
--
-- Three sources:
--   crm      the lead's form fill or trial start (its UTMs in the CRM). Always the
--            lead-creation touch, so every lead has one even if web tracking was blocked.
--   web      sessions from visitor IDs linked to the lead through stg_web__identities.
--            The session in the 30 minutes before the form fill is the same visit as the
--            crm touch, so it is dropped to avoid counting it twice.
--   marketo  email clicks and webinar attendance.
--
-- in_attribution_window marks touches attribution can credit: from 90 days before the lead
-- was created up to the opportunity (SLG leads that reached one) or the lead creation itself.
-- Onboarding emails after a trial starts and touches after an opportunity opens fall outside.
-- dateadd returns DATETIME on BigQuery, so it is cast back to TIMESTAMP before comparing.
{% set lookback_days = 90 %}

with leads as (
    select * from {{ ref('int_lead_funnel') }}
),

channel_mapping as (
    select * from {{ ref('channel_mapping') }}
),

crm_touches as (
    select
        'crm'                     as touch_source,
        lead_id                   as source_record_id,
        lead_id,
        created_ts                as touch_ts,
        landing_form              as touch_type,
        channel,
        ad_platform,
        utm_campaign
    from leads
),

web_sessions as (
    select
        s.session_id,
        i.lead_id,
        s.session_start_ts,
        s.landing_page,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        l.created_ts
    from {{ ref('stg_web__sessions') }} s
    join {{ ref('stg_web__identities') }} i
        on s.user_pseudo_id = i.user_pseudo_id
    join leads l
        on i.lead_id = l.lead_id
),

web_touches as (
    select
        'web'                                                             as touch_source,
        w.session_id                                                      as source_record_id,
        w.lead_id,
        w.session_start_ts                                                as touch_ts,
        'web_session'                                                     as touch_type,
        {{ channel_from_utm('w.utm_source', 'w.utm_medium', 'm.channel') }} as channel,
        w.utm_campaign
    from web_sessions w
    left join channel_mapping m
        on  w.utm_source = m.utm_source
        and w.utm_medium = m.utm_medium
    where not (
            w.session_start_ts >  cast({{ dbt.dateadd('minute', -30, 'w.created_ts') }} as timestamp)
        and w.session_start_ts <= w.created_ts
    )
),

marketo_touches as (
    select
        'marketo'                                                         as touch_source,
        a.activity_id                                                     as source_record_id,
        a.lead_id,
        a.activity_ts                                                     as touch_ts,
        a.activity_type                                                   as touch_type,
        {{ channel_from_utm('a.utm_source', 'a.utm_medium', 'm.channel') }} as channel,
        cast(null as {{ dbt.type_string() }})                             as utm_campaign
    from {{ ref('stg_marketo__activities') }} a
    left join channel_mapping m
        on  a.utm_source = m.utm_source
        and a.utm_medium = m.utm_medium
),

unioned as (
    select touch_source, source_record_id, lead_id, touch_ts, touch_type, channel, ad_platform, utm_campaign
    from crm_touches
    union all
    select touch_source, source_record_id, lead_id, touch_ts, touch_type, channel,
           {{ ad_platform_from_channel('channel') }}, utm_campaign
    from web_touches
    union all
    select touch_source, source_record_id, lead_id, touch_ts, touch_type, channel,
           {{ ad_platform_from_channel('channel') }}, utm_campaign
    from marketo_touches
)

select
    {{ dbt_utils.generate_surrogate_key(['u.touch_source', 'u.source_record_id', 'u.lead_id']) }} as touchpoint_id,
    u.lead_id,
    u.touch_source,
    u.source_record_id,
    u.touch_ts,
    u.touch_type,
    u.channel,
    u.ad_platform,
    u.utm_campaign,
    l.created_ts                                       as lead_created_ts,
    l.opportunity_at,
    u.touch_source = 'crm'                             as is_lead_creation_touch,
    coalesce(
        u.touch_ts >= cast({{ dbt.dateadd('day', -lookback_days, 'l.created_ts') }} as timestamp)
        and u.touch_ts <= coalesce(l.opportunity_at, l.created_ts),
        false
    )                                                  as in_attribution_window
from unioned u
join leads l
    on u.lead_id = l.lead_id
