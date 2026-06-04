#!/usr/bin/env Rscript
# Combine all .xlsx in a folder into one workbook (one sheet per file + master sheet)

args <- commandArgs(trailingOnly = TRUE)
input_dir <- if (length(args) >= 1) args[1] else "."
output_file <- if (length(args) >= 2) {
  args[2]
} else {
  file.path(input_dir, "Tabla3_DocPrincipal_consolidado.xlsx")
}

suppressPackageStartupMessages({
  library(readxl)
  library(openxlsx)
})

sanitize_sheet_name <- function(x, used) {
  x <- gsub("\\.xlsx$", "", x, ignore.case = TRUE)
  x <- gsub("[\\\\/:*?\\[\\]]", "_", x)
  x <- substr(x, 1, 31)
  base <- x
  i <- 1L
  while (x %in% used) {
    suf <- paste0("_", i)
    x <- paste0(substr(base, 1, 31 - nchar(suf)), suf)
    i <- i + 1L
  }
  x
}

parse_filename <- function(fname) {
  # stats_NDVIanual_SPEIanual.xlsx -> ndvi=anual, spei=anual
  core <- sub("^stats_NDVI", "", fname, ignore.case = TRUE)
  core <- sub("\\.xlsx$", "", core, ignore.case = TRUE)
  parts <- strsplit(core, "_SPEI", fixed = TRUE)[[1]]
  ndvi <- tolower(parts[1])
  spei <- if (length(parts) > 1) tolower(parts[2]) else NA_character_
  list(ndvi_season = ndvi, spei_index = spei)
}

input_dir <- normalizePath(input_dir, winslash = "/", mustWork = TRUE)
files <- sort(list.files(input_dir, pattern = "\\.xlsx$", full.names = TRUE))
files <- files[!basename(files) %in% basename(output_file)]

if (!length(files)) stop("No .xlsx files found in ", input_dir)

message("Found ", length(files), " Excel files")

master_list <- list()
sheet_names <- character()
used_names <- character()

for (f in files) {
  fname <- basename(f)
  meta <- parse_filename(fname)
  df <- as.data.frame(read_excel(f))
  df$source_file <- fname
  df$NDVI_season <- meta$ndvi_season
  df$SPEI_index <- meta$spei_index
  master_list[[fname]] <- df

  sh <- sanitize_sheet_name(fname, used_names)
  used_names <- c(used_names, sh)
  sheet_names[fname] <- sh
  message("  ", sh, " (", nrow(df), " rows)")
}

master <- do.call(rbind, master_list)
rownames(master) <- NULL

readme <- data.frame(
  item = c(
    "Source folder",
    "Files merged",
    "Sheets",
    "Master sheet",
    "Row content",
    "Filename pattern"
  ),
  description = c(
    input_dir,
    as.character(length(files)),
    "One sheet per stats_*.xlsx file",
    "Tabla3_all_combined — all tables stacked with NDVI_season and SPEI_index",
    "Land-cover stats (median, mean, Subbasin, Landcover, pixel counts, % significant)",
    "stats_NDVI{anual|prim|ver}_SPEI{anual|sep|dic}.xlsx"
  ),
  stringsAsFactors = FALSE
)

wb <- createWorkbook()
addWorksheet(wb, "README")
writeData(wb, "README", readme)
addWorksheet(wb, "Tabla3_all_combined")
writeData(wb, "Tabla3_all_combined", master, withFilter = TRUE)

for (f in files) {
  fname <- basename(f)
  df <- master_list[[fname]]
  sh <- sheet_names[fname]
  addWorksheet(wb, sh)
  writeData(
    wb, sh,
    df[, setdiff(names(df), c("source_file", "NDVI_season", "SPEI_index"))],
    withFilter = TRUE
  )
}

saveWorkbook(wb, output_file, overwrite = TRUE)
message("\nSaved: ", output_file)
