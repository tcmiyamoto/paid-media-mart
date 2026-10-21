-- One row per Stripe product. product_line is the name the CRM and funnel models use.
select
    id                                  as product_id,
    name                                as product_name,
    case id
        when 'prod_core'       then 'core'
        when 'prod_newproduct' then 'new_product'
    end                                 as product_line,
    active                              as is_active
from {{ ref('stripe_products') }}
