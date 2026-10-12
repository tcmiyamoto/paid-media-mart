-- Weekly paid channel performance on two bases: attributed (UTM) and incremental (test-calibrated).
-- Grain: week x paid channel.
--   incremental_signups = attributed signups x the factor valid that week
--   factor_status: current  = a test covers this week and is within its re-test date
--                  stale    = latest test is past its re-test date (still applied, flagged)
--                  untested = no test yet; incremental columns are null, not guessed
with weekly as (
    select
        week_start,
        channel_name,
        spend_usd,
        signups as attributed_signups
    from {{ ref('rpt_channel_weekly') }}
    where channel_group = 'Paid'
),

factors as (
    select * from {{ ref('int_incrementality_factors') }}
),

matched as (
    select
        w.week_start,
        w.channel_name,
        w.spend_usd,
        w.attributed_signups,
        f.test_id,
        f.retest_by,
        f.incrementality_factor,
        f.incrementality_factor_low,
        f.incrementality_factor_high
    from weekly w
    left join factors f
        on  w.channel_name = f.channel_name
        and w.week_start  >= f.valid_from
        and (f.valid_to is null or w.week_start < f.valid_to)
),

calculated as (
    select
        *,
        attributed_signups * incrementality_factor        as incremental_signups,
        attributed_signups * incrementality_factor_low    as incremental_signups_low,
        attributed_signups * incrementality_factor_high   as incremental_signups_high
    from matched
)

select
    week_start,
    channel_name,
    spend_usd,
    attributed_signups,
    round(spend_usd / nullif(attributed_signups, 0), 2)          as attributed_cac,
    test_id,
    round(incrementality_factor, 3)                              as incrementality_factor,
    round(incremental_signups, 1)                                as incremental_signups,
    round(spend_usd / nullif(incremental_signups, 0), 2)         as incremental_cac,
    -- a higher factor bound means more incremental signups, so a lower CAC
    round(spend_usd / nullif(incremental_signups_high, 0), 2)    as incremental_cac_low,
    round(spend_usd / nullif(incremental_signups_low, 0), 2)     as incremental_cac_high,
    case
        when test_id is null          then 'untested'
        when week_start > retest_by   then 'stale'
        else 'current'
    end                                                          as factor_status
from calculated
