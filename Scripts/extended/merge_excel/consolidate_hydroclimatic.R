#!/usr/bin/env Rscript
# =============================================================================
# Consolidate All_annual_timeseries + sacbad Hydroclimatic updates
#
# - Hydroclimatic is the FIRST sheet; data truncated at year 2023.
# - PP from All_annual renamed as "hydro year"; calendar PP added from sacbad.
# - Adds: temperature, SPEI-12 September/December from sacbad.
#
# Usage:
#   Rscript consolidate_hydroclimatic.R <all_annual.xlsx> <sacbad.xlsx> [output.xlsx] [--force]
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
force_run <- "--force" %in% args
args <- args[args != "--force"]
YEAR_MAX <- 2023L

if (length(args) < 2) {
  stop("Usage: ... <all_annual.xlsx> <sacbad.xlsx> [output.xlsx] [--force]")
}

path_all <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
path_sac <- normalizePath(args[2], winslash = "/", mustWork = TRUE)
path_out <- if (length(args) >= 3) {
  file.path(normalizePath(dirname(args[3]), winslash = "/"), basename(args[3]))
} else {
  sub("\\.xlsx$", "_consolidated.xlsx", path_all, ignore.case = TRUE)
}

suppressPackageStartupMessages({
  library(readxl)
  library(openxlsx)
})

find_hydro_sheet <- function(path) {
  sheets <- excel_sheets(path)
  hit <- sheets[grep("^hydroclimatic", sheets, ignore.case = TRUE)]
  if (!length(hit)) stop("No Hydroclimatic sheet in ", basename(path))
  hit[1]
}

read_hydro <- function(path) {
  sh <- find_hydro_sheet(path)
  message("Reading ", basename(path), " / ", sh)
  as.data.frame(read_excel(path, sheet = sh))
}

year_col <- function(df) {
  nm <- names(df)[grep("^year$", names(df), ignore.case = TRUE)][1]
  if (is.na(nm)) stop("Year column not found")
  nm
}

station_id_from_col <- function(nm) {
  trimws(sub(".*\\(([^)]+)\\)\\s*$", "\\1", nm, perl = TRUE))
}

trim_to_year <- function(df, year_max = YEAR_MAX) {
  y <- year_col(df)
  df <- df[!is.na(df[[y]]) & as.integer(df[[y]]) <= year_max, , drop = FALSE]
  df
}

#' Rename legacy All_annual PP columns to explicit hydro-year labels
label_pp_hydro_columns <- function(df) {
  pp <- grep("precipitation.*\\(mm\\)", names(df), ignore.case = TRUE, value = TRUE)
  pp <- pp[!grepl("calendar|hydro year", pp, ignore.case = TRUE)]
  for (col in pp) {
    new_nm <- sub(
      "Annual precipitation \\(mm\\)",
      "Annual precipitation hydro year (mm)",
      col,
      ignore.case = TRUE
    )
    if (new_nm == col) {
      new_nm <- paste0("Annual precipitation hydro year (mm) ", station_id_from_col(col))
    }
    names(df)[names(df) == col] <- new_nm
  }
  df
}

#' Calendar-year PP from sacbad with explicit labels
calendar_pp_columns <- function(df_sac) {
  cols <- names(df_sac)[grepl("Annual precipitation calendar \\(mm\\)", names(df_sac), ignore.case = TRUE)]
  if (!length(cols)) {
    cols <- names(df_sac)[grepl("precipitation.*calendar", names(df_sac), ignore.case = TRUE)]
  }
  cols
}

label_pp_calendar_columns <- function(df, cols) {
  out <- df[, cols, drop = FALSE]
  names(out) <- sub(
    "Annual precipitation calendar \\(mm\\)",
    "Annual precipitation calendar year (mm)",
    names(out),
    ignore.case = TRUE
  )
  out
}

find_sacbad_pp_col <- function(df_sac, station_id, prefer = c("hydro", "calendar")) {
  sid <- trimws(station_id)
  cands <- names(df_sac)[grepl("precipitation", names(df_sac), ignore.case = TRUE)]
  cands <- cands[grepl("(mm)", cands, fixed = TRUE)]
  for (pref in prefer) {
    sub <- cands[grepl(pref, cands, ignore.case = TRUE)]
    for (col in sub) {
      if (station_id_from_col(col) == sid) return(col)
    }
  }
  NULL
}

compare_series <- function(y, v_all, v_sac, tol = 1e-4) {
  m <- merge(data.frame(y = y, a = v_all), data.frame(y = y, b = v_sac), by = "y")
  a <- suppressWarnings(as.numeric(m$a))
  b <- suppressWarnings(as.numeric(m$b))
  if (!all(is.finite(a)) || !all(is.finite(b))) {
    ok <- all(trimws(as.character(m$a)) == trimws(as.character(m$b)), na.rm = FALSE)
    return(list(ok = ok, max_diff = NA_real_, n = nrow(m)))
  }
  d <- max(abs(a - b), na.rm = TRUE)
  list(ok = is.finite(d) && d <= tol, max_diff = d, n = nrow(m))
}

verify_pp_spi <- function(df_all, df_sac) {
  y <- year_col(df_all)
  ys <- year_col(df_sac)
  if (ys != y) names(df_sac)[names(df_sac) == ys] <- y

  rows <- list()
  pp_cols <- names(df_all)[grepl("precipitation.*hydro year", names(df_all), ignore.case = TRUE)]
  for (col in pp_cols) {
    sid <- station_id_from_col(col)
    sac_col <- find_sacbad_pp_col(df_sac, sid, prefer = "hydro")
    if (is.null(sac_col)) {
      rows[[length(rows) + 1]] <- data.frame(
        variable = "Precipitation (hydro year)", column_all = col, column_sac = NA,
        status = "no_sacbad_match", max_diff = NA, n_years = 0,
        stringsAsFactors = FALSE
      )
      next
    }
    cmp <- compare_series(
      df_all[[y]], df_all[[col]], df_sac[[sac_col]][match(df_all[[y]], df_sac[[y]])]
    )
    rows[[length(rows) + 1]] <- data.frame(
      variable = "Precipitation (hydro year)",
      column_all = col, column_sac = sac_col,
      status = if (cmp$ok) "OK" else "DIFF",
      max_diff = cmp$max_diff, n_years = cmp$n,
      stringsAsFactors = FALSE
    )
  }

  for (label in c("SPI-12-September", "SPI-12-December")) {
    pat <- if (label == "SPI-12-September") "SPI-12 September" else "SPI-12 December"
    cols <- names(df_all)[grepl(pat, names(df_all), fixed = TRUE)]
    for (col in cols) {
      if (!col %in% names(df_sac)) next
      cmp <- compare_series(
        df_all[[y]], df_all[[col]], df_sac[[col]][match(df_all[[y]], df_sac[[y]])]
      )
      rows[[length(rows) + 1]] <- data.frame(
        variable = label, column_all = col, column_sac = col,
        status = if (cmp$ok) "OK" else "DIFF",
        max_diff = cmp$max_diff, n_years = cmp$n,
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows)) do.call(rbind, rows) else NULL
}

columns_to_add_from_sacbad <- function(df_sac) {
  c(
    calendar_pp_columns(df_sac),
    grep("^Mean maximum temperature", names(df_sac), value = TRUE),
    grep("^Mean minimum temperature", names(df_sac), value = TRUE),
    grep("SPEI-12 September", names(df_sac), fixed = TRUE, value = TRUE),
    grep("SPEI-12 December", names(df_sac), fixed = TRUE, value = TRUE)
  )
}

merge_hydro <- function(df_all, df_sac) {
  y <- year_col(df_all)
  ys <- year_col(df_sac)
  if (ys != y) names(df_sac)[names(df_sac) == ys] <- y

  df_all <- label_pp_hydro_columns(df_all)
  df_all <- trim_to_year(df_all, YEAR_MAX)
  df_sac <- trim_to_year(df_sac, YEAR_MAX)

  add_cols <- columns_to_add_from_sacbad(df_sac)
  cal_cols <- calendar_pp_columns(df_sac)
  cal_df <- label_pp_calendar_columns(df_sac, cal_cols)

  other_add <- setdiff(add_cols, cal_cols)
  sac_sub <- df_sac[, c(y, other_add), drop = FALSE]

  out <- df_all
  drop_from_out <- intersect(c(other_add, names(cal_df)), names(out))
  if (length(drop_from_out)) out[drop_from_out] <- NULL

  out <- merge(out, sac_sub, by = y, all.x = TRUE, sort = FALSE)
  out <- merge(out, cbind(df_sac[y], cal_df), by = y, all.x = TRUE, sort = FALSE)

  ord <- order(out[[y]])
  out <- out[ord, , drop = FALSE]
  out
}

write_consolidated <- function(path_all, path_out, df_hydro, hydro_sheet) {
  sheets_all <- excel_sheets(path_all)
  hydro_exact <- sheets_all[trimws(sheets_all) == trimws(hydro_sheet)][1]
  if (is.na(hydro_exact)) hydro_exact <- hydro_sheet
  hydro_name <- "Hydroclimatic"
  others <- sheets_all[sheets_all != hydro_exact]

  wb <- createWorkbook()
  addWorksheet(wb, hydro_name)
  writeData(wb, hydro_name, df_hydro, withFilter = TRUE)

  for (sh in others) {
    message("  Copy sheet: ", sh)
    df <- as.data.frame(read_excel(path_all, sheet = sh))
    if ("Year" %in% names(df) || "year" %in% tolower(names(df))) {
      df <- trim_to_year(df, YEAR_MAX)
    }
    addWorksheet(wb, sh)
    writeData(wb, sh, df, withFilter = TRUE)
  }

  saveWorkbook(wb, path_out, overwrite = TRUE)
}

message("\n=== 1) Read Hydroclimatic ===")
df_all <- read_hydro(path_all)
df_sac <- read_hydro(path_sac)

message("\n=== 2) Verification (hydro-year PP + SPI) ===")
report <- verify_pp_spi(df_all, df_sac)
if (!is.null(report)) {
  print(report, row.names = FALSE)
  report_path <- sub("\\.xlsx$", "_verification_report.csv", path_out, ignore.case = TRUE)
  write.csv(report, report_path, row.names = FALSE)
  n_pp_diff <- sum(report$variable == "Precipitation (hydro year)" & report$status == "DIFF", na.rm = TRUE)
  if (!force_run && n_pp_diff > 0) {
    stop("PP hydro-year verification failed (", n_pp_diff, " series). Use --force to continue.")
  }
}

message("\n=== 3) Merge Hydroclimatic (hydro + calendar PP, temp, SPEI; years <= ", YEAR_MAX, ") ===")
df_merged <- merge_hydro(df_all, df_sac)
message("  Rows: ", nrow(df_merged), " | Columns: ", ncol(df_merged))
message("  PP hydro: ", sum(grepl("hydro year", names(df_merged), ignore.case = TRUE)))
message("  PP calendar: ", sum(grepl("calendar year", names(df_merged), ignore.case = TRUE)))

message("\n=== 4) Write workbook (Hydroclimatic first) ===")
sh <- find_hydro_sheet(path_all)
write_consolidated(path_all, path_out, df_merged, sh)
message("\nDone: ", path_out)
