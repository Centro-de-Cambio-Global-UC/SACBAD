#!/usr/bin/env Rscript
# Scan geospatial files and append/update geospatial_inventory.csv.

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

geo_ext <- c(".shp", ".gpkg", ".geojson", ".tif", ".tiff")
all_files <- list.files(root, recursive = TRUE, full.names = TRUE)
hits <- all_files[tolower(tools::file_ext(all_files)) %in% c("shp", "gpkg", "geojson", "tif", "tiff")]

# Map relative_path -> file_id from data_files if present
files_reg <- if (file.exists(file.path(reg, "data_files.csv"))) {
  read_registry("data_files.csv", root)
} else {
  data.frame()
}

existing <- if (file.exists(file.path(reg, "geospatial_inventory.csv"))) {
  read_registry("geospatial_inventory.csv", root)
} else {
  data.frame(
    file_id = character(),
    relative_path = character(),
    format = character(),
    geometry_type = character(),
    crs_epsg = character(),
    extent_xmin = numeric(),
    extent_ymin = numeric(),
    extent_xmax = numeric(),
    extent_ymax = numeric(),
    resolution_m = character(),
    n_features = character(),
    n_bands = character(),
    temporal_coverage = character(),
    variable_id = character(),
    source = character(),
    license = character(),
    notes = character(),
    stringsAsFactors = FALSE
  )
}

describe_vector <- function(path) {
  if (!requireNamespace("sf", quietly = TRUE)) return(NULL)
  x <- tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) NULL)
  if (is.null(x)) return(NULL)
  bb <- sf::st_bbox(x)
  crs <- tryCatch(sf::st_crs(x)$epsg, error = function(e) NA)
  list(
    format = toupper(tools::file_ext(path)),
    geometry_type = unique(as.character(sf::st_geometry_type(x)))[1],
    crs_epsg = if (is.na(crs)) "" else as.character(crs),
    extent_xmin = unname(bb["xmin"]),
    extent_ymin = unname(bb["ymin"]),
    extent_xmax = unname(bb["xmax"]),
    extent_ymax = unname(bb["ymax"]),
    resolution_m = "",
    n_features = as.character(nrow(x)),
    n_bands = ""
  )
}

describe_raster <- function(path) {
  if (!requireNamespace("terra", quietly = TRUE)) return(NULL)
  r <- tryCatch(terra::rast(path), error = function(e) NULL)
  if (is.null(r)) return(NULL)
  e <- terra::ext(r)
  res <- terra::res(r)[1]
  crs <- tryCatch(terra::crs(r, describe = TRUE)$code, error = function(e) "")
  list(
    format = "GEOTIFF",
    geometry_type = "raster",
    crs_epsg = crs,
    extent_xmin = e[1],
    extent_ymin = e[3],
    extent_xmax = e[2],
    extent_ymax = e[4],
    resolution_m = as.character(res),
    n_features = "",
    n_bands = as.character(terra::nlyr(r))
  )
}

rows <- list()
for (f in hits) {
  rel <- sub(paste0("^", gsub("\\\\", "/", normalizePath(root, winslash = "/")), "/?"),
             "", gsub("\\\\", "/", f))
  file_id <- ""
  if (nrow(files_reg)) {
    m <- files_reg$relative_path == rel
    if (any(m)) file_id <- files_reg$file_id[which(m)[1]]
  }
  ext <- tolower(tools::file_ext(f))
  meta <- if (ext %in% c("tif", "tiff")) describe_raster(f) else describe_vector(f)
  if (is.null(meta)) {
    meta <- list(
      format = toupper(ext), geometry_type = "", crs_epsg = "",
      extent_xmin = NA_real_, extent_ymin = NA_real_,
      extent_xmax = NA_real_, extent_ymax = NA_real_,
      resolution_m = "", n_features = "", n_bands = ""
    )
  }
  old <- existing[existing$relative_path == rel, , drop = FALSE]
  rows[[length(rows) + 1]] <- data.frame(
    file_id = if (nrow(old) && nzchar(old$file_id[1])) old$file_id[1] else file_id,
    relative_path = rel,
    format = meta$format,
    geometry_type = meta$geometry_type,
    crs_epsg = meta$crs_epsg,
    extent_xmin = meta$extent_xmin,
    extent_ymin = meta$extent_ymin,
    extent_xmax = meta$extent_xmax,
    extent_ymax = meta$extent_ymax,
    resolution_m = meta$resolution_m,
    n_features = meta$n_features,
    n_bands = meta$n_bands,
    temporal_coverage = if (nrow(old)) old$temporal_coverage[1] else "1990-2023",
    variable_id = if (nrow(old)) old$variable_id[1] else "",
    source = if (nrow(old)) old$source[1] else "",
    license = if (nrow(old)) old$license[1] else "",
    notes = if (nrow(old)) old$notes[1] else "",
    stringsAsFactors = FALSE
  )
}

if (!length(rows)) {
  message("No geospatial files found under ", root)
  quit(save = "no", status = 0)
}

out <- do.call(rbind, rows)
write_registry(out, "geospatial_inventory.csv", root)
message("Wrote geospatial_inventory.csv (", nrow(out), " layers)")
