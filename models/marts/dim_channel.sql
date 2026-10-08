with channels as (
    select distinct channel as channel_name from {{ ref('channel_mapping') }}
    union distinct select 'Direct'
    union distinct select 'Referral'
    union distinct select 'Other'
)

select
    {{ dbt_utils.generate_surrogate_key(['channel_name']) }} as channel_key,
    channel_name,
    case
        when channel_name like 'Paid%'  then 'Paid'
        when channel_name = 'Direct'    then 'Direct'
        when channel_name = 'Email'     then 'Owned'
        when channel_name = 'Other'     then 'Unclassified'
        else 'Organic'
    end as channel_group,
    channel_name like 'Paid%' as is_paid
from channels
