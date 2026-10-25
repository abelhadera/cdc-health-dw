Select week_ending_date, pathogen_name, new_admissions,
       new_admissions_4wk_avg, wow_change, wow_pct_change
FROM rpt.vw_weekly_admissions
WHERE jurisdiction_code = 'GA'
    AND week_ending_date >= DATEADD(week, -8,(SELECT MAX(week_ending_date) FROM dw.dim_date))
ORDER BY pathogen_name, week_ending_date DESC;