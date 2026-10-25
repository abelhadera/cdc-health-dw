SELECT TOP 10 jurisdiction_name, pct_inpatient_occupied, pct_icu_occupied, pct_occupied_by_resp
FROM rpt.vw_hospital_occupancy
WHERE jurisdiction_type = 'State'
  AND week_ending_date = (SELECT MAX(week_ending_date) FROM dw.dim_date)
ORDER BY pct_inpatient_occupied DESC;