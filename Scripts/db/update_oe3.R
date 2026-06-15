#!/usr/bin/env Rscript
# Fase 3/4: update OE3 WORKING copy:
#  - Sites: add ID_Subcuenca_SACBAD column (from spatial join)
#  - new sheet Estaciones_automaticas
#  - append hydroclimate/NDVI variables to Variables sheet

suppressMessages({
  library(openxlsx)
  library(readxl)
})

args <- commandArgs(trailingOnly = TRUE)
oe3 <- args[1]    # working copy
reg <- args[2]    # registry dir

sites_reg <- read.csv(file.path(reg, "sites.csv"), stringsAsFactors = FALSE, encoding = "UTF-8")
ea <- read.csv(file.path(reg, "estaciones_automaticas.csv"), stringsAsFactors = FALSE, encoding = "UTF-8")
vars <- read.csv(file.path(reg, "variables.csv"), stringsAsFactors = FALSE, encoding = "UTF-8")

wb <- loadWorkbook(oe3)

# --- Sites: add subbasin column aligned by ID_Site order ---
sites_x <- read_excel(oe3, sheet = "Sites")
sub_nat <- sub("^SUBB-", "", sites_reg$subbasin_id)
names(sub_nat) <- sites_reg$natural_code
sites_x$ID_Subcuenca_SACBAD <- ifelse(
  sites_x[["ID_Site"]] %in% names(sub_nat),
  sub_nat[sites_x[["ID_Site"]]], ""
)
new_col_idx <- ncol(sites_x)
writeData(wb, "Sites", x = data.frame(ID_Subcuenca_SACBAD = sites_x$ID_Subcuenca_SACBAD),
          startCol = new_col_idx, startRow = 1, colNames = TRUE)

# --- Estaciones_automaticas sheet ---
if ("Estaciones_automaticas" %in% names(wb)) removeWorksheet(wb, "Estaciones_automaticas")
addWorksheet(wb, "Estaciones_automaticas")
writeData(wb, "Estaciones_automaticas", ea)

# --- Append new variables to Variables sheet ---
vsheet <- read_excel(oe3, sheet = "Variables")
existing_ids <- vsheet[["ID_Variable"]]
add <- vars[!(vars$variable_id %in% existing_ids), ]
if (nrow(add)) {
  newrows <- data.frame(
    ID_Variable = add$variable_id,
    Name_Variable = add$name,
    Methodology = "Hydroclimate/Remote sensing processing (SACBAD)",
    Measurement_Unit = add$unit,
    Proccessed_data = "Processed",
    Automatization = "Derived",
    Type_Variable = "Continuous",
    Description = add$notes,
    stringsAsFactors = FALSE
  )
  start <- nrow(vsheet) + 2  # +1 header +1 next row
  writeData(wb, "Variables", newrows, startRow = start, colNames = FALSE)
  cat("Appended", nrow(newrows), "variables to Variables sheet\n")
}

saveWorkbook(wb, oe3, overwrite = TRUE)
cat("Updated OE3 working copy\n")
