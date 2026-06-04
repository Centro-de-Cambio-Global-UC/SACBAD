# Repository root and configuration helpers

asc_repo_root <- function() {
  root <- Sys.getenv("ASC_REPO_ROOT", unset = NA_character_)
  if (!is.na(root) && nzchar(root) && dir.exists(root)) {
    return(normalizePath(root, winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

asc_setup <- function() {
  root <- asc_repo_root()
  Sys.setenv(ASC_REPO_ROOT = root)
  if (!identical(normalizePath(getwd(), winslash = "/"), root)) {
    setwd(root)
  }
  Sys.setenv(ASC_REPO_ROOT = root)
  invisible(root)
}

asc_source_config <- function(path = Sys.getenv("ASC_CONFIG", "Scripts/config_sacbad.R")) {
  if (!file.exists(path)) stop("Configuration not found: ", path)
  source(path, local = FALSE)
  invisible(path)
}

asc_scripts_dir <- function() {
  file.path(asc_repo_root(), "Scripts")
}
