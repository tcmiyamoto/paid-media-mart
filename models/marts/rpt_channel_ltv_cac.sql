-- Acquisition channel economics by motion: what a new customer costs today vs. what customers
-- from the same channel have been worth over their first 12 months.
--   CAC              Jul-Sep 2026 paid spend / customers won (rpt_funnel_monthly)
--   Incremental CAC  CAC / the channel's latest incrementality factor. The factor was measured
--                    on signups; applying it to paying customers assumes the same lift.
--   12-month value   revenue in months 0-11 per starting customer, from cohorts that first paid
--                    Oct 2024 to Sep 2025 (the only ones with 12 observed months), x gross margin
--   Payback          first month in which cumulative gross profit per customer covers CAC
-- Uses legacy cohorts' retention to value today's customers: a stated assumption, not a fact.
{% set margin = var('gross_margin', 0.80) %}

with cohort as (
    select
        c.motion,
        c.acquisition_channel,
        m.workspace_id,
        m.months_since_first_paid,
        m.mrr
    from {{ ref('int_customer_mrr_monthly') }} m
    join {{ ref('dim_customer') }} c on m.workspace_id = c.customer_id
    where c.first_paid_month between cast('2024-10-01' as date) and cast('2025-09-01' as date)
      and m.months_since_first_paid <= 12
),

cohort_value as (
    select
        motion,
        acquisition_channel,
        count(distinct workspace_id)                                                        as cohort_customers,
        sum(case when months_since_first_paid = 0 then mrr else 0 end)
            / count(distinct workspace_id)                                                  as avg_starting_mrr,
        sum(case when months_since_first_paid <= 11 then mrr else 0 end)
            / count(distinct workspace_id)                                                  as revenue_12m_per_customer,
        avg(case when months_since_first_paid = 12 then case when mrr > 0 then 1.0 else 0 end end) as logo_retention_m12,
        sum(case when months_since_first_paid = 12 then mrr else 0 end)
            / nullif(sum(case when months_since_first_paid = 0 then mrr else 0 end), 0)    as net_mrr_retention_m12
    from cohort
    group by 1, 2
),

curve as (
    select
        motion,
        acquisition_channel,
        months_since_first_paid,
        sum(sum(mrr)) over (
            partition by motion, acquisition_channel
            order by months_since_first_paid
            rows between unbounded preceding and current row
        ) / count(distinct workspace_id)                    as cumulative_revenue_per_customer
    from cohort
    where months_since_first_paid <= 11
    group by 1, 2, 3
),

acquisition as (
    select
        motion,
        channel_name                                        as acquisition_channel,
        sum(spend_usd)                                      as spend_usd,
        sum(won)                                            as customers_won
    from {{ ref('rpt_funnel_monthly') }}
    group by 1, 2
),

factors as (
    select channel_name, incrementality_factor
    from {{ ref('int_incrementality_factors') }}
    where is_latest_test
),

joined as (
    select
        v.motion,
        v.acquisition_channel,
        a.customers_won,
        a.spend_usd,
        -- Channels with no paid spend have no CAC (null, not zero), so no payback either.
        nullif(a.spend_usd, 0) / nullif(a.customers_won, 0)                     as cac,
        f.incrementality_factor,
        nullif(a.spend_usd, 0) / nullif(a.customers_won, 0) / f.incrementality_factor as incremental_cac,
        v.cohort_customers,
        v.avg_starting_mrr,
        v.logo_retention_m12,
        v.net_mrr_retention_m12,
        v.revenue_12m_per_customer,
        v.revenue_12m_per_customer * {{ margin }}                               as gross_profit_12m_per_customer
    from cohort_value v
    left join acquisition a
        on  v.motion              = a.motion
        and v.acquisition_channel = a.acquisition_channel
    left join factors f
        on v.acquisition_channel = f.channel_name
),

payback as (
    select
        j.motion,
        j.acquisition_channel,
        min(case when c.cumulative_revenue_per_customer * {{ margin }} >= j.cac
                 then c.months_since_first_paid + 1 end)                        as payback_months,
        min(case when c.cumulative_revenue_per_customer * {{ margin }} >= j.incremental_cac
                 then c.months_since_first_paid + 1 end)                        as incremental_payback_months
    from joined j
    join curve c
        on  j.motion              = c.motion
        and j.acquisition_channel = c.acquisition_channel
    group by 1, 2
)

select
    j.motion,
    j.acquisition_channel,
    j.customers_won,
    round(j.spend_usd, 2)                                       as spend_usd,
    round(j.cac, 2)                                             as cac,
    round(j.incrementality_factor, 3)                           as incrementality_factor,
    round(j.incremental_cac, 2)                                 as incremental_cac,
    j.cohort_customers,
    round(j.avg_starting_mrr, 2)                                as avg_starting_mrr,
    round(j.logo_retention_m12, 4)                              as logo_retention_m12,
    round(j.net_mrr_retention_m12, 4)                           as net_mrr_retention_m12,
    round(j.revenue_12m_per_customer, 2)                        as revenue_12m_per_customer,
    round(j.gross_profit_12m_per_customer, 2)                   as gross_profit_12m_per_customer,
    round(j.gross_profit_12m_per_customer / nullif(j.cac, 0), 2)             as ltv_12m_to_cac,
    round(j.gross_profit_12m_per_customer / nullif(j.incremental_cac, 0), 2) as ltv_12m_to_incremental_cac,
    p.payback_months,
    p.incremental_payback_months
from joined j
left join payback p
    on  j.motion              = p.motion
    and j.acquisition_channel = p.acquisition_channel
