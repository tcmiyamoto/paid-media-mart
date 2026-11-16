with leads as (
    select * from {{ ref('raw_crm_leads') }}
),

transformed as (
    select
        lead_id,
        anonymous_id,
        cast(created_at as timestamp) as lead_created_at,
        lead_status
    from leads
)

select * from transformed