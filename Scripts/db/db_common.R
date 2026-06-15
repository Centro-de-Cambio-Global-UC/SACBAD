# Shared helpers for uc365 SACBAD database registry scripts.
# Usage: set SACBAD_DB_ROOT or pass --db-root=...

db_root <- function() {
  root <- Sys.getenv("SACBAD_DB_ROOT", unset = NA_character_)
  if (!is.na(root) && nzchar(root) && dir.exists(root)) {
    return(normalizePath(root, winslash = "/", mustWork = TRUE))
  }
  stop(
    "Set SACBAD_DB_ROOT to the uc365_SACBAD Anillo 220055 - Database folder.",
    call. = FALSE
  )
}

registry_dir <- function(root = db_root()) {
  file.path(root, "00_Database_Registry")
}

read_registry <- function(name, root = db_root()) {
  path <- file.path(registry_dir(root), name)
  if (!file.exists(path)) stop("Missing registry file: ", path, call. = FALSE)
  df <- utils::read.csv(path, stringsAsFactors = FALSE, encoding = "UTF-8")
  df
}

write_registry <- function(df, name, root = db_root()) {
  path <- file.path(registry_dir(root), name)
  utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}

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
  stop("Install R package 'digest' for SHA256.", call. = FALSE)
}

parse_db_root_arg <- function(args) {
  hit <- grep("^--db-root=", args, value = TRUE)
  if (length(hit)) {
    Sys.setenv(SACBAD_DB_ROOT = sub("^--db-root=", "", hit[1]))
    args <- setdiff(args, hit)
  }
  args
}
