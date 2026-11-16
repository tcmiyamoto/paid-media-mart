with obt_totals as (
    select
        attribution_model,
        sum(spend_usd) as spend_total,
        sum(impressions) as impressions_total,
        sum(clicks) as clicks_total,
        sum(attributed_revenue) as attributed_revenue_total
    from {{ ref('obt_marketing_performance_daily') }}
    group by 1
),

paid_media_totals as (
    select
        sum(spend_usd) as expected_spend_total,
        sum(impressions) as expected_impressions_total,
        sum(clicks) as expected_clicks_total
    from {{ ref('fct_paid_media_daily') }}
),

revenue_totals as (
    select
        attribution_model,
        sum(attributed_revenue) as expected_revenue_total
    from {{ ref('fct_campaign_attributed_revenue_daily') }}
    group by 1
),

expected_models as (
    select 'first_touch' as attribution_model
    union all
    select 'last_touch'
    union all
    select 'linear_touch'
),

final as (
    select
        r.attribution_model as r_attribution_model,
        o.attribution_model as o_attribution_model,
        e.attribution_model as expected_attribution_model,
        o.spend_total as spend_total,
        o.impressions_total as impressions_total,
        o.clicks_total as clicks_total,
        o.attributed_revenue_total as attributed_revenue_total,
        p.expected_spend_total as expected_spend_total,
        p.expected_impressions_total as expected_impressions_total,
        p.expected_clicks_total as expected_clicks_total,
        r.expected_revenue_total as expected_revenue_total
    from expected_models e
    left join revenue_totals r
        on e.attribution_model = r.attribution_model
    left join obt_totals o
        on e.attribution_model = o.attribution_model
    cross join paid_media_totals p
)

select * from final
where r_attribution_model is null
    or o_attribution_model is null
    or spend_total is distinct from expected_spend_total
    or impressions_total is distinct from expected_impressions_total
    or clicks_total is distinct from expected_clicks_total
    or attributed_revenue_total is distinct from expected_revenue_total