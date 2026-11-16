SELECT
    lead_id,
    SUM(attribution_weight) AS total_weight
FROM {{ ref('int_linear_attribution') }}
GROUP BY lead_id
HAVING ABS(SUM(attribution_weight) - 1.0) > 0.000001
