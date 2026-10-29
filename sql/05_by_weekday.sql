-- 05 Resolution time by day of the week the request was created
WITH clean AS (
  SELECT DISTINCT unique_key, created_date, closed_date
  FROM service_requests
  WHERE closed_date IS NOT NULL
    AND closed_date >= created_date)
SELECT CASE strftime('%w', created_date)
         WHEN '1' THEN '1 Mon' WHEN '2' THEN '2 Tue' WHEN '3' THEN '3 Wed'
         WHEN '4' THEN '4 Thu' WHEN '5' THEN '5 Fri' WHEN '6' THEN '6 Sat'
         ELSE '7 Sun' END AS weekday,
       COUNT(*) AS requests,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)) * 24, 1) AS avg_hours_to_close,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)), 2) AS avg_days_to_close
FROM clean
GROUP BY 1
ORDER BY 1;
