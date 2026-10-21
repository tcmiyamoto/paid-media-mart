-- Workspaces with an acquisition channel from the shared UTM mapping, so a customer, the lead
-- it came from, and its web sessions always land in the same channel. Internal QA
-- workspaces are dropped.
with workspaces as (
    select * from {{ ref('stg_app__workspaces') }}
    where not is_internal
),

channel_mapping as (
    select * from {{ ref('channel_mapping') }}
)

select
    w.*,
    {{ channel_from_utm('w.utm_source', 'w.utm_medium', 'm.channel') }} as channel
from workspaces w
left join channel_mapping m
    on  w.utm_source = m.utm_source
    and w.utm_medium = m.utm_medium
