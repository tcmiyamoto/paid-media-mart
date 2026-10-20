-- One row per contact on an opportunity (the buying committee). is_primary marks the contact
-- the opportunity was converted from.
select
    id                                  as contact_role_id,
    opportunity_id,
    contact_id,
    role                                as contact_role,
    is_primary,
    cast(created_date as timestamp)     as created_ts
from {{ ref('sf_opportunity_contact_role') }}
where not is_deleted
