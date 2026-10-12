-- Fails if two tests on the same channel claim the same week, which would double-count.
select
    a.channel_name,
    a.test_id as test_a,
    b.test_id as test_b
from {{ ref('int_incrementality_factors') }} a
join {{ ref('int_incrementality_factors') }} b
    on  a.channel_name = b.channel_name
    and a.test_id < b.test_id
    and a.valid_from < coalesce(b.valid_to, date '9999-12-31')
    and b.valid_from < coalesce(a.valid_to, date '9999-12-31')
