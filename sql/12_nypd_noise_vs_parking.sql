-- 12 Within NYPD requests: noise complaints vs parking complaints
-- Comparing inside one agency keeps the comparison fair, because the same agency handles
-- both groups.
SELECT CASE WHEN complaint_type LIKE 'Noise%' THEN 'Noise complaints'
            WHEN complaint_type IN ('Illegal Parking', 'Blocked Driveway') THEN 'Parking complaints'
            ELSE 'Other NYPD complaints' END AS complaint_group,
       COUNT(*)                                AS eligible_requests,
       SUM(closed_in_window)                   AS closed_within_window,
       ROUND(100.0 * AVG(closed_in_window), 1) AS pct_closed_within_window
FROM observed_requests
WHERE eligible = 1
  AND agency = 'NYPD'
GROUP BY 1
ORDER BY pct_closed_within_window DESC;
