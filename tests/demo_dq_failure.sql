/*
  demo_dq_failure.sql
  Live demo: shows the data quality checks catching a bad record.

  Run in: cdc_dw (Azure SQL Database)
  IMPORTANT: Run each step separately (highlight + Cmd+Shift+E).
  Step 2 raises an error on purpose, which stops the batch,
  so the cleanup in Step 3 must be run on its own.
*/

-- STEP 1: Inject a record with a jurisdiction code that doesn't exist
INSERT stg.nhsn_hrd_weekly (weekendingdate, jurisdiction)
VALUES ('2026-10-17T00:00:00.000', 'XX');

-- STEP 2: Run the checks. Expect an error: unknown_jurisdiction_codes = 1
EXEC etl.usp_run_dq_checks;

-- STEP 3: Clean up (always run this after the demo)
DELETE FROM stg.nhsn_hrd_weekly WHERE jurisdiction = 'XX';

-- STEP 4: Show the failure was recorded
SELECT TOP 10 check_name, severity, status, failed_count, checked_at
FROM dq.check_result
ORDER BY result_id DESC;