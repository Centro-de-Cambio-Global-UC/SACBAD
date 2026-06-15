#!/usr/bin/env Rscript
# Fase 5a (CORRECTED): physically move misclassified geospatial datasets out of
# 02_Tabular_Data/04_Geospatial_Elevation_Data into 01_Geospatial_Data/03_Elevation,
# moving ALL sidecar files of each dataset and logging old->new paths.
#
# Relative path is computed by safe prefix removal (no regex), fixing the
# earlier bug that produced illegal targets.

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
reg <- args[2]

src_root <- file.path(root, "02_Tabular_Data", "04_Geospatial_Elevation_Data")
dst_root <- file.path(root, "01_Geospatial_Data", "03_Elevation")
src_root_n <- gsub("\\\\", "/", normalizePath(src_root, winslash = "/", mustWork = FALSE))

geo_ext <- c("shp", "gpkg", "geojson", "tif", "tiff")
all_files <- list.files(src_root, recursive = TRUE, full.names = TRUE)
if (!length(all_files)) { cat("Nothing to move under", src_root, "\n"); quit(save = "no") }
geo_primary <- all_files[tolower(tools::file_ext(all_files)) %in% geo_ext]

rel_of <- function(p) {
  pn <- gsub("\\\\", "/", normalizePath(p, winslash = "/", mustWork = FALSE))
  sub(paste0("^", src_root_n, "/"), "", pn, fixed = FALSE)
}

moves <- list(); moved_stems <- character()
for (f in geo_primary) {
  d <- dirname(f); stem <- tools::file_path_sans_ext(basename(f))
  key <- file.path(d, stem)
  if (key %in% moved_stems) next
  moved_stems <- c(moved_stems, key)
  siblings <- list.files(d, full.names = TRUE)
  sib <- siblings[startsWith(basename(siblings), paste0(stem, "."))]
  for (s in sib) {
    rel_after <- rel_of(s)                       # path relative to src_root
    target <- file.path(dst_root, rel_after)     # mirror under dst_root
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    ok <- file.rename(s, target)
    if (!ok) {
      cp <- file.copy(s, target, overwrite = TRUE)
      if (!isTRUE(cp)) stop("Copy failed for: ", s, " -> ", target)
      file.remove(s)
    }
    moves[[length(moves) + 1]] <- data.frame(
      old_path = paste0("02_Tabular_Data/04_Geospatial_Elevation_Data/", rel_after),
      new_path = paste0("01_Geospatial_Data/03_Elevation/", rel_after),
      stringsAsFactors = FALSE
    )
  }
}

if (length(moves)) {
  mv <- do.call(rbind, moves)
  write.csv(mv, file.path(reg, "_geospatial_moves.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  cat("Moved", nrow(mv), "files (", length(moved_stems), "datasets )\n")
} else cat("No geospatial primary files found.\n")
