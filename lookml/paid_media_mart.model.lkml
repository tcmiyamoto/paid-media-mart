connection: "mktg_portfolio_bigquery"

include: "/views/*.view.lkml"

# Multi-touch attribution. Pick a model with the Attribution Model filter; every attributed
# measure switches with it. Spend is joined at channel grain and protected from fanout by
# the channel_spend primary key (symmetric aggregates).
explore: attribution {
  from: fct_attribution
  label: "Marketing Attribution"
  description: "Leads, pipeline, and won ARR credited to channels and campaigns under first-touch, last-touch, linear, or position-based (W-shaped) attribution."

  join: dim_channel {
    type: left_outer
    relationship: many_to_one
    sql_on: ${attribution.channel_key} = ${dim_channel.channel_key} ;;
  }

  join: dim_campaign {
    type: left_outer
    relationship: many_to_one
    sql_on: ${attribution.campaign_key} = ${dim_campaign.campaign_key} ;;
  }

  join: channel_spend {
    type: left_outer
    relationship: many_to_one
    sql_on: ${attribution.channel_key} = ${channel_spend.channel_key} ;;
  }
}

# Single-touch funnel: one row per lead, credited to the channel of the form it submitted.
explore: lead_funnel {
  from: fct_leads
  label: "Lead Funnel"
  description: "Lead-to-won funnel by product line, motion, channel, and campaign. Single-touch (lead-creation) channel."

  join: dim_channel {
    type: left_outer
    relationship: many_to_one
    sql_on: ${lead_funnel.channel_key} = ${dim_channel.channel_key} ;;
  }

  join: dim_campaign {
    type: left_outer
    relationship: many_to_one
    sql_on: ${lead_funnel.campaign_key} = ${dim_campaign.campaign_key} ;;
  }
}

# Opportunity pipeline: one row per opportunity, credited to the channel of its Primary
# Campaign Source (sourced). Stage velocity measures use completed stages only.
explore: pipeline {
  from: fct_opportunities
  label: "Pipeline"
  description: "Sourced pipeline, win rate, and stage velocity by product line, segment, channel, and campaign."

  join: dim_channel {
    type: left_outer
    relationship: many_to_one
    sql_on: ${pipeline.sourced_channel_key} = ${dim_channel.channel_key} ;;
  }

  join: dim_campaign {
    type: left_outer
    relationship: many_to_one
    sql_on: ${pipeline.sourced_campaign_key} = ${dim_campaign.campaign_key} ;;
  }
}
