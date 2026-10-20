-- Accumulating snapshot: one row per opportunity, with stage timestamps, time in each stage,
-- the sourced channel (Primary Campaign Source), and the size of the buying committee.
--
-- days_in_<stage> is the time from entering a stage to entering the next one the deal reached,
-- or to closing if it was lost there. It is null while the deal is still in that stage, so
-- averages only use completed stages.
with opportunities as (
    select * from {{ ref('stg_salesforce__opportunity') }}
),

stages as (
    select * from {{ ref('int_opportunity_stages') }}
),

converting_leads as (
    select * from {{ ref('int_leads__channel_classified') }}
    where converted_opportunity_id is not null
),

campaigns as (
    select * from {{ ref('int_salesforce__campaigns') }}
),

committee as (
    select opportunity_id, count(*) as buying_committee_size
    from {{ ref('stg_salesforce__opportunity_contact_role') }}
    group by 1
),

influence as (
    select
        opportunity_id,
        count(distinct campaign_id) as influencing_campaigns,
        count(distinct channel)     as influencing_channels
    from {{ ref('int_opportunity_influence') }}
    group by 1
)

select
    o.opportunity_id,
    o.account_id,
    l.lead_id,
    o.product_line,
    l.segment_type,
    l.segment,
    {{ dbt_utils.generate_surrogate_key(['c.channel']) }}        as sourced_channel_key,
    c.ad_campaign_key                                            as sourced_campaign_key,
    o.campaign_id                                                as primary_campaign_id,
    o.amount                                                     as pipeline_amount,
    case when o.is_won then o.amount end                         as won_arr,
    o.stage_name,
    o.forecast_category,
    o.is_closed,
    o.is_won,
    o.created_ts                                                 as created_at,
    s.discovery_at,
    s.evaluation_at,
    s.proposal_at,
    s.negotiation_at,
    s.closed_at,
    o.close_date                                                 as expected_close_date,
    {{ dbt.datediff('s.discovery_at', 'coalesce(s.evaluation_at, s.closed_at)', 'day') }}   as days_in_discovery,
    {{ dbt.datediff('s.evaluation_at', 'coalesce(s.proposal_at, s.closed_at)', 'day') }}    as days_in_evaluation,
    {{ dbt.datediff('s.proposal_at', 'coalesce(s.negotiation_at, s.closed_at)', 'day') }}   as days_in_proposal,
    {{ dbt.datediff('s.negotiation_at', 's.closed_at', 'day') }}                            as days_in_negotiation,
    {{ dbt.datediff('o.created_ts', 's.closed_at', 'day') }}                                as days_to_close,
    coalesce(cm.buying_committee_size, 0)                        as buying_committee_size,
    coalesce(i.influencing_campaigns, 0)                         as influencing_campaigns,
    coalesce(i.influencing_channels, 0)                          as influencing_channels
from opportunities o
join stages s
    on o.opportunity_id = s.opportunity_id
left join converting_leads l
    on o.opportunity_id = l.converted_opportunity_id
left join campaigns c
    on o.campaign_id = c.campaign_id
left join committee cm
    on o.opportunity_id = cm.opportunity_id
left join influence i
    on o.opportunity_id = i.opportunity_id
