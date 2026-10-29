-- 06 Weekday vs weekend, compared WITHIN each complaint type
-- Why: weekend requests might look slower only because more of them are a slow type.
-- Comparing inside one type removes that mix effect.
WITH clean AS (
  SELECT DISTINCT unique_key,
         UPPER(TRIM(complaint_type)) AS complaint_type,
         created_date, closed_date
  FROM service_requests
  WHERE closed_date IS NOT NULL
    AND closed_date >= created_date)
SELECT complaint_type,
       CASE WHEN strftime('%w', created_date) IN ('0', '6') THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       COUNT(*) AS requests,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)) * 24, 1) AS avg_hours_to_close,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)), 2) AS avg_days_to_close
FROM clean
GROUP BY 1, 2
HAVING COUNT(*) >= :min_count
ORDER BY 1, 2;
