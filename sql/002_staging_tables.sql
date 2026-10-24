/*
  002_staging_tables.sql
  Staging table for NHSN Weekly Hospital Respiratory Data (data.cdc.gov ua7e-t2fy).
  Columns are stored as text, exactly as received; typing happens in etl procs.

  Run in: cdc_dw (Azure SQL Database)
  Safe to re-run: yes
*/

IF OBJECT_ID('stg.nhsn_hrd_weekly') IS NULL
CREATE TABLE stg.nhsn_hrd_weekly (
    -- Keys and season
    weekendingdate               NVARCHAR(30)  NULL,
    jurisdiction                 NVARCHAR(20)  NULL,
    respseason                   NVARCHAR(20)  NULL,

    -- Hospital capacity (7-day averages)
    numinptbeds                  NVARCHAR(30)  NULL,
    numinptbedsocc               NVARCHAR(30)  NULL,
    numicubeds                   NVARCHAR(30)  NULL,
    numicubedsocc                NVARCHAR(30)  NULL,

    -- COVID-19
    totalconfc19newadm           NVARCHAR(30)  NULL,
    totalconfc19newadmadult      NVARCHAR(30)  NULL,
    totalconfc19newadmped        NVARCHAR(30)  NULL,
    totalconfc19hosppats         NVARCHAR(30)  NULL,
    totalconfc19icupats          NVARCHAR(30)  NULL,
    totalconfc19newadmhosprep    NVARCHAR(30)  NULL,

    -- Influenza
    totalconfflunewadm           NVARCHAR(30)  NULL,
    totalconfflunewadmadult      NVARCHAR(30)  NULL,
    totalconfflunewadmped        NVARCHAR(30)  NULL,
    totalconffluhosppats         NVARCHAR(30)  NULL,
    totalconffluicupats          NVARCHAR(30)  NULL,
    totalconfflunewadmhosprep    NVARCHAR(30)  NULL,

    -- RSV
    totalconfrsvnewadm           NVARCHAR(30)  NULL,
    totalconfrsvnewadmadult      NVARCHAR(30)  NULL,
    totalconfrsvnewadmped        NVARCHAR(30)  NULL,
    totalconfrsvhosppats         NVARCHAR(30)  NULL,
    totalconfrsvicupats          NVARCHAR(30)  NULL,
    totalconfrsvnewadmhosprep    NVARCHAR(30)  NULL,

    -- Load metadata
    _source_file                 NVARCHAR(400) NULL,
    _loaded_at                   DATETIME2(0)  NOT NULL
        CONSTRAINT df_stg_nhsn_loaded_at DEFAULT SYSUTCDATETIME()
);