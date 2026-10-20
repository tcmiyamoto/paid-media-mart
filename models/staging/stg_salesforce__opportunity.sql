-- One row per live opportunity. campaign_id is Salesforce's Primary Campaign Source, set from
-- the converting lead's campaign. Hand-made test opportunities are deleted, so filtered here.
select
    id                                     as opportunity_id,
    account_id,
    name                                   as opportunity_name,
    type                                   as opportunity_type,
    lead_source,
    campaign_id,
    cast(amount as numeric)                as amount,
    stage_name,
    probability,
    forecast_category,
    cast(created_date as timestamp)        as created_ts,
    cast(close_date as date)               as close_date,
    is_closed,
    is_won,
    product_line__c                        as product_line
from {{ ref('sf_opportunity') }}
where not is_deleted
