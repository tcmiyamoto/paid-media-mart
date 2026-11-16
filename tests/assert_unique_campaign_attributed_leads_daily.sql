
select
    date,
    campaign_key,
    attribution_model,
    count(*) as row_count
from {{ ref('fct_campaign_attributed_leads_daily') }}
group by 1, 2, 3
having count(*) > 1
