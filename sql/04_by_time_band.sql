-- 04 Resolution time by time of day the request was created
-- Rows created at exactly 00:00:00 are excluded: that usually means "no time recorded",
-- not a real midnight request. The audit tells you how many that is.
WITH clean AS (
  SELECT DISTINCT unique_key, created_date, closed_date
  FROM service_requests
  WHERE closed_date IS NOT NULL
    AND closed_date >= created_date
    AND strftime('%H:%M:%S', created_date) <> '00:00:00')
SELECT CASE
         WHEN CAST(strftime('%H', created_date) AS INTEGER) BETWEEN 6 AND 11  THEN '1 Morning (6-11)'
         WHEN CAST(strftime('%H', created_date) AS INTEGER) BETWEEN 12 AND 17 THEN '2 Afternoon (12-17)'
         WHEN CAST(strftime('%H', created_date) AS INTEGER) BETWEEN 18 AND 23 THEN '3 Evening (18-23)'
         ELSE '4 Night (0-5)' END AS time_band,
       COUNT(*) AS requests,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)) * 24, 1) AS avg_hours_to_close,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)), 2) AS avg_days_to_close
FROM clean
GROUP BY 1
ORDER BY 1;
