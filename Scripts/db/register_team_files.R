#!/usr/bin/env Rscript
# Register team analytical files in data_files.csv (run after file migration).

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grep("^--file=", args)])
  if (length(f)) dirname(normalizePath(f, winslash = "/")) else getwd()
}

source(file.path(script_dir(), "db_common.R"))

args <- commandArgs(trailingOnly = TRUE)
args <- parse_db_root_arg(args)
root <- db_root()

entries <- list(
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/02_Processed/All_annual_timeseries.xlsx",
       "hydroclimate_master", "VAR-PP-HYDRO", "SUBB-CQP", "1990-2023", "team"),
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/03_Results/Publication_Tables/figure4_data.xlsx",
       "figure4", "", "", "1990-2023", "team"),
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/03_Results/Publication_Tables/figure5_data.xlsx",
       "figure5", "", "", "1990-2023", "team"),
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/03_Results/Publication_Tables/figure6_data.xlsx",
       "figure6", "VAR-NDVI-ANUAL", "", "1990-2023", "team"),
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/03_Results/Publication_Tables/Table3_data.xlsx",
       "table3", "VAR-NDVI-SPEI-CORR", "", "1990-2023", "team"),
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/03_Results/Publication_Tables/figS1_data.xlsx",
       "figS1", "", "", "1990-2023", "team"),
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/05_Metadata/SACBAD_data_dictionary.xlsx",
       "data_dictionary", "", "", "", "team"),
  list("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/05_Metadata/TEAM_ZENODO_README.txt",
       "zenodo_readme", "", "", "", "team")
)

# SPEI G Q VIIRS folder
spei_dir <- file.path(root, "02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/02_Processed/Correlations_SPEI_G_Q_VIIRS")
if (dir.exists(spei_dir)) {
  for (f in list.files(spei_dir, full.names = FALSE)) {
    entries[[length(entries) + 1]] <- list(
      file.path("02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries/02_Processed/Correlations_SPEI_G_Q_VIIRS", f),
      tools::file_path_sans_ext(f), "VAR-SPEI12", "", "1990-2023", "team"
    )
  }
}

# NDVI CSVs
ndvi_dir <- file.path(root, "01_Geospatial_Data/01_Remote_Sensing/01_NDVI/02_Processed/NDVI_anual_est_csv")
if (dir.exists(ndvi_dir)) {
  for (f in list.files(ndvi_dir, pattern = "\\.csv$", full.names = FALSE)) {
    sub_id <- sub("^NDVI_([A-Z]+)anual.*", "\\1", f)
    subbasin <- if (grepl("^[A-Z]+$", sub_id)) paste0("SUBB-", sub_id) else ""
    entries[[length(entries) + 1]] <- list(
      file.path("01_Geospatial_Data/01_Remote_Sensing/01_NDVI/02_Processed/NDVI_anual_est_csv", f),
      tools::file_path_sans_ext(f), "VAR-NDVI-ANUAL", subbasin, "1990-2023", "team"
    )
  }
}

# GeoTIFF correlations
geo_root <- file.path(root, "01_Geospatial_Data/01_Remote_Sensing/02_NDVI_SPEI_Correlations")
if (dir.exists(geo_root)) {
  tifs <- list.files(geo_root, pattern = "\\.tif$", recursive = TRUE, full.names = FALSE)
  for (rel in tifs) {
    entries[[length(entries) + 1]] <- list(
      file.path("01_Geospatial_Data/01_Remote_Sensing/02_NDVI_SPEI_Correlations", rel),
      tools::file_path_sans_ext(basename(rel)), "VAR-NDVI-SPEI-CORR", "", "1990-2023", "team"
    )
  }
}

rows <- list()
n <- 0L
for (e in entries) {
  rel <- e[[1]]
  path <- file.path(root, rel)
  if (!file.exists(path)) next
  n <- n + 1L
  info <- file.info(path)
  rows[[n]] <- data.frame(
    file_id = sprintf("FILE-%04d", n),
    relative_path = gsub("\\\\", "/", rel),
    slug = e[[2]],
    category = dirname(rel),
    variable_id = e[[3]],
    subbasin_id = e[[4]],
    temporal_coverage = e[[5]],
    responsible_team = e[[6]],
    format = tools::file_ext(path),
    bytes = as.numeric(info$size),
    sha256 = sha256_file(path),
    status = "active",
    zenodo_doi = "",
    notes = "Incorporated from team Bases de datos nuevas",
    stringsAsFactors = FALSE
  )
}

df <- do.call(rbind, rows)
write_registry(df, "data_files.csv", root)
message("Registered ", nrow(df), " files in data_files.csv")
