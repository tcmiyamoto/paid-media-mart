-- One row per workspace in the product database: every trial since the CRM went live, plus
-- every workspace that has ever paid. Salesforce and Stripe IDs are written by the
-- provisioning syncs. Signup UTMs are captured at workspace creation (copied from the lead's
-- form fill for sales-provisioned workspaces) and get the same cleanup as the CRM.
select
    workspace_id,
    cast(created_at as timestamp)                                       as created_ts,
    nullif(trim(cast(sfdc_lead_id as {{ dbt.type_string() }})), '')     as lead_id,
    nullif(trim(cast(sfdc_account_id as {{ dbt.type_string() }})), '')  as account_id,
    nullif(trim(cast(stripe_customer_id as {{ dbt.type_string() }})), '') as stripe_customer_id,
    coalesce(nullif(lower(trim(signup_utm_source)), ''), '(none)')      as utm_source,
    coalesce(nullif(lower(trim(signup_utm_medium)), ''), '(none)')      as utm_medium,
    nullif(trim(cast(signup_utm_campaign as {{ dbt.type_string() }})), '') as utm_campaign,
    nullif(segment_type, '')                                            as segment_type,
    nullif(segment, '')                                                 as segment,
    is_internal
from {{ ref('app_workspaces') }}
