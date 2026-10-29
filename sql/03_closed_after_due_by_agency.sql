-- 03 Share of requests closed after their due date, by agency
-- Only requests that have BOTH a closed_date and a due_date can be checked.
-- Look at the audit first: if most rows have no due_date, say so in your README and
-- treat this as a result for the agencies that use due dates only.
WITH clean AS (
  SELECT DISTINCT unique_key, UPPER(TRIM(agency)) AS agency, closed_date, due_date
  FROM service_requests
  WHERE closed_date IS NOT NULL
    AND due_date IS NOT NULL)
SELECT agency,
       COUNT(*) AS requests_with_due_date,
       ROUND(100.0 * AVG(closed_date > due_date), 1) AS pct_closed_after_due
FROM clean
GROUP BY agency
HAVING COUNT(*) >= :min_count
ORDER BY pct_closed_after_due DESC;
