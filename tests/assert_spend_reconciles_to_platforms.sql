-- Fails if modeled spend drifts more than $0.01 from the raw platform totals
with platform_total as (
    select
        (select sum(cast(cost_micros as numeric)) / 1000000 from {{ ref('google_ads_spend') }})
      + (select sum(cast(spend as numeric))                  from {{ ref('meta_ads_spend') }})
      + (select sum(cast(cost_usd as numeric))               from {{ ref('linkedin_ads_spend') }})
      as total
),

modeled_total as (
    select sum(spend_usd) as total
    from {{ ref('fct_ad_spend') }}
)

select
    p.total as platform_total,
    m.total as modeled_total
from platform_total p
cross join modeled_total m
where abs(p.total - m.total) > 0.01
