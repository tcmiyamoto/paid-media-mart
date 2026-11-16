
select
    date,
    campaign_key,
    attribution_model,
    count(*) as row_count

from {{ ref('obt_marketing_performance_daily') }}

group by 1, 2, 3

having count(*) > 1
