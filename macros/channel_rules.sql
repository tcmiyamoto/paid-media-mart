{#
  Shared channel rules for touchpoints. mapped_channel is the channel from a left join to
  the channel_mapping seed; unmapped traffic falls back to Direct, Referral, or Other.
  Same rules as int_leads__channel_classified and int_signups__channel_classified.
#}
{% macro channel_from_utm(utm_source, utm_medium, mapped_channel) %}
    case
        when {{ mapped_channel }} is not null                                    then {{ mapped_channel }}
        when {{ utm_source }} = '(none)' and {{ utm_medium }} = '(none)'         then 'Direct'
        when {{ utm_medium }} = 'referral'                                       then 'Referral'
        else 'Other'
    end
{% endmacro %}

{% macro ad_platform_from_channel(channel) %}
    case {{ channel }}
        when 'Paid Search'            then 'google'
        when 'Paid Social - Meta'     then 'meta'
        when 'Paid Social - LinkedIn' then 'linkedin'
    end
{% endmacro %}
