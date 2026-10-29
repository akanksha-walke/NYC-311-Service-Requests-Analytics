-- 07 Monthly trend of resolution time
-- Caution: the most recent months look faster than they are, because slow requests from
-- those months are still open and are not counted yet. Leave out the latest 2-3 months
-- when you read this chart, and say so in your README.
WITH clean AS (
  SELECT DISTINCT unique_key, created_date, closed_date
  FROM service_requests
  WHERE closed_date IS NOT NULL
    AND closed_date >= created_date)
SELECT strftime('%Y-%m', created_date) AS month,
       COUNT(*) AS requests,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)) * 24, 1) AS avg_hours_to_close,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)), 2) AS avg_days_to_close
FROM clean
GROUP BY 1
ORDER BY 1;
