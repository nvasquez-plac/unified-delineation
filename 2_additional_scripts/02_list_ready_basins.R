# List CAMELS-MX v01 basins and whether they are ready (structural validation passed)
# Base R only. Run on Arc:  Rscript 02_list_ready_basins.R
# Output: basin_delineation_v01/v01_basin_status.csv

out_dir <- "/work/comphyd_lab/share/dataset_develop/camels_mx/basin_delineation_v01"

# All basins that were sent to delineation (normal + large lists)
sites <- c(readLines(file.path(out_dir, "lists/basins_normal.txt")),
           readLines(file.path(out_dir, "lists/basins_large.txt")))

status <- data.frame( site_id          = sites, 
                      type             = NA, 
                      status           = "NOT_FINISHED",
                      shapefile_dir    = NA, 
                      stringsAsFactors = FALSE)

for (i in seq_along(sites)) {

  s <- sites[i]
  
  ordinary <- file.path(out_dir, s, "validation/step07_validation_summary.json")
  nested   <- file.path(out_dir, s, "validation/tdx_nested_preview/step07b_validation_summary.json")

  if (file.exists(nested)) {
    f                       <- nested 
    status$type[i]          <- "nested"
    status$shapefile_dir[i] <- file.path(out_dir, s, "tdx_nested_preview")

  } else if (file.exists(ordinary)) {
    f                       <- ordinary; status$type[i] <- "ordinary"
    status$shapefile_dir[i] <- file.path(out_dir, s, "cwarhm_exports")
  } else next

  txt              <- paste(readLines(f, warn = FALSE), collapse = "")
  passed           <- grepl('"structural_validation_pass": *true', txt)
  status$status[i] <- if (passed) "READY" else "FAILED_VALIDATION"
}

# Write files with the summary of all basins successfully delineated
write.csv( status, 
           file.path(out_dir, "v01_basin_status.csv"), 
           row.names = FALSE)

print(table(status$status, status$type, useNA = "ifany"))

cat("Ready basins:", sum(status$status == "READY"), "of", length(sites), "\n")
