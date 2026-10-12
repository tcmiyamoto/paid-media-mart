-- One row per incrementality test from the test registry seed.
-- Casts types only; factors are calculated downstream so they can't drift from the inputs.
with source as (
    select * from {{ ref('incrementality_tests') }}
)

select
    test_id,
    channel                                              as channel_name,
    method,
    cast(start_date as date)                             as start_date,
    cast(end_date as date)                               as end_date,
    cast(retest_by as date)                              as retest_by,
    primary_metric,
    cast(lift as numeric)                                as lift,
    cast(lift_ci_low as numeric)                         as lift_ci_low,
    cast(lift_ci_high as numeric)                        as lift_ci_high,
    cast(incremental_conversions as numeric)             as incremental_conversions,
    cast(incremental_conversions_low as numeric)         as incremental_conversions_low,
    cast(incremental_conversions_high as numeric)        as incremental_conversions_high,
    cast(attributed_conversions as numeric)              as attributed_conversions,
    notes
from source
