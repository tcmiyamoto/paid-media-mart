-- Fails if any lead's credits don't sum to 1 under any attribution model.
select
    lead_id,
    sum(credit_first_touch)     as first_touch,
    sum(credit_last_touch)      as last_touch,
    sum(credit_linear)          as linear,
    sum(credit_position_based)  as position_based
from {{ ref('fct_attribution') }}
group by 1
having abs(sum(credit_first_touch)    - 1) > 0.000001
    or abs(sum(credit_last_touch)     - 1) > 0.000001
    or abs(sum(credit_linear)         - 1) > 0.000001
    or abs(sum(credit_position_based) - 1) > 0.000001
