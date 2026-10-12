-- One row per lead per funnel stage reached. amount is ARR on wins and opportunity amount on opps.
with source as (
    select * from {{ ref('funnel_events') }}
)

select
    lead_id,
    stage,
    cast(event_ts as timestamp)                     as event_ts,
    cast(cast(event_ts as timestamp) as date)       as event_date,
    cast(amount as numeric)                         as amount
from source
