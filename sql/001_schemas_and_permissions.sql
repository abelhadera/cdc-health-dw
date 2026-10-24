-- Check who you're signed in as (should be your Outlook account, not sqladmin)
SELECT SUSER_NAME() AS signed_in_as;

-- Layers of the warehouse
EXEC('CREATE SCHEMA stg');   -- raw loads land here
EXEC('CREATE SCHEMA dw');    -- star schema
EXEC('CREATE SCHEMA dq');    -- data quality results
EXEC('CREATE SCHEMA etl');   -- stored procedures

-- Data Factory's identity, with only the access it needs
CREATE USER [adf-cdc-dw-ah] FROM EXTERNAL PROVIDER;
GRANT SELECT, INSERT, UPDATE, DELETE, ALTER ON SCHEMA::stg TO [adf-cdc-dw-ah];
GRANT SELECT, INSERT ON SCHEMA::dq TO [adf-cdc-dw-ah];
GRANT EXECUTE ON SCHEMA::etl TO [adf-cdc-dw-ah];