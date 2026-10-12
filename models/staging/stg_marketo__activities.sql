-- One row per Marketo activity (email click, webinar attendance) for a known lead.
-- The export repeats some rows, so keep one row per activity_id.
-- program_channel becomes a UTM-style source/medium so it classifies through channel_mapping.
with source as (
    select * from {{ ref('marketo_activities') }}
),

deduped as (
    select
        *,
        row_number() over (partition by activity_id order by activity_ts) as row_num
    from source
)

select
    activity_id,
    lead_id,
    activity_type,
    cast(activity_ts as timestamp)    as activity_ts,
    program_name,
    'marketo'                         as utm_source,
    lower(trim(program_channel))      as utm_medium
from deduped
where row_num = 1
