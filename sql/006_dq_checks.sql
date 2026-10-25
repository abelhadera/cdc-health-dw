/*
  006_dq_checks.sql
  Data quality results table + procedure that runs checks after each load.

  Run in: cdc_dw (Azure SQL Database)
  Safe to re-run: yes
*/

-------------------------------------------------------------------
-- Results table
-------------------------------------------------------------------
IF OBJECT_ID('dq.check_result') IS NULL
CREATE TABLE dq.check_result (
    result_id     INT            NOT NULL IDENTITY(1,1) CONSTRAINT pk_dq_check_result PRIMARY KEY,
    load_run_id   INT            NULL CONSTRAINT fk_dq_load_run REFERENCES etl.load_run(run_id),
    check_name    VARCHAR(60)    NOT NULL,
    severity      VARCHAR(10)    NOT NULL CONSTRAINT ck_dq_severity CHECK (severity IN ('Error','Warning')),
    status        VARCHAR(4)     NOT NULL CONSTRAINT ck_dq_status   CHECK (status IN ('Pass','Fail')),
    failed_count  INT            NULL,
    details       NVARCHAR(400)  NULL,
    checked_at    DATETIME2(0)   NOT NULL CONSTRAINT df_dq_checked_at DEFAULT SYSUTCDATETIME()
);
GO

-------------------------------------------------------------------
-- DQ procedure
-------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_run_dq_checks
    @load_run_id   INT = NULL,   -- defaults to the latest successful load
    @fail_on_error BIT = 1       -- 1 = raise an error if any Error-level check fails
AS
BEGIN
    SET NOCOUNT ON;

    IF @load_run_id IS NULL
        SELECT @load_run_id = MAX(run_id) FROM etl.load_run WHERE status = 'Succeeded';

    DECLARE @r TABLE (check_name VARCHAR(60), severity VARCHAR(10), failed_count INT, details NVARCHAR(400));
    DECLARE @n INT, @cur INT, @prev INT, @max_week DATE;

    -- 1. Volume vs previous successful load
    SELECT @cur = rows_staged FROM etl.load_run WHERE run_id = @load_run_id;
    SELECT TOP 1 @prev = rows_staged
    FROM etl.load_run
    WHERE status = 'Succeeded' AND run_id < @load_run_id
    ORDER BY run_id DESC;

    INSERT @r VALUES ('volume_vs_previous_load', 'Error',
        CASE WHEN @prev IS NOT NULL AND @cur < @prev * 0.95 THEN 1 ELSE 0 END,
        CONCAT('current=', @cur, ', previous=', ISNULL(CAST(@prev AS VARCHAR(20)), 'n/a')));

    -- 2. Unknown jurisdiction codes in staging
    SELECT @n = COUNT(DISTINCT s.jurisdiction)
    FROM stg.nhsn_hrd_weekly AS s
    WHERE NOT EXISTS (SELECT 1 FROM dw.dim_jurisdiction AS j
                      WHERE j.jurisdiction_code = LTRIM(RTRIM(s.jurisdiction)));
    INSERT @r VALUES ('unknown_jurisdiction_codes', 'Error', @n,
        'Codes in staging not found in dim_jurisdiction');

    -- 3. Incomplete weeks (every week should have every jurisdiction)
    SELECT @n = COUNT(*)
    FROM (SELECT date_key
          FROM dw.fact_hospital_capacity_weekly
          GROUP BY date_key
          HAVING COUNT(*) <> (SELECT COUNT(*) FROM dw.dim_jurisdiction)) AS w;
    INSERT @r VALUES ('incomplete_weeks', 'Error', @n,
        'Weeks missing a row for one or more jurisdictions');

    -- 4. Missing weeks (gaps in the weekly sequence)
    SELECT @n = COUNT(*)
    FROM (SELECT week_ending_date,
                 LAG(week_ending_date) OVER (ORDER BY week_ending_date) AS prev_week
          FROM dw.dim_date) AS x
    WHERE prev_week IS NOT NULL AND DATEDIFF(day, prev_week, week_ending_date) <> 7;
    INSERT @r VALUES ('missing_weeks', 'Error', @n,
        'Gaps where consecutive weeks are not 7 days apart');

    -- 5. Negative values
    SELECT @n = COUNT(*)
    FROM dw.fact_resp_admissions_weekly
    WHERE new_admissions < 0 OR new_admissions_adult < 0 OR new_admissions_ped < 0
       OR hospitalized_patients < 0 OR icu_patients < 0;
    INSERT @r VALUES ('negative_values', 'Error', @n,
        'Fact rows with negative counts');

    -- 6. Duplicate keys in staging
    SELECT @n = COUNT(*)
    FROM (SELECT weekendingdate, jurisdiction
          FROM stg.nhsn_hrd_weekly
          GROUP BY weekendingdate, jurisdiction
          HAVING COUNT(*) > 1) AS d;
    INSERT @r VALUES ('duplicate_keys_in_staging', 'Warning', @n,
        'Duplicate (week, jurisdiction) pairs; extras dropped by the load');

    -- 7. Unparseable values in staging
    SELECT @n = COUNT(*)
    FROM stg.nhsn_hrd_weekly
    WHERE TRY_CONVERT(date, LEFT(weekendingdate, 10)) IS NULL
       OR (NULLIF(totalconfc19newadm, '') IS NOT NULL AND TRY_CONVERT(decimal(12,2), totalconfc19newadm) IS NULL)
       OR (NULLIF(totalconfflunewadm, '') IS NOT NULL AND TRY_CONVERT(decimal(12,2), totalconfflunewadm) IS NULL)
       OR (NULLIF(totalconfrsvnewadm, '') IS NOT NULL AND TRY_CONVERT(decimal(12,2), totalconfrsvnewadm) IS NULL)
       OR (NULLIF(numinptbeds, '')        IS NOT NULL AND TRY_CONVERT(decimal(12,2), numinptbeds)        IS NULL);
    INSERT @r VALUES ('unparseable_values_in_staging', 'Warning', @n,
        'Rows with values that failed type conversion');

    -- 8. Occupied beds exceed capacity
    SELECT @n = COUNT(*)
    FROM dw.fact_hospital_capacity_weekly
    WHERE inpatient_beds_occupied > inpatient_beds OR icu_beds_occupied > icu_beds;
    INSERT @r VALUES ('occupied_exceeds_capacity', 'Warning', @n,
        'Rows where occupied beds > total beds');

    -- 9. Age groups exceed total (adult + ped should not exceed total)
    SELECT @n = COUNT(*)
    FROM dw.fact_resp_admissions_weekly
    WHERE new_admissions_adult + new_admissions_ped > new_admissions + 0.5;
    INSERT @r VALUES ('age_groups_exceed_total', 'Warning', @n,
        'Rows where adult + pediatric admissions > total admissions');

    -- 10. Freshness
    SELECT @max_week = MAX(week_ending_date) FROM dw.dim_date;
    INSERT @r VALUES ('data_freshness', 'Warning',
        CASE WHEN DATEDIFF(day, @max_week, CAST(SYSUTCDATETIME() AS DATE)) > 14 THEN 1 ELSE 0 END,
        CONCAT('latest week = ', @max_week));

    -- Persist results
    INSERT dq.check_result (load_run_id, check_name, severity, status, failed_count, details)
    SELECT @load_run_id, check_name, severity,
           CASE WHEN failed_count > 0 THEN 'Fail' ELSE 'Pass' END,
           failed_count, details
    FROM @r;

    -- Show results (handy when running by hand)
    SELECT check_name, severity,
           CASE WHEN failed_count > 0 THEN 'Fail' ELSE 'Pass' END AS status,
           failed_count, details
    FROM @r
    ORDER BY CASE WHEN failed_count > 0 THEN 0 ELSE 1 END, severity, check_name;

    -- Fail the pipeline on any Error-level failure
    IF @fail_on_error = 1 AND EXISTS (SELECT 1 FROM @r WHERE severity = 'Error' AND failed_count > 0)
        THROW 50002, 'Data quality checks failed (Error severity). See dq.check_result.', 1;
END;
GO