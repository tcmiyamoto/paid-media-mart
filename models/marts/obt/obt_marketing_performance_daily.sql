with

revenue_source as (
    select * from {{ ref('fct_campaign_attributed_revenue_daily') }}
),

paid_media_source as (
    select * from {{ ref('fct_paid_media_daily') }}
),

lead_source as (
    select * from {{ ref('fct_campaign_attributed_leads_daily') }}
),

attribution_models as (
    select 'first_touch' as attribution_model
    union all
    select 'last_touch'
    union all
    select 'linear_touch'
),

paid_media_expanded as (
    select
        p.*,
        a.attribution_model
    from paid_media_source p
    cross join attribution_models a
),

combined as (
    select
        coalesce(p.date, r.date) as date,
        coalesce(p.campaign_key, r.campaign_key) as campaign_key,
        coalesce(p.attribution_model, r.attribution_model) as attribution_model,
        coalesce(p.spend_usd, 0) as spend_usd,
        coalesce(p.impressions, 0) as impressions,
        coalesce(p.clicks, 0) as clicks,
        coalesce(r.attributed_revenue, 0) as attributed_revenue
    from paid_media_expanded p
    full outer join revenue_source r
        on p.date = r.date
        and p.campaign_key = r.campaign_key
        and p.attribution_model = r.attribution_model
),

final as (
    select
        coalesce(c.date, l.date) as date,
        coalesce(c.campaign_key, l.campaign_key) as campaign_key,
        d.campaign_name,
        coalesce(c.attribution_model, l.attribution_model) as attribution_model,
        coalesce(c.spend_usd, 0) as spend_usd,
        coalesce(c.impressions, 0) as impressions,
        coalesce(c.clicks, 0) as clicks,
        coalesce(l.attributed_leads, 0) as attributed_leads,
        coalesce(c.attributed_revenue, 0) as attributed_revenue
    from combined c
    full outer join lead_source l
        on c.date = l.date
        and c.campaign_key = l.campaign_key
        and c.attribution_model = l.attribution_model
    left join {{ ref('dim_campaign') }} d
        on coalesce(c.campaign_key, l.campaign_key) = d.campaign_key
)

select * from final
