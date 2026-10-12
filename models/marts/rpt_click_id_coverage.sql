-- Share of paid search leads that carry a Google click ID, by entry form.
-- Without a click ID on the CRM record, downstream outcomes (SQL, won) can't be sent back
-- to the ad platform for bidding. A form with low coverage is a tracking gap to fix.
select
    l.product_line,
    l.motion,
    l.landing_form,
    count(*)                                                    as paid_search_leads,
    sum(case when l.has_click_id then 1 else 0 end)             as with_click_id,
    round(avg(case when l.has_click_id then 1.0 else 0.0 end), 4) as click_id_coverage
from {{ ref('fct_leads') }} l
join {{ ref('dim_channel') }} ch
    on l.channel_key = ch.channel_key
where ch.channel_name = 'Paid Search'
group by 1, 2, 3
