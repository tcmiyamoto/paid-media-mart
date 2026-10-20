view: fct_opportunities {
  sql_table_name: `@{project}.@{schema}.fct_opportunities` ;;
  label: "Opportunities"

  dimension: opportunity_id {
    primary_key: yes
    type: string
    sql: ${TABLE}.opportunity_id ;;
  }

  dimension: sourced_channel_key {
    hidden: yes
    type: string
    sql: ${TABLE}.sourced_channel_key ;;
  }

  dimension: sourced_campaign_key {
    hidden: yes
    type: string
    sql: ${TABLE}.sourced_campaign_key ;;
  }

  dimension_group: created {
    type: time
    timeframes: [date, week, month, quarter]
    sql: ${TABLE}.created_at ;;
  }

  dimension_group: closed {
    type: time
    timeframes: [date, month, quarter]
    sql: ${TABLE}.closed_at ;;
  }

  dimension: product_line {
    type: string
    sql: ${TABLE}.product_line ;;
  }

  dimension: segment {
    type: string
    sql: ${TABLE}.segment ;;
  }

  dimension: stage_name {
    label: "Current Stage"
    type: string
    sql: ${TABLE}.stage_name ;;
    order_by_field: stage_order
  }

  dimension: stage_order {
    hidden: yes
    type: number
    sql: case ${TABLE}.stage_name
           when 'Discovery' then 1 when 'Evaluation' then 2 when 'Proposal' then 3
           when 'Negotiation' then 4 when 'Closed Won' then 5 when 'Closed Lost' then 6 end ;;
  }

  dimension: is_closed {
    type: yesno
    sql: ${TABLE}.is_closed ;;
  }

  dimension: is_won {
    type: yesno
    sql: ${TABLE}.is_won ;;
  }

  dimension: buying_committee_size {
    type: number
    sql: ${TABLE}.buying_committee_size ;;
  }

  measure: opportunities {
    type: count
    drill_fields: [opportunity_id, created_date, product_line, stage_name, dim_channel.channel_name]
  }

  measure: open_opportunities {
    type: count
    filters: [is_closed: "no"]
  }

  measure: won_opportunities {
    type: count
    filters: [is_won: "yes"]
  }

  measure: closed_opportunities {
    type: count
    filters: [is_closed: "yes"]
  }

  measure: win_rate {
    description: "Won / closed. Open deals are excluded, so recent cohorts read high or low until they close."
    type: number
    value_format_name: percent_1
    sql: ${won_opportunities} / nullif(${closed_opportunities}, 0) ;;
  }

  measure: pipeline {
    type: sum
    value_format_name: usd_0
    sql: ${TABLE}.pipeline_amount ;;
  }

  measure: open_pipeline {
    type: sum
    value_format_name: usd_0
    sql: ${TABLE}.pipeline_amount ;;
    filters: [is_closed: "no"]
  }

  measure: won_arr {
    type: sum
    value_format_name: usd_0
    sql: ${TABLE}.won_arr ;;
  }

  measure: avg_days_in_discovery {
    type: average
    value_format_name: decimal_1
    sql: ${TABLE}.days_in_discovery ;;
  }

  measure: avg_days_in_evaluation {
    type: average
    value_format_name: decimal_1
    sql: ${TABLE}.days_in_evaluation ;;
  }

  measure: avg_days_in_proposal {
    type: average
    value_format_name: decimal_1
    sql: ${TABLE}.days_in_proposal ;;
  }

  measure: avg_days_in_negotiation {
    type: average
    value_format_name: decimal_1
    sql: ${TABLE}.days_in_negotiation ;;
  }

  measure: avg_days_to_close_won {
    type: average
    value_format_name: decimal_1
    sql: ${TABLE}.days_to_close ;;
    filters: [is_won: "yes"]
  }
}
