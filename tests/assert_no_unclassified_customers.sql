-- Every paying customer's signup UTMs must map to a channel; 'Other' means the mapping seed
-- needs a new row.
select customer_id, acquisition_channel
from {{ ref('dim_customer') }}
where acquisition_channel = 'Other'
