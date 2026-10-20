-- One row per Salesforce campaign: one per ad campaign, inbound source, and Marketo program.
-- utm_source / utm_medium hold each campaign's canonical tracking values, cleaned the same way
-- as lead UTMs so campaigns classify through the shared channel mapping.
select
    id                                                              as campaign_id,
    name                                                            as campaign_name,
    type                                                            as campaign_type,
    status                                                          as campaign_status,
    product_line__c                                                 as product_line,
    coalesce(nullif(lower(trim(utm_source__c)), ''), '(none)')      as utm_source,
    coalesce(nullif(lower(trim(utm_medium__c)), ''), '(none)')      as utm_medium,
    nullif(trim(ad_platform__c), '')                                as ad_platform,
    nullif(trim(cast(ad_campaign_id__c as {{ dbt.type_string() }})), '') as ad_campaign_id,
    cast(created_date as timestamp)                                 as created_ts
from {{ ref('sf_campaign') }}
where not is_deleted
