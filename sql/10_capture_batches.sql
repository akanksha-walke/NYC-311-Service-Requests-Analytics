-- 10 One row per capture batch (roughly one pipeline pull)
-- Shows what each pull covered, how many times it was loaded into the file, and its
-- closed-within-window rate. Use it to describe the sample honestly in your README.
SELECT batch,
       MIN(created_date)                       AS first_created,
       MAX(created_date)                       AS last_created,
       COUNT(*)                                AS unique_requests,
       MAX(copies_in_file)                     AS times_loaded_in_file,
       SUM(eligible)                           AS eligible_requests,
       SUM(eligible * closed_in_window)        AS closed_within_window,
       ROUND(100.0 * SUM(eligible * closed_in_window) / NULLIF(SUM(eligible), 0), 1) AS pct_closed_within_window
FROM observed_requests
GROUP BY batch
ORDER BY batch;
