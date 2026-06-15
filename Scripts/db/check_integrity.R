#!/usr/bin/env Rscript
# Validate primary/foreign keys and file paths in 00_Database_Registry.

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
fail <- function(msg) { message("FAIL: ", msg); ok <<- FALSE }

pk_re <- list(
  site_id = "^SITE-[A-Za-z0-9_-]+$",
  subbasin_id = "^SUBB-[A-Z0-9]+$",
  station_id = "^STN-(DGA|DMC)-[0-9]+$",
  variable_id = "^VAR-[A-Z0-9-]+$",
  file_id = "^FILE-[0-9]{4,}$"
)
nz <- function(v) { v <- v[!is.na(v)]; v[nzchar(v)] }
check_pk <- function(df, col, pattern) {
  if (anyDuplicated(df[[col]])) fail(paste(col, "duplicate PKs"))
  bad <- df[[col]][!grepl(pattern, df[[col]])]
  if (length(bad)) fail(paste(col, "invalid format:", paste(head(bad,3), collapse=", ")))
}
check_fk <- function(child, fk, parent, pk) {
  miss <- setdiff(nz(child[[fk]]), parent[[pk]])
  if (length(miss)) fail(paste(fk, "orphans:", paste(head(miss,5), collapse=", ")))
}
rd <- function(n) read_registry(n, root)

sites <- rd("sites.csv"); subbasins <- rd("subbasins.csv")
stations <- rd("stations.csv"); variables <- rd("variables.csv")
site_sub <- rd("site_subbasin.csv"); station_sub <- rd("station_subbasin.csv")

check_pk(sites, "site_id", pk_re$site_id)
check_pk(subbasins, "subbasin_id", pk_re$subbasin_id)
check_pk(stations, "station_id", pk_re$station_id)
check_pk(variables, "variable_id", pk_re$variable_id)

check_fk(sites, "subbasin_id", subbasins, "subbasin_id")
check_fk(stations, "subbasin_id", subbasins, "subbasin_id")
check_fk(site_sub, "site_id", sites, "site_id")
check_fk(site_sub, "subbasin_id", subbasins, "subbasin_id")
check_fk(station_sub, "station_id", stations, "station_id")
check_fk(station_sub, "subbasin_id", subbasins, "subbasin_id")

if (file.exists(file.path(reg, "estaciones_automaticas.csv"))) {
  ea <- rd("estaciones_automaticas.csv")
  check_fk(ea, "station_id", stations, "station_id")
  check_fk(ea, "subbasin_id", subbasins, "subbasin_id")
}

if (file.exists(file.path(reg, "data_files.csv"))) {
  files <- rd("data_files.csv")
  if (nrow(files)) {
    check_pk(files, "file_id", pk_re$file_id)
    check_fk(files, "subbasin_id", subbasins, "subbasin_id")
    check_fk(files, "variable_id", variables, "variable_id")
    for (rel in files$relative_path) if (!file.exists(file.path(root, rel))) fail(paste("Missing file:", rel))
  }
}

if (file.exists(file.path(reg, "file_contents.csv"))) {
  fc <- rd("file_contents.csv")
  files <- rd("data_files.csv")
  check_fk(fc, "file_id", files, "file_id")
  check_fk(fc, "variable_id", variables, "variable_id")
}

if (ok) { message("Integrity check passed: ", reg); quit(save="no", status=0) }
quit(save = "no", status = 1)
