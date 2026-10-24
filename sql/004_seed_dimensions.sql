/*
  004_seed_dimensions.sql
  Seeds reference dimensions: pathogens and jurisdictions (with HHS region mapping).

  Run in: cdc_dw (Azure SQL Database)
  Safe to re-run: yes (MERGE upserts)
*/

-------------------------------------------------------------------
-- Pathogens
-------------------------------------------------------------------
MERGE dw.dim_pathogen AS tgt
USING (VALUES
    (1, 'C19', 'COVID-19'),
    (2, 'FLU', 'Influenza'),
    (3, 'RSV', 'RSV')
) AS src (pathogen_key, pathogen_code, pathogen_name)
ON tgt.pathogen_key = src.pathogen_key
WHEN MATCHED AND (tgt.pathogen_code <> src.pathogen_code OR tgt.pathogen_name <> src.pathogen_name) THEN
    UPDATE SET pathogen_code = src.pathogen_code, pathogen_name = src.pathogen_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (pathogen_key, pathogen_code, pathogen_name)
    VALUES (src.pathogen_key, src.pathogen_code, src.pathogen_name);

-------------------------------------------------------------------
-- Jurisdictions (codes match the NHSN feed exactly)
-------------------------------------------------------------------
MERGE dw.dim_jurisdiction AS tgt
USING (VALUES
    -- Region 1
    ('CT','Connecticut','State',1), ('ME','Maine','State',1), ('MA','Massachusetts','State',1),
    ('NH','New Hampshire','State',1), ('RI','Rhode Island','State',1), ('VT','Vermont','State',1),
    -- Region 2
    ('NJ','New Jersey','State',2), ('NY','New York','State',2),
    ('PR','Puerto Rico','Territory',2), ('VI','U.S. Virgin Islands','Territory',2),
    -- Region 3
    ('DE','Delaware','State',3), ('DC','District of Columbia','District',3), ('MD','Maryland','State',3),
    ('PA','Pennsylvania','State',3), ('VA','Virginia','State',3), ('WV','West Virginia','State',3),
    -- Region 4
    ('AL','Alabama','State',4), ('FL','Florida','State',4), ('GA','Georgia','State',4),
    ('KY','Kentucky','State',4), ('MS','Mississippi','State',4), ('NC','North Carolina','State',4),
    ('SC','South Carolina','State',4), ('TN','Tennessee','State',4),
    -- Region 5
    ('IL','Illinois','State',5), ('IN','Indiana','State',5), ('MI','Michigan','State',5),
    ('MN','Minnesota','State',5), ('OH','Ohio','State',5), ('WI','Wisconsin','State',5),
    -- Region 6
    ('AR','Arkansas','State',6), ('LA','Louisiana','State',6), ('NM','New Mexico','State',6),
    ('OK','Oklahoma','State',6), ('TX','Texas','State',6),
    -- Region 7
    ('IA','Iowa','State',7), ('KS','Kansas','State',7), ('MO','Missouri','State',7), ('NE','Nebraska','State',7),
    -- Region 8
    ('CO','Colorado','State',8), ('MT','Montana','State',8), ('ND','North Dakota','State',8),
    ('SD','South Dakota','State',8), ('UT','Utah','State',8), ('WY','Wyoming','State',8),
    -- Region 9
    ('AZ','Arizona','State',9), ('CA','California','State',9), ('HI','Hawaii','State',9), ('NV','Nevada','State',9),
    ('AS','American Samoa','Territory',9), ('GU','Guam','Territory',9),
    ('MP','Northern Mariana Islands','Territory',9),
    -- Region 10
    ('AK','Alaska','State',10), ('ID','Idaho','State',10), ('OR','Oregon','State',10), ('WA','Washington','State',10),
    -- HHS regions (aggregates)
    ('Region 1','HHS Region 1','HHS Region',1), ('Region 2','HHS Region 2','HHS Region',2),
    ('Region 3','HHS Region 3','HHS Region',3), ('Region 4','HHS Region 4','HHS Region',4),
    ('Region 5','HHS Region 5','HHS Region',5), ('Region 6','HHS Region 6','HHS Region',6),
    ('Region 7','HHS Region 7','HHS Region',7), ('Region 8','HHS Region 8','HHS Region',8),
    ('Region 9','HHS Region 9','HHS Region',9), ('Region 10','HHS Region 10','HHS Region',10),
    -- National
    ('USA','United States','National',NULL)
) AS src (jurisdiction_code, jurisdiction_name, jurisdiction_type, hhs_region)
ON tgt.jurisdiction_code = src.jurisdiction_code
WHEN MATCHED AND (
       tgt.jurisdiction_name <> src.jurisdiction_name
    OR tgt.jurisdiction_type <> src.jurisdiction_type
    OR ISNULL(tgt.hhs_region, 0) <> ISNULL(src.hhs_region, 0)
) THEN
    UPDATE SET jurisdiction_name = src.jurisdiction_name,
               jurisdiction_type = src.jurisdiction_type,
               hhs_region        = src.hhs_region
WHEN NOT MATCHED BY TARGET THEN
    INSERT (jurisdiction_code, jurisdiction_name, jurisdiction_type, hhs_region)
    VALUES (src.jurisdiction_code, src.jurisdiction_name, src.jurisdiction_type, src.hhs_region);