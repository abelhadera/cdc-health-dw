SELECT resp_season, total_admissions, peak_week_admissions, peak_week, weeks_reported
FROM rpt.vw_season_summary
WHERE jurisdiction_code = 'USA' AND pathogen_name = 'Influenza'
ORDER BY resp_season;