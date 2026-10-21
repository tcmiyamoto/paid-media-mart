-- A customer linked to a CRM lead must land in the same channel as that lead, since the
-- workspace's signup UTMs come from the same form fill and use the same channel mapping.
select c.customer_id, c.channel_key, l.channel_key as lead_channel_key
from {{ ref('dim_customer') }} c
join {{ ref('fct_leads') }} l
    on c.lead_id = l.lead_id
where c.channel_key <> l.channel_key
