-- The primary campaign always counts as an influence, so every channel's influenced
-- opportunities must include its sourced ones. Fails if any channel has fewer.
select product_line, channel_name
from {{ ref('rpt_pipeline_sourced_vs_influenced') }}
where influenced_opportunities < sourced_opportunities
   or influenced_pipeline      < sourced_pipeline
