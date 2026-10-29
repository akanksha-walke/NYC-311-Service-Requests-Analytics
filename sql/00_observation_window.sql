-- 00 Build the table the "closed within N hours" scripts use.
--
-- WHY: a request can only be called "closed within N hours" if we watched it for at least
-- N hours. Pipeline pulls are snapshots, so a request created just before a pull has had
-- almost no time to close. Counting it as "not closed" would make everything look slower
-- than it is.
--
-- HOW:
--  1. Keep one row per request (exact duplicates from repeated pulls are removed).
--  2. Group requests into capture batches: a gap of more than :gap_hours between two
--     consecutive created dates starts a new batch (one batch is roughly one pull).
--  3. A batch's snapshot time is approximated by the latest created_date in that batch.
--     The real pull happened at or after that moment, so this never over-credits a request.
--  4. A request is "eligible" only if it was created at least :window_hours before its
--     batch's snapshot time.
CREATE TABLE observed_requests AS
WITH uniq AS (
  SELECT DISTINCT unique_key,
         UPPER(TRIM(agency))         AS agency,
         TRIM(complaint_type)        AS complaint_type,
         created_date, closed_date
  FROM service_requests),
flagged AS (
  SELECT *,
         CASE WHEN (julianday(created_date)
                    - julianday(LAG(created_date) OVER (ORDER BY created_date, unique_key))) * 24 > :gap_hours
              THEN 1 ELSE 0 END AS new_batch
  FROM uniq),
batched AS (
  SELECT *,
         SUM(new_batch) OVER (ORDER BY created_date, unique_key ROWS UNBOUNDED PRECEDING) AS batch
  FROM flagged),
copies AS (
  SELECT unique_key, COUNT(*) AS copies_in_file
  FROM service_requests GROUP BY unique_key)
SELECT b.unique_key, b.agency, b.complaint_type, b.created_date, b.closed_date, b.batch,
       c.copies_in_file,
       MAX(b.created_date) OVER (PARTITION BY b.batch) AS snapshot_time,
       CASE WHEN (julianday(MAX(b.created_date) OVER (PARTITION BY b.batch))
                  - julianday(b.created_date)) * 24 >= :window_hours THEN 1 ELSE 0 END AS eligible,
       CASE WHEN b.closed_date IS NOT NULL
             AND b.closed_date >= b.created_date
             AND (julianday(b.closed_date) - julianday(b.created_date)) * 24 <= :window_hours
            THEN 1 ELSE 0 END AS closed_in_window
FROM batched b
JOIN copies c USING (unique_key);
