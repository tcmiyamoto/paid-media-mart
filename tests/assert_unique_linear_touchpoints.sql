
SELECT
    lead_id,
    touchpoint_id,
    COUNT(*) AS row_count
FROM {{ ref('int_linear_attribution') }}
GROUP BY lead_id, touchpoint_id
HAVING COUNT(*) > 1
