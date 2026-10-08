-- Fails if a UTM combination falls through to 'Other' (mapping table needs a new row)
select f.user_id
from {{ ref('fct_signups') }} f
join {{ ref('dim_channel') }} d
    on f.channel_key = d.channel_key
where d.channel_name = 'Other'
