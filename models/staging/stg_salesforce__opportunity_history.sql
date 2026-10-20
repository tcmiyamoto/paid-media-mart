-- One row per opportunity stage change.
select
    id                                  as history_id,
    opportunity_id,
    cast(created_date as timestamp)     as changed_ts,
    stage_name,
    cast(amount as numeric)             as amount,
    probability,
    cast(close_date as date)            as close_date
from {{ ref('sf_opportunity_history') }}
where not is_deleted
