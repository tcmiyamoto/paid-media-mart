select *
from {{ ref('fct_ad_spend') }}
where spend_usd < 0
