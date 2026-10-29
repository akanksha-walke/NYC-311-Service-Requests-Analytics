-- 01 Data quality audit
-- Run this first and save the numbers: they go in your README ("what I cleaned and why").
-- It reads the file exactly as loaded (duplicates included), then counts problems per UNIQUE request.
WITH raw AS (SELECT * FROM service_requests),
     uniq AS (SELECT DISTINCT unique_key, closed_date, created_date, due_date, complaint_type FROM raw)
SELECT
  (SELECT COUNT(*) FROM raw)                                                        AS rows_in_file,
  (SELECT COUNT(DISTINCT unique_key) FROM raw)                                      AS unique_requests,
  (SELECT COUNT(*) FROM raw) - (SELECT COUNT(DISTINCT unique_key) FROM raw)         AS duplicate_rows,
  (SELECT MAX(c) FROM (SELECT COUNT(*) AS c FROM raw GROUP BY unique_key))          AS max_copies_of_one_request,
  (SELECT MIN(created_date) FROM uniq)                                              AS first_created,
  (SELECT MAX(created_date) FROM uniq)                                              AS last_created,
  (SELECT COUNT(*) FROM uniq WHERE closed_date IS NULL)                             AS no_closed_date,
  (SELECT COUNT(*) FROM uniq WHERE closed_date < created_date)                      AS closed_before_created,
  (SELECT COUNT(*) FROM uniq WHERE due_date IS NOT NULL)                            AS requests_with_due_date,
  (SELECT COUNT(*) FROM uniq WHERE strftime('%H:%M:%S', created_date) = '00:00:00') AS created_exactly_midnight,
  (SELECT COUNT(DISTINCT complaint_type) FROM uniq)                                 AS complaint_types_raw,
  (SELECT COUNT(DISTINCT UPPER(TRIM(complaint_type))) FROM uniq)                    AS complaint_types_after_standardizing;
