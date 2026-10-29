-- 02 Resolution time by complaint type
-- Only CLOSED requests have a resolution time, and rows that close before they were
-- created are excluded (see the audit). Complaint types with fewer than :min_count
-- requests are hidden so rare types cannot top the list by chance.
WITH clean AS (
  SELECT DISTINCT unique_key,
         UPPER(TRIM(complaint_type)) AS complaint_type,
         created_date, closed_date
  FROM service_requests
  WHERE closed_date IS NOT NULL
    AND closed_date >= created_date)
SELECT complaint_type,
       COUNT(*) AS requests,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)) * 24, 1) AS avg_hours_to_close,
       ROUND(AVG(julianday(closed_date) - julianday(created_date)), 2) AS avg_days_to_close
FROM clean
GROUP BY complaint_type
HAVING COUNT(*) >= :min_count
ORDER BY avg_days_to_close DESC;
