-- One row per paying customer per month: product usage, a health score, and whether the
-- customer churned in the next three months (for backtesting the score).
--
-- Health score (0-100), from usage only, so it can flag risk before billing shows a problem:
--   engagement     35  active days per active user >= 12 (20 if >= 8)
--   integration    25  3 or more connected data sources (15 if 2)
--   depth          25  1 or more reports created per active user
--   usage trend    15  active users have not fallen below 70% of their prior 3-month average
-- Bands: healthy (70+), watch (40-69), at_risk (under 40). A customer's first month has no
-- trend yet and keeps the trend points.
--
-- Weights were set from voluntary churn rates by component on customer-months through
-- Dec 2025 (calibration). rpt_health_backtest reports Jan-Jun 2026 separately as a holdout.
-- A first version weighted the usage trend at 40 points; it was the weakest signal and could
-- not separate watch from at_risk, so it was cut to a single drop threshold.
--
-- churned_next_3m is null for the last three months of data, where the outcome isn't known yet.
-- dateadd returns DATETIME on BigQuery, so it is cast back to DATE before comparing.
{% set last_month = "2026-09-01" %}

with usage as (
    select
        *,
        avg(active_users) over (
            partition by workspace_id
            order by usage_month
            rows between 3 preceding and 1 preceding
        ) as prior_3m_avg_active_users
    from {{ ref('stg_app__workspace_usage_monthly') }}
),

active as (
    select * from {{ ref('int_customer_mrr_monthly') }}
    where mrr > 0
),

churn as (
    select customer_id, mrr_month, churn_type
    from {{ ref('fct_mrr_movements') }}
    where movement_type = 'churn'
),

scored as (
    select
        a.workspace_id                                                      as customer_id,
        a.mrr_month,
        a.months_since_first_paid,
        a.mrr,
        u.active_users,
        u.prior_3m_avg_active_users,
        round(u.active_users / nullif(u.prior_3m_avg_active_users, 0), 3)   as active_user_trend,
        round(u.user_active_days / nullif(u.active_users, 0), 1)            as active_days_per_user,
        round(u.reports_created / nullif(u.active_users, 0), 2)             as reports_per_user,
        u.connected_sources,
        case
            when u.user_active_days >= 12 * u.active_users then 35
            when u.user_active_days >= 8  * u.active_users then 20
            else 0
        end
        + case
            when u.connected_sources >= 3 then 25
            when u.connected_sources = 2  then 15
            else 0
        end
        + case when u.reports_created >= u.active_users then 25 else 0 end
        + case
            when u.prior_3m_avg_active_users is null                        then 15
            when u.active_users >= 0.7 * u.prior_3m_avg_active_users        then 15
            else 0
        end                                                                 as health_score
    from active a
    join usage u
        on  a.workspace_id = u.workspace_id
        and a.mrr_month    = u.usage_month
),

outcomes as (
    select
        s.customer_id,
        s.mrr_month,
        max(case when c.customer_id is not null then 1 else 0 end)                      as churned,
        max(case when c.churn_type = 'voluntary'   then 1 else 0 end)                   as churned_voluntary,
        max(case when c.churn_type = 'involuntary' then 1 else 0 end)                   as churned_involuntary
    from scored s
    left join churn c
        on  s.customer_id = c.customer_id
        and c.mrr_month >  s.mrr_month
        and c.mrr_month <= cast({{ dbt.dateadd('month', 3, 's.mrr_month') }} as date)
    group by 1, 2
)

select
    {{ dbt_utils.generate_surrogate_key(['s.customer_id', 's.mrr_month']) }} as customer_health_key,
    s.*,
    case
        when s.health_score >= 70 then 'healthy'
        when s.health_score >= 40 then 'watch'
        else 'at_risk'
    end                                                                     as health_band,
    case when s.mrr_month <= cast({{ dbt.dateadd('month', -3, "cast('" ~ last_month ~ "' as date)") }} as date)
         then o.churned = 1 end                                             as churned_next_3m,
    case when s.mrr_month <= cast({{ dbt.dateadd('month', -3, "cast('" ~ last_month ~ "' as date)") }} as date)
         then o.churned_voluntary = 1 end                                   as churned_voluntary_next_3m,
    case when s.mrr_month <= cast({{ dbt.dateadd('month', -3, "cast('" ~ last_month ~ "' as date)") }} as date)
         then o.churned_involuntary = 1 end                                 as churned_involuntary_next_3m
from scored s
join outcomes o
    on  s.customer_id = o.customer_id
    and s.mrr_month   = o.mrr_month
