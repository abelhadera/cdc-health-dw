/*
  001_schemas_and_permissions.sql
  Creates the warehouse schemas and grants Data Factory least-privilege access.

  Run in: cdc_dw (Azure SQL Database)
  Run as: Microsoft Entra admin (required for FROM EXTERNAL PROVIDER)
  Safe to re-run: yes
*/

-- Warehouse layers
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');   -- raw loads from ADF
IF SCHEMA_ID('dw')  IS NULL EXEC('CREATE SCHEMA dw');    -- star schema
IF SCHEMA_ID('dq')  IS NULL EXEC('CREATE SCHEMA dq');    -- data quality results
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl');   -- stored procedures

-- Data Factory managed identity
IF DATABASE_PRINCIPAL_ID('adf-cdc-dw-ah') IS NULL
    CREATE USER [adf-cdc-dw-ah] FROM EXTERNAL PROVIDER;

-- Least privilege: ADF loads staging, writes DQ results, and runs procs.
-- It has no direct access to dw; procs in etl write there via ownership chaining.
GRANT SELECT, INSERT, UPDATE, DELETE, ALTER ON SCHEMA::stg TO [adf-cdc-dw-ah];
GRANT SELECT, INSERT ON SCHEMA::dq TO [adf-cdc-dw-ah];
GRANT EXECUTE ON SCHEMA::etl TO [adf-cdc-dw-ah];