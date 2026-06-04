#!/usr/bin/env Rscript
# Compare SHA256 of key outputs with Scripts/tests/expected_checksums.txt

repo_root <- normalizePath(getwd(), winslash = "/")
if (dir.exists(file.path(repo_root, "Scripts"))) {
  checksum_file <- file.path(repo_root, "Scripts/tests/expected_checksums.txt")
} else {
  checksum_file <- file.path(repo_root, "tests/expected_checksums.txt")
}

archivos_clave <- c(
  "Output/consolidado_export/sacbad_timeseries_anual_1988_2024.xlsx",
  "Output/Correlaciones_NDVI/datos_spei_jv.csv",
  "Output/indicadores/sacbad_spei_12_60_1988_2024.csv"
)

sha256_file <- function(path) {
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(file = path, algo = "sha256"))
  }
  if (.Platform$OS.type == "windows") {
    cmd <- sprintf(
      "(Get-FileHash -LiteralPath '%s' -Algorithm SHA256).Hash.ToLower()",
      gsub("'", "''", normalizePath(path, winslash = "/"))
    )
    out <- system2("powershell", c("-NoProfile", "-Command", cmd), stdout = TRUE)
    return(trimws(out[[length(out)]]))
  }
  stop("Install R package 'digest' for SHA256 verification.")
}

if (!file.exists(checksum_file)) {
  stop("Missing ", checksum_file)
}

expected <- read.delim(checksum_file, header = FALSE, stringsAsFactors = FALSE,
                       col.names = c("path", "hash"))
ok <- TRUE
for (i in seq_len(nrow(expected))) {
  rel <- expected$path[i]
  p <- file.path(repo_root, rel)
  if (!file.exists(p)) {
    message("MISSING: ", rel)
    ok <- FALSE
    next
  }
  cur <- sha256_file(p)
  if (!identical(cur, expected$hash[i])) {
    message("DIFF: ", rel)
    message("  expected: ", expected$hash[i])
    message("  actual:   ", cur)
    ok <- FALSE
  } else {
    message("OK: ", rel)
  }
}

if (!ok) quit(status = 1)
message("Verification complete.")
