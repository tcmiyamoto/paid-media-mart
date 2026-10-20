-- One row per live Salesforce contact. Raw email is hashed and dropped.
select
    id                                       as contact_id,
    account_id,
    {{ dbt.hash('lower(trim(email))') }}     as email_hash,
    title,
    lead_source,
    cast(created_date as timestamp)          as created_ts
from {{ ref('sf_contact') }}
where not is_deleted
