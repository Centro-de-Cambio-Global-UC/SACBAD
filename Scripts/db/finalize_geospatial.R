#!/usr/bin/env Rscript
# Fase 5 (recovery-safe): 
#  - record geospatial files that no longer exist on disk (incident) for recovery
#  - register existing geospatial layers (cartography, BNA) into data_files.csv
# Does NOT move anything.

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
reg <- file.path(root, "00_Database_Registry")

sha256_file <- function(path) {
  if (requireNamespace("digest", quietly = TRUE)) return(digest::digest(file = path, algo = "sha256"))
  NA_character_
}

inv_path <- file.path(reg, "geospatial_inventory.csv")
inv <- read.csv(inv_path, stringsAsFactors = FALSE, encoding = "UTF-8", check.names = FALSE)

abspath <- function(rel) file.path(root, rel)
exists_flag <- vapply(inv$relative_path, function(r) file.exists(abspath(r)), logical(1))

lost <- inv[!exists_flag, ]
if (nrow(lost)) {
  lost_out <- data.frame(
    former_relative_path = lost$relative_path,
    format = lost$format,
    geometry_type = lost$geometry_type,
    crs_epsg = lost$crs_epsg,
    status = "deleted_pending_recovery",
    incident = "Fase5 move bug 2026-06-15; restore from OneDrive online recycle bin",
    stringsAsFactors = FALSE
  )
  write.csv(lost_out, file.path(reg, "_lost_geospatial.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  cat("Recorded", nrow(lost_out), "lost geospatial datasets in _lost_geospatial.csv\n")
} else cat("No lost geospatial files detected.\n")

# Register existing geospatial layers not yet in data_files.csv
df <- read.csv(file.path(reg, "data_files.csv"), stringsAsFactors = FALSE, encoding = "UTF-8", check.names = FALSE)
have <- df$relative_path

geo_ext <- c("shp","gpkg","geojson","tif","tiff")
geo_dirs <- c(file.path(root, "01_Geospatial_Data"))
all_geo <- unlist(lapply(geo_dirs, function(d) list.files(d, recursive = TRUE, full.names = TRUE)))
all_geo <- all_geo[tolower(tools::file_ext(all_geo)) %in% geo_ext]
rel_geo <- gsub("\\\\", "/", sub(paste0("^", gsub("\\\\","/",root), "/"), "", gsub("\\\\","/", all_geo)))

new <- rel_geo[!(rel_geo %in% have)]
if (length(new)) {
  start_n <- max(as.integer(sub("FILE-", "", df$file_id)), 0) + 1L
  rows <- lapply(seq_along(new), function(i) {
    rel <- new[i]; p <- abspath(rel); info <- file.info(p)
    data.frame(
      file_id = sprintf("FILE-%04d", start_n + i - 1L),
      relative_path = rel,
      slug = tools::file_path_sans_ext(basename(rel)),
      category = dirname(rel),
      variable_id = "", subbasin_id = "",
      temporal_coverage = "", responsible_team = "project",
      format = tools::file_ext(p), bytes = as.numeric(info$size),
      sha256 = sha256_file(p), status = "active", zenodo_doi = "",
      notes = "Geospatial layer registered in Fase 5", stringsAsFactors = FALSE
    )
  })
  df2 <- rbind(df, do.call(rbind, rows))
  write.csv(df2, file.path(reg, "data_files.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  cat("Registered", length(new), "existing geospatial layers into data_files.csv\n")
} else cat("No new geospatial layers to register.\n")
