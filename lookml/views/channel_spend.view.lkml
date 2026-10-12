# Total ad spend per channel, one row per channel. Joined to touch-level data, so the
# primary key lets Looker use symmetric aggregates and count each channel's spend once.
view: channel_spend {
  derived_table: {
    sql:
      select channel_key, sum(spend_usd) as spend_usd
      from `@{project}.@{schema}.fct_ad_spend`
      group by 1 ;;
  }
  label: "Spend"

  dimension: channel_key {
    primary_key: yes
    hidden: yes
    type: string
    sql: ${TABLE}.channel_key ;;
  }

  measure: total_spend {
    description: "Ad spend for the channel over the full period (Jul to Sep 2026). Not affected by touch or lead date filters."
    type: sum
    value_format_name: usd_0
    sql: ${TABLE}.spend_usd ;;
  }
}
