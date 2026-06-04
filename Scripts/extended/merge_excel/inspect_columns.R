#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
suppressPackageStartupMessages(library(readxl))
f1 <- args[1]; f2 <- args[2]; out <- args[3]
sh1 <- excel_sheets(f1)[grep("hydro", excel_sheets(f1), ignore.case = TRUE)[1]]
sh2 <- excel_sheets(f2)[grep("hydro", excel_sheets(f2), ignore.case = TRUE)[1]]
h1 <- as.data.frame(read_excel(f1, sheet = sh1))
h2 <- as.data.frame(read_excel(f2, sheet = sh2))
sink(out)
cat("FILE1 sheet:", sh1, "dim", nrow(h1), ncol(h1), "\n\n")
cat(paste(names(h1), collapse = "\n"))
cat("\n\nFILE2 sheet:", sh2, "dim", nrow(h2), ncol(h2), "\n\n")
cat(paste(names(h2), collapse = "\n"))
cat("\n\nYears file1:", paste(range(h1[[1]], na.rm = TRUE), collapse = "-"))
cat("\nYears file2:", paste(range(h2[[1]], na.rm = TRUE), collapse = "-"), "\n")
sink()
