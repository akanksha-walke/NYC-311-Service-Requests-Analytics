-- 08 Share of requests closed within the window (default 1 hour), by agency
-- Uses only "eligible" requests, i.e. ones observed for at least the full window
-- (see 00_observation_window.sql). Agencies with fewer than :min_count eligible
-- requests are hidden so a handful of requests cannot decide the result.
SELECT agency,
       COUNT(*)                                AS eligible_requests,
       SUM(closed_in_window)                   AS closed_within_window,
       ROUND(100.0 * AVG(closed_in_window), 1) AS pct_closed_within_window
FROM observed_requests
WHERE eligible = 1
GROUP BY agency
HAVING COUNT(*) >= :min_count
ORDER BY pct_closed_within_window DESC;
