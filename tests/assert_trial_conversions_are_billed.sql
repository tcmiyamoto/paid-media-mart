-- Every trial that converted to paid in the CRM must have a paying workspace in billing.
-- (Sales-led deals are reconciled in rpt_crm_billing_reconciliation instead, since a deal can
-- legitimately close before it is invoiced.)
select l.lead_id
from {{ ref('fct_leads') }} l
left join {{ ref('dim_customer') }} c
    on l.lead_id = c.lead_id
where l.is_won
  and l.motion = 'plg'
  and c.customer_id is null
