/*
  005_etl_load_dw.sql
  Load log table + procedure that loads stg.nhsn_hrd_weekly into the star schema.

  Run in: cdc_dw (Azure SQL Database)
  Safe to re-run: yes (CREATE OR ALTER)
*/

-------------------------------------------------------------------
-- Load run log
-------------------------------------------------------------------
IF OBJECT_ID('etl.load_run') IS NULL
CREATE TABLE etl.load_run (
    run_id            INT            NOT NULL IDENTITY(1,1) CONSTRAINT pk_load_run PRIMARY KEY,
    pipeline_run_id   NVARCHAR(100)  NULL,      -- ADF run ID, for tracing back to the pipeline
    started_at        DATETIME2(0)   NOT NULL,
    ended_at          DATETIME2(0)   NULL,
    status            VARCHAR(20)    NOT NULL,  -- Running / Succeeded / Failed
    rows_staged       INT            NULL,
    rows_rejected     INT            NULL,
    cap_inserted      INT            NULL,
    cap_updated       INT            NULL,
    adm_inserted      INT            NULL,
    adm_updated       INT            NULL,
    error_message     NVARCHAR(4000) NULL
);
GO

-------------------------------------------------------------------
-- Load procedure
-------------------------------------------------------------------
CREATE OR ALTER PROCEDURE etl.usp_load_dw
    @pipeline_run_id NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- any error rolls back the whole transaction

    DECLARE @run_id INT, @rows_staged INT, @rows_rejected INT;
    DECLARE @cap TABLE (act NVARCHAR(10));   -- MERGE actions for capacity fact
    DECLARE @adm TABLE (act NVARCHAR(10));   -- MERGE actions for admissions fact

    -- Log start (outside the transaction, so it survives a rollback)
    INSERT etl.load_run (pipeline_run_id, started_at, status)
    VALUES (@pipeline_run_id, SYSUTCDATETIME(), 'Running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        SELECT @rows_staged = COUNT(*) FROM stg.nhsn_hrd_weekly;
        IF @rows_staged = 0
            THROW 50001, 'Staging table is empty; nothing to load.', 1;

        ---------------------------------------------------------------
        -- 1. Type conversion (bad values become NULL, never crash)
        ---------------------------------------------------------------
        SELECT
            TRY_CONVERT(date, LEFT(s.weekendingdate, 10))                         AS week_ending_date,
            LTRIM(RTRIM(s.jurisdiction))                                           AS jurisdiction_code,
            LEFT(s.respseason, 9)                                                  AS resp_season,

            TRY_CONVERT(decimal(12,2), s.numinptbeds)                              AS inpatient_beds,
            TRY_CONVERT(decimal(12,2), s.numinptbedsocc)                           AS inpatient_beds_occupied,
            TRY_CONVERT(decimal(12,2), s.numicubeds)                               AS icu_beds,
            TRY_CONVERT(decimal(12,2), s.numicubedsocc)                            AS icu_beds_occupied,

            TRY_CONVERT(decimal(12,2), s.totalconfc19newadm)                       AS c19_new_adm,
            TRY_CONVERT(decimal(12,2), s.totalconfc19newadmadult)                  AS c19_new_adm_adult,
            TRY_CONVERT(decimal(12,2), s.totalconfc19newadmped)                    AS c19_new_adm_ped,
            TRY_CONVERT(decimal(12,2), s.totalconfc19hosppats)                     AS c19_hosp,
            TRY_CONVERT(decimal(12,2), s.totalconfc19icupats)                      AS c19_icu,
            TRY_CONVERT(int, TRY_CONVERT(decimal(12,2), s.totalconfc19newadmhosprep)) AS c19_hosprep,

            TRY_CONVERT(decimal(12,2), s.totalconfflunewadm)                       AS flu_new_adm,
            TRY_CONVERT(decimal(12,2), s.totalconfflunewadmadult)                  AS flu_new_adm_adult,
            TRY_CONVERT(decimal(12,2), s.totalconfflunewadmped)                    AS flu_new_adm_ped,
            TRY_CONVERT(decimal(12,2), s.totalconffluhosppats)                     AS flu_hosp,
            TRY_CONVERT(decimal(12,2), s.totalconffluicupats)                      AS flu_icu,
            TRY_CONVERT(int, TRY_CONVERT(decimal(12,2), s.totalconfflunewadmhosprep)) AS flu_hosprep,

            TRY_CONVERT(decimal(12,2), s.totalconfrsvnewadm)                       AS rsv_new_adm,
            TRY_CONVERT(decimal(12,2), s.totalconfrsvnewadmadult)                  AS rsv_new_adm_adult,
            TRY_CONVERT(decimal(12,2), s.totalconfrsvnewadmped)                    AS rsv_new_adm_ped,
            TRY_CONVERT(decimal(12,2), s.totalconfrsvhosppats)                     AS rsv_hosp,
            TRY_CONVERT(decimal(12,2), s.totalconfrsvicupats)                      AS rsv_icu,
            TRY_CONVERT(int, TRY_CONVERT(decimal(12,2), s.totalconfrsvnewadmhosprep)) AS rsv_hosprep
        INTO #typed
        FROM stg.nhsn_hrd_weekly AS s;

        ---------------------------------------------------------------
        -- 2. Validate: known jurisdiction, valid date, no duplicate keys
        ---------------------------------------------------------------
        SELECT t.*,
               j.jurisdiction_key,
               YEAR(t.week_ending_date) * 10000
                 + MONTH(t.week_ending_date) * 100
                 + DAY(t.week_ending_date)                                         AS date_key,
               ROW_NUMBER() OVER (PARTITION BY t.week_ending_date, j.jurisdiction_key
                                  ORDER BY (SELECT NULL))                          AS rn
        INTO #valid
        FROM #typed AS t
        JOIN dw.dim_jurisdiction AS j ON j.jurisdiction_code = t.jurisdiction_code
        WHERE t.week_ending_date IS NOT NULL;

        DELETE FROM #valid WHERE rn > 1;   -- drop duplicate keys

        SET @rows_rejected = @rows_staged - (SELECT COUNT(*) FROM #valid);

        BEGIN TRANSACTION;

        ---------------------------------------------------------------
        -- 3. dim_date: add new weeks, keep resp_season current
        ---------------------------------------------------------------
        MERGE dw.dim_date AS tgt
        USING (
            SELECT date_key, week_ending_date, MAX(resp_season) AS resp_season
            FROM #valid
            GROUP BY date_key, week_ending_date
        ) AS src
        ON tgt.date_key = src.date_key
        WHEN MATCHED AND ISNULL(tgt.resp_season, '') <> ISNULL(src.resp_season, '') THEN
            UPDATE SET resp_season = src.resp_season
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (date_key, week_ending_date, week_start_date, [year], [quarter], [month], month_name, resp_season)
            VALUES (src.date_key, src.week_ending_date, DATEADD(day, -6, src.week_ending_date),
                    YEAR(src.week_ending_date), DATEPART(quarter, src.week_ending_date),
                    MONTH(src.week_ending_date), DATENAME(month, src.week_ending_date), src.resp_season);

        ---------------------------------------------------------------
        -- 4. Capacity fact (one row per jurisdiction-week)
        ---------------------------------------------------------------
        MERGE dw.fact_hospital_capacity_weekly AS tgt
        USING (
            SELECT date_key, jurisdiction_key,
                   inpatient_beds, inpatient_beds_occupied, icu_beds, icu_beds_occupied
            FROM #valid
        ) AS src
        ON tgt.date_key = src.date_key AND tgt.jurisdiction_key = src.jurisdiction_key
        -- Update only if something actually changed (EXCEPT treats NULL = NULL)
        WHEN MATCHED AND EXISTS (
            SELECT src.inpatient_beds, src.inpatient_beds_occupied, src.icu_beds, src.icu_beds_occupied
            EXCEPT
            SELECT tgt.inpatient_beds, tgt.inpatient_beds_occupied, tgt.icu_beds, tgt.icu_beds_occupied
        ) THEN
            UPDATE SET inpatient_beds          = src.inpatient_beds,
                       inpatient_beds_occupied = src.inpatient_beds_occupied,
                       icu_beds                = src.icu_beds,
                       icu_beds_occupied       = src.icu_beds_occupied,
                       _updated_at             = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (date_key, jurisdiction_key, inpatient_beds, inpatient_beds_occupied, icu_beds, icu_beds_occupied)
            VALUES (src.date_key, src.jurisdiction_key, src.inpatient_beds, src.inpatient_beds_occupied,
                    src.icu_beds, src.icu_beds_occupied)
        OUTPUT $action INTO @cap;

        ---------------------------------------------------------------
        -- 5. Admissions fact: unpivot COVID / flu / RSV into rows
        ---------------------------------------------------------------
        WITH src AS (
            SELECT v.date_key, v.jurisdiction_key, p.pathogen_key,
                   p.new_adm, p.new_adm_adult, p.new_adm_ped, p.hosp, p.icu, p.hosprep
            FROM #valid AS v
            CROSS APPLY (VALUES
                (1, v.c19_new_adm, v.c19_new_adm_adult, v.c19_new_adm_ped, v.c19_hosp, v.c19_icu, v.c19_hosprep),
                (2, v.flu_new_adm, v.flu_new_adm_adult, v.flu_new_adm_ped, v.flu_hosp, v.flu_icu, v.flu_hosprep),
                (3, v.rsv_new_adm, v.rsv_new_adm_adult, v.rsv_new_adm_ped, v.rsv_hosp, v.rsv_icu, v.rsv_hosprep)
            ) AS p (pathogen_key, new_adm, new_adm_adult, new_adm_ped, hosp, icu, hosprep)
        )
        MERGE dw.fact_resp_admissions_weekly AS tgt
        USING src AS s
        ON  tgt.date_key = s.date_key
        AND tgt.jurisdiction_key = s.jurisdiction_key
        AND tgt.pathogen_key = s.pathogen_key
        WHEN MATCHED AND EXISTS (
            SELECT s.new_adm, s.new_adm_adult, s.new_adm_ped, s.hosp, s.icu, s.hosprep
            EXCEPT
            SELECT tgt.new_admissions, tgt.new_admissions_adult, tgt.new_admissions_ped,
                   tgt.hospitalized_patients, tgt.icu_patients, tgt.hospitals_reporting
        ) THEN
            UPDATE SET new_admissions        = s.new_adm,
                       new_admissions_adult  = s.new_adm_adult,
                       new_admissions_ped    = s.new_adm_ped,
                       hospitalized_patients = s.hosp,
                       icu_patients          = s.icu,
                       hospitals_reporting   = s.hosprep,
                       _updated_at           = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (date_key, jurisdiction_key, pathogen_key, new_admissions, new_admissions_adult,
                    new_admissions_ped, hospitalized_patients, icu_patients, hospitals_reporting)
            VALUES (s.date_key, s.jurisdiction_key, s.pathogen_key, s.new_adm, s.new_adm_adult,
                    s.new_adm_ped, s.hosp, s.icu, s.hosprep)
        OUTPUT $action INTO @adm;

        COMMIT TRANSACTION;

        -- Log success
        UPDATE etl.load_run
        SET ended_at      = SYSUTCDATETIME(),
            status        = 'Succeeded',
            rows_staged   = @rows_staged,
            rows_rejected = @rows_rejected,
            cap_inserted  = (SELECT COUNT(*) FROM @cap WHERE act = 'INSERT'),
            cap_updated   = (SELECT COUNT(*) FROM @cap WHERE act = 'UPDATE'),
            adm_inserted  = (SELECT COUNT(*) FROM @adm WHERE act = 'INSERT'),
            adm_updated   = (SELECT COUNT(*) FROM @adm WHERE act = 'UPDATE')
        WHERE run_id = @run_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        UPDATE etl.load_run
        SET ended_at      = SYSUTCDATETIME(),
            status        = 'Failed',
            rows_staged   = @rows_staged,
            error_message = ERROR_MESSAGE()
        WHERE run_id = @run_id;

        THROW;   -- re-raise so ADF marks the activity as failed
    END CATCH
END;
GO