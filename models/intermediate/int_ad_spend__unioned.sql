with google as (
    select * from {{ ref('stg_google_ads__spend') }}
),

meta as (
    select * from {{ ref('stg_meta_ads__spend') }}
),

linkedin as (
    select * from {{ ref('stg_linkedin_ads__spend') }}
)

select * from google
union all
select * from meta
union all
select * from linkedin
