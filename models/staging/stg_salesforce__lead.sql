-- One row per live Salesforce lead: every form fill and trial signup.
-- Merged duplicates are soft-deleted in Salesforce (is_deleted, with master_record_id pointing
-- at the surviving lead), so they are filtered here.
-- PII: the raw email is hashed and dropped; company stays because it identifies a business.
-- UTMs get the same cleanup as stg_app__signups so the channel mapping join is exact.
with source as (
    select * from {{ ref('sf_lead') }}
    where not is_deleted
)

select
    id                                                              as lead_id,
    cast(created_date as timestamp)                                 as created_ts,
    cast(cast(created_date as timestamp) as date)                   as created_date,
    case lead_source
        when 'Free Trial'      then 'free_trial'
        when 'Talk to Sales'   then 'talk_to_sales'
        when 'Working Session' then 'working_session'
    end                                                             as landing_form,
    case product_interest__c
        when 'New Product' then 'new_product'
        when 'Core'        then 'core'
    end                                                             as product_line,
    case when lead_source = 'Free Trial' then 'plg' else 'slg' end  as motion,
    coalesce(nullif(lower(trim(utm_source__c)), ''), '(none)')      as utm_source,
    coalesce(nullif(lower(trim(utm_medium__c)), ''), '(none)')      as utm_medium,
    nullif(trim(cast(utm_campaign__c as {{ dbt.type_string() }})), '') as utm_campaign,
    nullif(trim(cast(gclid__c as {{ dbt.type_string() }})), '')     as click_id,
    segment_type__c                                                 as segment_type,
    segment__c                                                      as segment,
    status                                                          as lead_status,
    {{ dbt.hash('lower(trim(email))') }}                            as email_hash,
    company,
    title,
    cast(meeting_booked_date__c as timestamp)                       as meeting_booked_ts,
    cast(meeting_held_date__c as timestamp)                         as meeting_held_ts,
    is_converted,
    cast(converted_date as date)                                    as converted_date,
    converted_account_id,
    converted_contact_id,
    converted_opportunity_id
from source
