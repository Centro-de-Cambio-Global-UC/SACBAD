#!/usr/bin/env Rscript

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grep("^--file=", args)])
  if (length(f)) dirname(normalizePath(f, winslash = "/")) else getwd()
}

source(file.path(script_dir(), "db_common.R"))

args <- commandArgs(trailingOnly = TRUE)
args <- parse_db_root_arg(args)
root <- db_root()
reg <- registry_dir(root)

ok <- TRUE
fail <- function(msg) {
  message("FAIL: ", msg)
  ok <<- FALSE
}

pk_re <- list(
  site_id = "^SITE-[A-Z0-9]+$",
  subbasin_id = "^SUBB-[A-Z0-9]+$",
  station_id = "^STN-DGA-[0-9]+$",
  variable_id = "^VAR-[A-Z0-9-]+$",
  file_id = "^FILE-[0-9]{4,}$"
)

check_pk <- function(df, col, pattern) {
  if (anyDuplicated(df[[col]])) fail(paste(col, "has duplicate PKs"))
  bad <- df[[col]][!grepl(pattern, df[[col]])]
  if (length(bad)) fail(paste(col, "invalid format:", paste(head(bad, 3), collapse = ", ")))
}

check_fk <- function(child, fk_col, parent, pk_col) {
  vals <- na.omit(child[[fk_col]])
  vals <- vals[nzchar(vals)]
  miss <- setdiff(vals, parent[[pk_col]])
  if (length(miss)) {
    fail(paste(fk_col, "orphans:", paste(head(miss, 5), collapse = ", ")))
  }
}

sites <- read_registry("sites.csv", root)
subbasins <- read_registry("subbasins.csv", root)
stations <- read_registry("stations.csv", root)
variables <- read_registry("variables.csv", root)
site_sub <- read_registry("site_subbasin.csv", root)
station_sub <- read_registry("station_subbasin.csv", root)

check_pk(sites, "site_id", pk_re$site_id)
check_pk(subbasins, "subbasin_id", pk_re$subbasin_id)
check_pk(stations, "station_id", pk_re$station_id)
check_pk(variables, "variable_id", pk_re$variable_id)

check_fk(site_sub, "site_id", sites, "site_id")
check_fk(site_sub, "subbasin_id", subbasins, "subbasin_id")
check_fk(station_sub, "station_id", stations, "station_id")
check_fk(station_sub, "subbasin_id", subbasins, "subbasin_id")

if (file.exists(file.path(reg, "data_files.csv"))) {
  files <- read_registry("data_files.csv", root)
  if (nrow(files)) {
    check_pk(files, "file_id", pk_re$file_id)
    check_fk(files, "subbasin_id", subbasins, "subbasin_id")
    vars_used <- unique(na.omit(files$variable_id))
    vars_used <- vars_used[nzchar(vars_used)]
    miss_var <- setdiff(vars_used, variables$variable_id)
    if (length(miss_var)) fail(paste("variable_id orphans:", paste(miss_var, collapse = ", ")))
    for (rel in files$relative_path) {
      p <- file.path(root, rel)
      if (!file.exists(p)) fail(paste("Missing file:", rel))
    }
  }
}

if (file.exists(file.path(reg, "geospatial_inventory.csv"))) {
  geo <- read_registry("geospatial_inventory.csv", root)
  if (nrow(geo) && file.exists(file.path(reg, "data_files.csv"))) {
    files <- read_registry("data_files.csv", root)
    check_fk(geo, "file_id", files, "file_id")
  }
}

if (ok) {
  message("Integrity check passed: ", reg)
  quit(save = "no", status = 0)
}
quit(save = "no", status = 1)
