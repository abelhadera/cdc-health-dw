/*
  007_reporting_views.sql
  Reporting layer: views in the rpt schema + a read-only role for report users.

  Run in: cdc_dw (Azure SQL Database)
  Safe to re-run: yes
*/

IF SCHEMA_ID('rpt') IS NULL EXEC('CREATE SCHEMA rpt');
GO

-------------------------------------------------------------------
-- Weekly admissions with trend measures
-------------------------------------------------------------------
CREATE OR ALTER VIEW rpt.vw_weekly_admissions
AS
WITH base AS (
    SELECT d.week_ending_date,
           d.resp_season,
           j.jurisdiction_code,
           j.jurisdiction_name,
           j.jurisdiction_type,
           j.hhs_region,
           p.pathogen_name,
           f.new_admissions,
           f.new_admissions_adult,
           f.new_admissions_ped,
           f.hospitalized_patients,
           f.icu_patients,
           f.hospitals_reporting,
           AVG(f.new_admissions) OVER (
               PARTITION BY f.jurisdiction_key, f.pathogen_key
               ORDER BY d.week_ending_date
               ROWS BETWEEN 3 PRECEDING AND CURRENT ROW)           AS new_admissions_4wk_avg,
           LAG(f.new_admissions) OVER (
               PARTITION BY f.jurisdiction_key, f.pathogen_key
               ORDER BY d.week_ending_date)                         AS prev_week_admissions
    FROM dw.fact_resp_admissions_weekly AS f
    JOIN dw.dim_date         AS d ON d.date_key = f.date_key
    JOIN dw.dim_jurisdiction AS j ON j.jurisdiction_key = f.jurisdiction_key
    JOIN dw.dim_pathogen     AS p ON p.pathogen_key = f.pathogen_key
)
SELECT week_ending_date, resp_season,
       jurisdiction_code, jurisdiction_name, jurisdiction_type, hhs_region,
       pathogen_name,
       new_admissions, new_admissions_adult, new_admissions_ped,
       hospitalized_patients, icu_patients, hospitals_reporting,
       CAST(new_admissions_4wk_avg AS DECIMAL(12,1))                AS new_admissions_4wk_avg,
       prev_week_admissions,
       new_admissions - prev_week_admissions                        AS wow_change,
       CAST(100.0 * (new_admissions - prev_week_admissions)
            / NULLIF(prev_week_admissions, 0) AS DECIMAL(9,1))      AS wow_pct_change
FROM base;
GO

-------------------------------------------------------------------
-- Hospital occupancy + respiratory share of patients
-------------------------------------------------------------------
CREATE OR ALTER VIEW rpt.vw_hospital_occupancy
AS
WITH resp AS (
    SELECT date_key, jurisdiction_key,
           SUM(hospitalized_patients) AS resp_patients,   -- COVID + flu + RSV (where reported)
           SUM(icu_patients)          AS resp_icu_patients
    FROM dw.fact_resp_admissions_weekly
    GROUP BY date_key, jurisdiction_key
)
SELECT d.week_ending_date,
       d.resp_season,
       j.jurisdiction_code,
       j.jurisdiction_name,
       j.jurisdiction_type,
       j.hhs_region,
       c.inpatient_beds,
       c.inpatient_beds_occupied,
       c.icu_beds,
       c.icu_beds_occupied,
       CAST(100.0 * c.inpatient_beds_occupied / NULLIF(c.inpatient_beds, 0) AS DECIMAL(6,1))  AS pct_inpatient_occupied,
       CAST(100.0 * c.icu_beds_occupied       / NULLIF(c.icu_beds, 0)       AS DECIMAL(6,1))  AS pct_icu_occupied,
       r.resp_patients,
       r.resp_icu_patients,
       CAST(100.0 * r.resp_patients     / NULLIF(c.inpatient_beds_occupied, 0) AS DECIMAL(6,1)) AS pct_occupied_by_resp,
       CAST(100.0 * r.resp_icu_patients / NULLIF(c.icu_beds_occupied, 0)       AS DECIMAL(6,1)) AS pct_icu_occupied_by_resp
FROM dw.fact_hospital_capacity_weekly AS c
JOIN dw.dim_date         AS d ON d.date_key = c.date_key
JOIN dw.dim_jurisdiction AS j ON j.jurisdiction_key = c.jurisdiction_key
LEFT JOIN resp           AS r ON r.date_key = c.date_key AND r.jurisdiction_key = c.jurisdiction_key;
GO

-------------------------------------------------------------------
-- Season summary: totals and peak week per season
-------------------------------------------------------------------
CREATE OR ALTER VIEW rpt.vw_season_summary
AS
WITH s AS (
    SELECT d.resp_season,
           f.jurisdiction_key,
           f.pathogen_key,
           d.week_ending_date,
           f.new_admissions,
           ROW_NUMBER() OVER (
               PARTITION BY d.resp_season, f.jurisdiction_key, f.pathogen_key
               ORDER BY f.new_admissions DESC) AS rn
    FROM dw.fact_resp_admissions_weekly AS f
    JOIN dw.dim_date AS d ON d.date_key = f.date_key
    WHERE d.resp_season IS NOT NULL
)
SELECT s.resp_season,
       j.jurisdiction_code,
       j.jurisdiction_name,
       j.jurisdiction_type,
       p.pathogen_name,
       SUM(s.new_admissions)                                              AS total_admissions,
       MAX(s.new_admissions)                                              AS peak_week_admissions,
       MAX(CASE WHEN s.rn = 1 AND s.new_admissions IS NOT NULL
                THEN s.week_ending_date END)                              AS peak_week,
       COUNT(*)                                                           AS weeks_in_season,
       COUNT(s.new_admissions)                                            AS weeks_reported
FROM s
JOIN dw.dim_jurisdiction AS j ON j.jurisdiction_key = s.jurisdiction_key
JOIN dw.dim_pathogen     AS p ON p.pathogen_key = s.pathogen_key
GROUP BY s.resp_season, j.jurisdiction_code, j.jurisdiction_name, j.jurisdiction_type, p.pathogen_name;
GO

-------------------------------------------------------------------
-- Read-only role for report users / dashboards
-------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID('rpt_reader') IS NULL
    CREATE ROLE rpt_reader;
GRANT SELECT ON SCHEMA::rpt TO rpt_reader;
GO