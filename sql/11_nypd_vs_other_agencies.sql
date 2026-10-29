-- 11 NYPD vs all other agencies combined (closed within the window)
-- Script 08 hides small agencies; this one groups them so nothing is left out.
-- Note: agencies do different kinds of work (a police response vs a street repair), so a
-- gap here describes how fast requests get closed, not how well an agency performs.
SELECT CASE WHEN agency = 'NYPD' THEN 'NYPD' ELSE 'All other agencies' END AS agency_group,
       COUNT(*)                                AS eligible_requests,
       SUM(closed_in_window)                   AS closed_within_window,
       ROUND(100.0 * AVG(closed_in_window), 1) AS pct_closed_within_window
FROM observed_requests
WHERE eligible = 1
GROUP BY 1
ORDER BY 1 DESC;
