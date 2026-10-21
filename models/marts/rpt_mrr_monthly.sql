-- MRR bridge by month x motion, with trailing 12-month net and gross revenue retention.
--   NRR = MRR today from customers who were paying 12 months ago / their MRR then
--   GRR = the same, with each customer capped at its MRR 12 months ago (no expansion credit)
-- Retention numerators and denominators are stored alongside the rates, so totals across
-- motions are a sum of numerators over a sum of denominators, never an average of rates.
with movements as (
    select m.*, c.motion
    from {{ ref('fct_mrr_movements') }} m
    join {{ ref('dim_customer') }} c on m.customer_id = c.customer_id
),

bridge as (
    select
        mrr_month,
        motion,
        sum(case when beginning_mrr > 0 then 1 else 0 end)          as beginning_customers,
        sum(case when ending_mrr > 0 then 1 else 0 end)             as ending_customers,
        sum(case when movement_type = 'new' then 1 else 0 end)      as new_customers,
        sum(case when movement_type = 'churn' then 1 else 0 end)    as churned_customers,
        sum(beginning_mrr)                                          as beginning_mrr,
        sum(new_mrr)                                                as new_mrr,
        sum(reactivation_mrr)                                       as reactivation_mrr,
        sum(expansion_mrr)                                          as expansion_mrr,
        sum(case when change_driver = 'cross_sell'  then expansion_mrr else 0 end) as expansion_cross_sell_mrr,
        sum(case when change_driver = 'tier_change' then expansion_mrr else 0 end) as expansion_tier_mrr,
        sum(case when change_driver = 'price'       then expansion_mrr else 0 end) as expansion_price_mrr,
        sum(contraction_mrr)                                        as contraction_mrr,
        sum(churned_mrr)                                            as churned_mrr,
        sum(case when churn_type = 'voluntary'   then churned_mrr else 0 end) as churned_voluntary_mrr,
        sum(case when churn_type = 'involuntary' then churned_mrr else 0 end) as churned_involuntary_mrr,
        sum(ending_mrr)                                             as ending_mrr
    from movements
    group by 1, 2
),

customer_months as (
    select m.workspace_id, m.mrr_month, m.mrr, c.motion
    from {{ ref('int_customer_mrr_monthly') }} m
    join {{ ref('dim_customer') }} c on m.workspace_id = c.customer_id
),

retention as (
    select
        now_.mrr_month,
        now_.motion,
        sum(prior.mrr)                                              as nrr_denominator,
        sum(now_.mrr)                                               as nrr_numerator,
        sum(case when now_.mrr < prior.mrr then now_.mrr else prior.mrr end) as grr_numerator,
        count(*)                                                    as customers_12m_ago,
        sum(case when now_.mrr > 0 then 1 else 0 end)               as customers_retained_12m
    from customer_months now_
    join customer_months prior
        on  now_.workspace_id = prior.workspace_id
        and prior.mrr_month   = cast({{ dbt.dateadd('month', -12, 'now_.mrr_month') }} as date)
        and prior.mrr > 0
    group by 1, 2
)

select
    b.*,
    r.nrr_numerator,
    r.grr_numerator,
    r.nrr_denominator,
    r.customers_12m_ago,
    r.customers_retained_12m,
    round(r.nrr_numerator / nullif(r.nrr_denominator, 0), 4)                    as nrr_12m,
    round(r.grr_numerator / nullif(r.nrr_denominator, 0), 4)                    as grr_12m,
    round((b.new_mrr + b.reactivation_mrr + b.expansion_mrr)
          / nullif(b.contraction_mrr + b.churned_mrr, 0), 2)                    as quick_ratio
from bridge b
left join retention r
    on  b.mrr_month = r.mrr_month
    and b.motion    = r.motion
