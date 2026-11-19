-- One-off (director 2026-11-14, reviewed by api-ops): relabel jobs whose outcome was overwritten
-- by the :permanent-worker bug (fixed in c5f109e79) as outcome_unknown. Their real outcome is
-- lost; outcome_unknown has no Retry, so nobody re-runs a booking from them.
-- Needs the outcome_unknown status live first (fix/jobs-outcome-unknown), or reads of these rows
-- fail. Dev only: psql -v ON_ERROR_STOP=1 -d cadence_apogee_dev -f <this file>
-- Touches ONLY rows whose failure reason is exactly {job_not_running, _}; keeps that reason as
-- "previous". Prints the counts before and after; the transaction commits only if the number
-- relabelled equals the number matched.
\set ON_ERROR_STOP on
BEGIN;

SELECT 'before' AS phase, job_type, status, count(*)
  FROM background_jobs GROUP BY job_type, status ORDER BY job_type, status;

CREATE TEMP TABLE relabel_targets ON COMMIT DROP AS
  SELECT job_id FROM background_jobs
   WHERE status = 'failed'
     AND failure_reason -> 'value' -> 'tuple' ->> 0 = 'job_not_running';

SELECT 'matched' AS phase, count(*) FROM relabel_targets;

WITH relabelled AS (
  UPDATE background_jobs b
     SET status = 'outcome_unknown',
         failure_reason = jsonb_build_object(
           'value',
           jsonb_build_object('reason', 'outcome_unknown', 'previous', b.failure_reason -> 'value'))
    FROM relabel_targets t
   WHERE b.job_id = t.job_id
  RETURNING b.job_id
)
SELECT 'relabelled' AS phase, count(*) FROM relabelled;

DO $$
BEGIN
  IF (SELECT count(*) FROM background_jobs WHERE status = 'outcome_unknown'
        AND job_id IN (SELECT job_id FROM relabel_targets))
     <> (SELECT count(*) FROM relabel_targets) THEN
    RAISE EXCEPTION 'relabel count mismatch; rolling back';
  END IF;
END $$;

SELECT 'after' AS phase, job_type, status, count(*)
  FROM background_jobs GROUP BY job_type, status ORDER BY job_type, status;

COMMIT;
