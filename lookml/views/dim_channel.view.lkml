view: dim_channel {
  sql_table_name: `@{project}.@{schema}.dim_channel` ;;
  label: "Channel"

  dimension: channel_key {
    primary_key: yes
    hidden: yes
    type: string
    sql: ${TABLE}.channel_key ;;
  }

  dimension: channel_name {
    label: "Channel"
    type: string
    sql: ${TABLE}.channel_name ;;
  }

  dimension: channel_group {
    description: "Paid, Organic, Owned, Direct, or Unclassified"
    type: string
    sql: ${TABLE}.channel_group ;;
  }

  dimension: is_paid {
    type: yesno
    sql: ${TABLE}.is_paid ;;
  }
}
