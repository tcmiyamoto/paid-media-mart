-- Converts each test into an incrementality factor and gives it a validity window.
--   factor = incremental conversions (from the test) / attributed conversions (same period)
-- A factor applies from its test's end_date until the next test on the same channel ends.
with tests as (
    select * from {{ ref('stg_measurement__incrementality_tests') }}
),

factors as (
    select
        test_id,
        channel_name,
        method,
        start_date,
        end_date,
        retest_by,
        incremental_conversions / attributed_conversions       as incrementality_factor,
        incremental_conversions_low / attributed_conversions   as incrementality_factor_low,
        incremental_conversions_high / attributed_conversions  as incrementality_factor_high,
        lead(end_date) over (
            partition by channel_name
            order by end_date
        )                                                      as superseded_on
    from tests
)

select
    test_id,
    channel_name,
    method,
    start_date,
    end_date                    as valid_from,
    superseded_on               as valid_to,
    retest_by,
    incrementality_factor,
    incrementality_factor_low,
    incrementality_factor_high,
    superseded_on is null       as is_latest_test
from factors
