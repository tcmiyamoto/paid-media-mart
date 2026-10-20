-- One row per campaign membership. A member is a lead, a contact, or both: when a lead
-- converts, Salesforce copies its memberships onto the new contact and keeps the lead ID.
select
    id                                          as campaign_member_id,
    campaign_id,
    lead_id,
    contact_id,
    status                                      as member_status,
    has_responded,
    cast(first_responded_date as timestamp)     as first_responded_ts
from {{ ref('sf_campaign_member') }}
where not is_deleted
