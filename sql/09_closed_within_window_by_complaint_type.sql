-- 09 Share of requests closed within the window, by complaint type
-- Same rules as script 08. Types with fewer than :min_count eligible requests are hidden.
SELECT complaint_type,
       COUNT(*)                                AS eligible_requests,
       SUM(closed_in_window)                   AS closed_within_window,
       ROUND(100.0 * AVG(closed_in_window), 1) AS pct_closed_within_window
FROM observed_requests
WHERE eligible = 1
GROUP BY complaint_type
HAVING COUNT(*) >= :min_count
ORDER BY pct_closed_within_window DESC;
