view: fct_attribution {
  sql_table_name: `@{project}.@{schema}.fct_attribution` ;;
  label: "Attribution"

  # ---------- Attribution model picker ----------

  parameter: attribution_model {
    label: "Attribution Model"
    description: "Which model credits the touches. Position-based is W-shaped for leads with an opportunity and U-shaped otherwise."
    type: unquoted
    default_value: "position_based"
    allowed_value: { label: "Position-based (W-shaped)" value: "position_based" }
    allowed_value: { label: "First touch" value: "first_touch" }
    allowed_value: { label: "Last touch (lead creation)" value: "last_touch" }
    allowed_value: { label: "Linear" value: "linear" }
  }

  dimension: attribution_credit {
    hidden: yes
    type: number
    sql: ${TABLE}.credit_{% parameter attribution_model %} ;;
  }

  dimension: selected_attribution_model {
    label: "Attribution Model (selected)"
    type: string
    sql: '{% parameter attribution_model %}' ;;
  }

  # ---------- Keys ----------

  dimension: touchpoint_id {
    primary_key: yes
    hidden: yes
    type: string
    sql: ${TABLE}.touchpoint_id ;;
  }

  dimension: lead_id {
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

  # ---------- Touch attributes ----------

  dimension_group: touch {
    type: time
    timeframes: [raw, date, week, month, quarter]
    sql: ${TABLE}.touch_ts ;;
  }

  dimension: touch_source {
    description: "crm (form fill), web (identified session), or marketo (email click or webinar)"
    type: string
    sql: ${TABLE}.touch_source ;;
  }

  dimension: touch_type {
    type: string
    sql: ${TABLE}.touch_type ;;
  }

  dimension: touch_position {
    description: "1 is the earliest touch in the lead's attribution window."
    type: number
    sql: ${TABLE}.touch_position ;;
  }

  dimension: touches_in_journey {
    type: number
    sql: ${TABLE}.touches_in_journey ;;
  }

  dimension: touch_role {
    description: "The touch's milestone in a W-shaped journey. A touch can hold more than one; the earliest role is shown."
    type: string
    sql: case
           when ${TABLE}.is_first_touch         then 'First touch'
           when ${TABLE}.is_lead_creation_touch then 'Lead creation'
           when ${TABLE}.is_opportunity_touch   then 'Opportunity creation'
           else 'Middle'
         end ;;
  }

  # ---------- Lead attributes ----------

  dimension: product_line {
    type: string
    sql: ${TABLE}.product_line ;;
  }

  dimension: motion {
    description: "plg (free trial) or slg (sales form)"
    type: string
    sql: ${TABLE}.motion ;;
  }

  dimension_group: lead_created {
    type: time
    timeframes: [date, week, month, quarter]
    datatype: date
    convert_tz: no
    sql: ${TABLE}.lead_created_date ;;
  }

  dimension: is_opportunity {
    type: yesno
    sql: ${TABLE}.is_opportunity ;;
  }

  dimension: is_won {
    type: yesno
    sql: ${TABLE}.is_won ;;
  }

  # ---------- Measures (all follow the Attribution Model filter) ----------

  measure: touches {
    type: count
    drill_fields: [lead_id, touch_date, touch_source, touch_type, touch_role]
  }

  measure: attributed_leads {
    type: sum
    value_format_name: decimal_1
    sql: ${attribution_credit} ;;
  }

  measure: attributed_qualified {
    type: sum
    value_format_name: decimal_1
    sql: ${attribution_credit} * case when ${TABLE}.is_qualified then 1 else 0 end ;;
  }

  measure: attributed_opportunities {
    type: sum
    value_format_name: decimal_1
    sql: ${attribution_credit} * case when ${TABLE}.is_opportunity then 1 else 0 end ;;
  }

  measure: attributed_won {
    type: sum
    value_format_name: decimal_1
    sql: ${attribution_credit} * case when ${TABLE}.is_won then 1 else 0 end ;;
  }

  measure: attributed_pipeline {
    type: sum
    value_format_name: usd_0
    sql: ${attribution_credit} * coalesce(${TABLE}.pipeline_amount, 0) ;;
  }

  measure: attributed_won_arr {
    type: sum
    value_format_name: usd_0
    sql: ${attribution_credit} * coalesce(${TABLE}.won_arr, 0) ;;
  }

  measure: pipeline_per_spend_dollar {
    description: "Attributed pipeline divided by channel spend. Spend covers the full period regardless of date filters."
    type: number
    value_format_name: usd
    sql: ${attributed_pipeline} / nullif(${channel_spend.total_spend}, 0) ;;
  }

  measure: cost_per_attributed_opportunity {
    type: number
    value_format_name: usd_0
    sql: ${channel_spend.total_spend} / nullif(${attributed_opportunities}, 0) ;;
  }
}
