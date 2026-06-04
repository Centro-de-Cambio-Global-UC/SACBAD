#!/usr/bin/env Rscript
# Clear saved outputs from Jupyter notebooks (removes colleague machine paths in outputs).
files <- list.files(
  "Scripts/extended",
  pattern = "\\.ipynb$",
  recursive = TRUE,
  full.names = TRUE
)
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Install jsonlite to clear notebook outputs: install.packages('jsonlite')")
}
for (f in files) {
  nb <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  if (is.null(nb$cells)) next
  for (i in seq_along(nb$cells)) {
    nb$cells[[i]]$outputs <- list()
    nb$cells[[i]]$execution_count <- list(NULL)
  }
  jsonlite::write_json(nb, f, auto_unbox = TRUE, pretty = TRUE, null = "null")
  message("cleared: ", f)
}
