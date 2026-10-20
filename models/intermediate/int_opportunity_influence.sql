-- Which campaigns influenced each opportunity: one row per opportunity x campaign.
--
-- A campaign influences an opportunity when anyone on the deal responded to it in the
-- 90 days before the opportunity was created:
--   - the lead the opportunity was converted from (its form fill, nurture, webinars), or
--   - any contact on the opportunity (OpportunityContactRole), so colleagues in the buying
--     committee who attended a webinar or clicked an ad count too.
-- Responses after the opportunity opened are excluded, matching the attribution window.
-- The primary campaign (Opportunity.campaign_id) always qualifies: it is the converting lead's
-- form fill, which happens before the opportunity.
-- dateadd returns DATETIME on BigQuery, so it is cast back to TIMESTAMP before comparing.
{% set lookback_days = 90 %}

with opportunities as (
    select * from {{ ref('stg_salesforce__opportunity') }}
),

members as (
    select * from {{ ref('stg_salesforce__campaign_member') }}
    where has_responded
),

lead_responses as (
    select
        l.converted_opportunity_id     as opportunity_id,
        m.campaign_id,
        m.first_responded_ts,
        'converting_lead'              as responder
    from {{ ref('stg_salesforce__lead') }} l
    join members m
        on l.lead_id = m.lead_id
    where l.converted_opportunity_id is not null
),

committee_responses as (
    select
        r.opportunity_id,
        m.campaign_id,
        m.first_responded_ts,
        case when r.is_primary then 'converting_lead' else 'buying_committee' end as responder
    from {{ ref('stg_salesforce__opportunity_contact_role') }} r
    join members m
        on r.contact_id = m.contact_id
),

responses as (
    select * from lead_responses
    union all
    select * from committee_responses
),

in_window as (
    select
        r.opportunity_id,
        r.campaign_id,
        r.first_responded_ts,
        r.responder
    from responses r
    join opportunities o
        on r.opportunity_id = o.opportunity_id
    where r.first_responded_ts >= cast({{ dbt.dateadd('day', -lookback_days, 'o.created_ts') }} as timestamp)
      and r.first_responded_ts <= o.created_ts
)

select
    {{ dbt_utils.generate_surrogate_key(['w.opportunity_id', 'w.campaign_id']) }} as influence_id,
    w.opportunity_id,
    w.campaign_id,
    c.channel,
    min(w.first_responded_ts)                                            as first_responded_ts,
    max(case when w.responder = 'converting_lead'  then 1 else 0 end) = 1 as via_converting_lead,
    max(case when w.responder = 'buying_committee' then 1 else 0 end) = 1 as via_buying_committee,
    max(case when w.campaign_id = o.campaign_id then 1 else 0 end) = 1    as is_primary_campaign
from in_window w
join opportunities o
    on w.opportunity_id = o.opportunity_id
join {{ ref('int_salesforce__campaigns') }} c
    on w.campaign_id = c.campaign_id
group by 1, 2, 3, 4
