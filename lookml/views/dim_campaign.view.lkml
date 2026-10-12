view: dim_campaign {
  sql_table_name: `@{project}.@{schema}.dim_campaign` ;;
  label: "Campaign"

  dimension: campaign_key {
    primary_key: yes
    hidden: yes
    type: string
    sql: ${TABLE}.campaign_key ;;
  }

  dimension: campaign_name {
    label: "Campaign"
    type: string
    sql: ${TABLE}.campaign_name ;;
  }

  dimension: platform {
    type: string
    sql: ${TABLE}.platform ;;
  }

  dimension: campaign_id {
    type: string
    sql: ${TABLE}.campaign_id ;;
  }
}
