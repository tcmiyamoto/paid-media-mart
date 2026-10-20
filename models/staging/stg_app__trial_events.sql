-- Free trial lifecycle from the product database: trial started, activated (connected a data
-- source, the product-qualified lead), converted to paid. sfdc_lead_id is written by the
-- product-to-CRM sync. arr is set on conversion.
select
    event_id,
    sfdc_lead_id                                as lead_id,
    event_type,
    cast(event_ts as timestamp)                 as event_ts,
    cast(arr as numeric)                        as arr
from {{ ref('app_trial_events') }}
