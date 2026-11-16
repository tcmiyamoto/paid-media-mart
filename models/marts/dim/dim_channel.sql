
with channels as (

    select 'Paid Search' as channel_name
    union all
    select 'Paid Social - Meta'

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['channel_name']) }}
            as channel_key,
        channel_name

    from channels

)

select * from final
