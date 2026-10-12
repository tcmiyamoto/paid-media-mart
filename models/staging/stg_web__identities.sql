-- One row per identified browser: the web visitor ID linked to a CRM lead when they submit a form.
-- Visits on devices that never submit a form stay anonymous and can't be attributed.
with source as (
    select * from {{ ref('web_identities') }}
)

select
    cast(user_pseudo_id as {{ dbt.type_string() }})   as user_pseudo_id,
    lead_id,
    cast(identified_ts as timestamp)                  as identified_ts
from source
