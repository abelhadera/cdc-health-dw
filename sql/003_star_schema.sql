/*
  003_star_schema.sql
  Dimensions and facts for the respiratory hospital data warehouse.

  Run in: cdc_dw (Azure SQL Database)
  Safe to re-run: yes
*/

-------------------------------------------------------------------
-- Dimensions
-------------------------------------------------------------------
IF OBJECT_ID('dw.dim_date') IS NULL
CREATE TABLE dw.dim_date (
    date_key          INT          NOT NULL CONSTRAINT pk_dim_date PRIMARY KEY,  -- yyyymmdd
    week_ending_date  DATE         NOT NULL CONSTRAINT uq_dim_date_week UNIQUE,
    week_start_date   DATE         NOT NULL,
    [year]            SMALLINT     NOT NULL,
    [quarter]         TINYINT      NOT NULL,
    [month]           TINYINT      NOT NULL,
    month_name        VARCHAR(10)  NOT NULL,
    resp_season       VARCHAR(9)   NULL      -- e.g. 2025-2026
);
GO

IF OBJECT_ID('dw.dim_jurisdiction') IS NULL
CREATE TABLE dw.dim_jurisdiction (
    jurisdiction_key   SMALLINT     NOT NULL IDENTITY(1,1) CONSTRAINT pk_dim_jurisdiction PRIMARY KEY,
    jurisdiction_code  VARCHAR(10)  NOT NULL CONSTRAINT uq_dim_jurisdiction_code UNIQUE,
    jurisdiction_name  VARCHAR(60)  NOT NULL,
    jurisdiction_type  VARCHAR(20)  NOT NULL
        CONSTRAINT ck_dim_jurisdiction_type
        CHECK (jurisdiction_type IN ('State','District','Territory','HHS Region','National')),
    hhs_region         TINYINT      NULL      -- 1-10 for states/territories
);
GO

IF OBJECT_ID('dw.dim_pathogen') IS NULL
CREATE TABLE dw.dim_pathogen (
    pathogen_key   TINYINT      NOT NULL CONSTRAINT pk_dim_pathogen PRIMARY KEY,
    pathogen_code  VARCHAR(5)   NOT NULL CONSTRAINT uq_dim_pathogen_code UNIQUE,
    pathogen_name  VARCHAR(30)  NOT NULL
);
GO

-------------------------------------------------------------------
-- Facts
-------------------------------------------------------------------
-- Grain: one row per jurisdiction, per week, per pathogen
IF OBJECT_ID('dw.fact_resp_admissions_weekly') IS NULL
CREATE TABLE dw.fact_resp_admissions_weekly (
    date_key               INT            NOT NULL CONSTRAINT fk_fra_date         REFERENCES dw.dim_date(date_key),
    jurisdiction_key       SMALLINT       NOT NULL CONSTRAINT fk_fra_jurisdiction REFERENCES dw.dim_jurisdiction(jurisdiction_key),
    pathogen_key           TINYINT        NOT NULL CONSTRAINT fk_fra_pathogen     REFERENCES dw.dim_pathogen(pathogen_key),
    new_admissions         DECIMAL(12,2)  NULL,
    new_admissions_adult   DECIMAL(12,2)  NULL,
    new_admissions_ped     DECIMAL(12,2)  NULL,
    hospitalized_patients  DECIMAL(12,2)  NULL,   -- 7-day average census
    icu_patients           DECIMAL(12,2)  NULL,   -- 7-day average census
    hospitals_reporting    INT            NULL,
    _inserted_at           DATETIME2(0)   NOT NULL CONSTRAINT df_fra_inserted DEFAULT SYSUTCDATETIME(),
    _updated_at            DATETIME2(0)   NULL,
    CONSTRAINT pk_fact_resp_admissions_weekly PRIMARY KEY (date_key, jurisdiction_key, pathogen_key)
);
GO

-- Grain: one row per jurisdiction, per week
IF OBJECT_ID('dw.fact_hospital_capacity_weekly') IS NULL
CREATE TABLE dw.fact_hospital_capacity_weekly (
    date_key                 INT            NOT NULL CONSTRAINT fk_fhc_date         REFERENCES dw.dim_date(date_key),
    jurisdiction_key         SMALLINT       NOT NULL CONSTRAINT fk_fhc_jurisdiction REFERENCES dw.dim_jurisdiction(jurisdiction_key),
    inpatient_beds           DECIMAL(12,2)  NULL,
    inpatient_beds_occupied  DECIMAL(12,2)  NULL,
    icu_beds                 DECIMAL(12,2)  NULL,
    icu_beds_occupied        DECIMAL(12,2)  NULL,
    _inserted_at             DATETIME2(0)   NOT NULL CONSTRAINT df_fhc_inserted DEFAULT SYSUTCDATETIME(),
    _updated_at              DATETIME2(0)   NULL,
    CONSTRAINT pk_fact_hospital_capacity_weekly PRIMARY KEY (date_key, jurisdiction_key)
);
GO