-- One row per customer per month in which it had MRR at the start or end of the month.
-- Each month's change in MRR is classified once, so the movements always roll forward:
--   beginning + new + reactivation + expansion - contraction - churned = ending  (tested)
-- Expansion and contraction carry a driver:
--   cross_sell            the customer added the new product
--   product_cancellation  the customer dropped the new product but kept core
--   tier_change           the core plan tier moved (self-serve upgrade or downgrade)
--   price                 same plan, different price: renewal uplift, contract change, or a
--                         coupon ending. MRR is net of coupons, so a promo rolling off shows
--                         up here rather than as tier expansion.
-- Churn is involuntary when the customer's renewal invoice that month went uncollectible.
with customer_months as (
    select * from {{ ref('int_customer_mrr_monthly') }}
),

lagged as (
    select
        *,
        coalesce(lag(mrr)             over (partition by workspace_id order by mrr_month), 0) as beginning_mrr,
        coalesce(lag(core_mrr)        over (partition by workspace_id order by mrr_month), 0) as beginning_core_mrr,
        coalesce(lag(new_product_mrr) over (partition by workspace_id order by mrr_month), 0) as beginning_new_product_mrr,
        lag(core_plan_tier)           over (partition by workspace_id order by mrr_month)     as beginning_plan_tier
    from customer_months
),

uncollectible as (
    select distinct
        w.workspace_id,
        cast({{ dbt.date_trunc('month', 'i.created_ts') }} as date) as mrr_month
    from {{ ref('stg_stripe__invoices') }} i
    join {{ ref('int_workspaces__channel_classified') }} w
        on i.stripe_customer_id = w.stripe_customer_id
    where i.invoice_status = 'uncollectible'
),

classified as (
    select
        l.*,
        case
            when l.beginning_mrr = 0 and l.mrr > 0 and l.months_since_first_paid = 0 then 'new'
            when l.beginning_mrr = 0 and l.mrr > 0                                   then 'reactivation'
            when l.beginning_mrr > 0 and l.mrr = 0                                   then 'churn'
            when l.mrr > l.beginning_mrr + 0.005                                     then 'expansion'
            when l.mrr < l.beginning_mrr - 0.005                                     then 'contraction'
            when l.mrr > 0                                                           then 'flat'
        end as movement_type
    from lagged l
)

select
    {{ dbt_utils.generate_surrogate_key(['c.workspace_id', 'c.mrr_month']) }} as mrr_movement_key,
    c.workspace_id                                                          as customer_id,
    c.mrr_month,
    c.months_since_first_paid,
    c.movement_type,
    case
        when c.movement_type in ('expansion', 'contraction') then
            case
                when c.beginning_new_product_mrr = 0 and c.new_product_mrr > 0 then 'cross_sell'
                when c.beginning_new_product_mrr > 0 and c.new_product_mrr = 0 then 'product_cancellation'
                when c.beginning_plan_tier <> c.core_plan_tier                 then 'tier_change'
                else 'price'
            end
    end                                                                     as change_driver,
    case
        when c.movement_type = 'churn' then
            case when u.workspace_id is not null then 'involuntary' else 'voluntary' end
    end                                                                     as churn_type,
    c.beginning_mrr,
    c.mrr                                                                   as ending_mrr,
    case when c.movement_type = 'new'          then c.mrr else 0 end        as new_mrr,
    case when c.movement_type = 'reactivation' then c.mrr else 0 end        as reactivation_mrr,
    case when c.movement_type = 'expansion'    then c.mrr - c.beginning_mrr else 0 end as expansion_mrr,
    case when c.movement_type = 'contraction'  then c.beginning_mrr - c.mrr else 0 end as contraction_mrr,
    case when c.movement_type = 'churn'        then c.beginning_mrr else 0 end as churned_mrr,
    c.beginning_plan_tier,
    c.core_plan_tier                                                        as ending_plan_tier,
    c.core_billing_interval                                                 as billing_interval
from classified c
left join uncollectible u
    on  c.workspace_id = u.workspace_id
    and c.mrr_month    = u.mrr_month
where c.movement_type is not null
