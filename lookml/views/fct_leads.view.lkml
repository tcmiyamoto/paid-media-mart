view: fct_leads {
  sql_table_name: `@{project}.@{schema}.fct_leads` ;;
  label: "Leads"

  dimension: lead_id {
    primary_key: yes
    type: string
    sql: ${TABLE}.lead_id ;;
  }

  dimension: channel_key {
    hidden: yes
    type: string
    sql: ${TABLE}.channel_key ;;
  }

  dimension: campaign_key {
    hidden: yes
    type: string
    sql: ${TABLE}.campaign_key ;;
  }

  dimension_group: created {
    type: time
    timeframes: [date, week, month, quarter]
    datatype: date
    convert_tz: no
    sql: ${TABLE}.created_date ;;
  }

  dimension: product_line {
    type: string
    sql: ${TABLE}.product_line ;;
  }

  dimension: motion {
    type: string
    sql: ${TABLE}.motion ;;
  }

  dimension: landing_form {
    type: string
    sql: ${TABLE}.landing_form ;;
  }

  dimension: segment {
    type: string
    sql: ${TABLE}.segment ;;
  }

  dimension: has_click_id {
    type: yesno
    sql: ${TABLE}.has_click_id ;;
  }

  dimension: days_to_won {
    type: number
    sql: ${TABLE}.days_to_won ;;
  }

  measure: leads {
    type: count
    drill_fields: [lead_id, created_date, product_line, motion, dim_channel.channel_name]
  }

  measure: qualified {
    type: count
    filters: [is_qualified: "yes"]
  }

  measure: opportunities {
    type: count
    filters: [is_opportunity: "yes"]
  }

  measure: won {
    type: count
    filters: [is_won: "yes"]
  }

  measure: pipeline {
    type: sum
    value_format_name: usd_0
    sql: ${TABLE}.pipeline_amount ;;
  }

  measure: won_arr {
    type: sum
    value_format_name: usd_0
    sql: ${TABLE}.won_arr ;;
  }

  measure: lead_to_qualified_rate {
    type: number
    value_format_name: percent_1
    sql: ${qualified} / nullif(${leads}, 0) ;;
  }

  measure: lead_to_won_rate {
    type: number
    value_format_name: percent_1
    sql: ${won} / nullif(${leads}, 0) ;;
  }

  dimension: is_qualified {
    type: yesno
    sql: ${TABLE}.is_qualified ;;
  }

  dimension: is_opportunity {
    type: yesno
    sql: ${TABLE}.is_opportunity ;;
  }

  dimension: is_won {
    type: yesno
    sql: ${TABLE}.is_won ;;
  }
}
