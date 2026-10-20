-- One row per live Salesforce account.
select
    id                                as account_id,
    name                              as account_name,
    website,
    industry,
    number_of_employees,
    segment__c                        as segment,
    type                              as account_type,
    cast(created_date as timestamp)   as created_ts
from {{ ref('sf_account') }}
where not is_deleted
