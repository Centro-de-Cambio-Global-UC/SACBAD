
local({

  # the requested version of renv
  version <- "1.0.7"
  sha <- attr(version, "sha", exact = TRUE)
  if (is.null(sha)) {
    sha <- "2024-02-28"
  }

  # the project directory
  project <- getwd()

  # check if renv is installed
  if (!requireNamespace("renv", quietly = TRUE)) {
    return(invisible(FALSE))
  }

  renv::activate(project = project)
  invisible(TRUE)
})
