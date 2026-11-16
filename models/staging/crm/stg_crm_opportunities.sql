with opportunities as (
    select * from {{ ref('raw_crm_opportunities') }}
),

transformed as (
    select
        opportunity_id,
        lead_id,
        cast(created_at as timestamp) as opportunity_created_at,
        stage,
        amount_usd
    from opportunities
)

select * from transformed