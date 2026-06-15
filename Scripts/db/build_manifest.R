#!/usr/bin/env Rscript
# Build MANIFEST.csv (SHA256 inventory) for uc365 database root.
# Use --scope=team to scan only registry + incorporated team products.

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grep("^--file=", args)])
  if (length(f)) dirname(normalizePath(f, winslash = "/")) else getwd()
}

source(file.path(script_dir(), "db_common.R"))

args <- commandArgs(trailingOnly = TRUE)
args <- parse_db_root_arg(args)
root <- db_root()
out_path <- file.path(root, "MANIFEST.csv")
version <- format(Sys.Date(), "%Y-%m-%d")

scope <- "full"
if (any(args == "--scope=team")) {
  scope <- "team"
  args <- setdiff(args, "--scope=team")
}
if (length(args) && !grepl("^--", args[1])) version <- args[1]

scan_roots <- if (scope == "team") {
  c(
    file.path(root, "00_Database_Registry"),
    file.path(root, "02_Tabular_Data/16_Hydroclimate_Subbasin_Timeseries"),
    file.path(root, "01_Geospatial_Data/01_Remote_Sensing")
  )
} else {
  root
}

collect_files <- function(base) {
  if (!dir.exists(base)) return(character())
  list.files(base, recursive = TRUE, full.names = TRUE)
}

all_files <- if (scope == "team") {
  unique(unlist(lapply(scan_roots, collect_files)))
} else {
  list.files(root, recursive = TRUE, full.names = TRUE)
}

all_files <- all_files[!grepl("desktop\\.ini$", all_files, ignore.case = TRUE)]
all_files <- all_files[!grepl("[/\\\\]\\.git[/\\\\]", gsub("\\\\", "/", all_files))]

root_norm <- gsub("\\\\", "/", normalizePath(root, winslash = "/"))
rel_paths <- sub(paste0("^", root_norm, "/?"), "", gsub("\\\\", "/", all_files))

rows <- lapply(seq_along(all_files), function(i) {
  f <- all_files[i]
  rel <- rel_paths[i]
  info <- file.info(f)
  data.frame(
    relative_path = rel,
    sha256 = sha256_file(f),
    bytes = as.numeric(info$size),
    last_modified = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    snapshot_version = version,
    stringsAsFactors = FALSE
  )
})

manifest <- do.call(rbind, rows)
utils::write.csv(manifest, out_path, row.names = FALSE, fileEncoding = "UTF-8")
message("Wrote ", nrow(manifest), " entries (scope=", scope, ") to ", out_path)
