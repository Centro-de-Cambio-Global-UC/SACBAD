#!/usr/bin/env Rscript
# Fase 1/3: assign SACBAD subbasin to each OE3 Site via spatial join with
# BNA SubSubCuencas, using a documented COD_SSUBC -> subbasin_id crosswalk.
# Writes sites.csv, site_subbasin.csv and bna_subbasin_crosswalk.csv.

suppressMessages({
  library(sf)
  library(readxl)
})

args <- commandArgs(trailingOnly = TRUE)
oe3 <- args[1]      # OE3 working copy
shp <- args[2]      # BNA shapefile
reg <- args[3]      # 00_Database_Registry dir

# COD_SSUBC -> SACBAD subbasin (from hydrological analysis of BNA codes)
cw <- data.frame(
  cod_ssubc = c("04900","04901","04902","05000","05100","05101",
                "05110","05111","05120","05200","05210","05211","05220","05221"),
  subbasin_id = c("SUBB-UQ","SUBB-MQ","SUBB-LQ","SUBB-CQP","SUBB-UP","SUBB-UP",
                  "SUBB-MP","SUBB-MP","SUBB-LP","SUBB-UL","SUBB-ML","SUBB-ML",
                  "SUBB-LL","SUBB-LL"),
  stringsAsFactors = FALSE
)

sites <- read_excel(oe3, sheet = "Sites")
east <- suppressWarnings(as.numeric(as.character(sites[["Easting (WGS84 19S)"]])))
north <- suppressWarnings(as.numeric(as.character(sites[["Northing (WGS84 19S)"]])))

base <- data.frame(
  site_id = paste0("SITE-", sites[["ID_Site"]]),
  natural_code = sites[["ID_Site"]],
  name = sites[["Name_Site"]],
  locality = sites[["Site_Locality"]],
  zone_sacbad = sites[["Zone_SACBAD"]],
  type_site = sites[["Type_Site"]],
  easting = east, northing = north,
  stringsAsFactors = FALSE
)

keep <- !is.na(east) & !is.na(north)
pts <- st_as_sf(base[keep, ], coords = c("easting", "northing"),
                crs = 32719, remove = FALSE)

bna <- st_make_valid(st_transform(st_read(shp, quiet = TRUE), 32719))
j <- st_join(pts, bna[, c("COD_SSUBC", "NOM_SSUBC")], left = TRUE)
jd <- st_drop_geometry(j)

jd$subbasin_id <- cw$subbasin_id[match(jd$COD_SSUBC, cw$cod_ssubc)]

# Merge back to all sites (including those without coords)
res <- merge(base, jd[, c("site_id", "COD_SSUBC", "NOM_SSUBC", "subbasin_id")],
             by = "site_id", all.x = TRUE, sort = FALSE)

res$status <- ifelse(is.na(res$easting) | is.na(res$northing), "no_coords",
              ifelse(is.na(res$COD_SSUBC), "marine_or_offshore",
              ifelse(is.na(res$subbasin_id), "out_of_scope_coastal", "active")))
res$notes <- ifelse(res$status == "out_of_scope_coastal",
                    paste0("Outside SACBAD 10 subbasins; BNA=", res$NOM_SSUBC), "")

sites_out <- data.frame(
  site_id = res$site_id,
  natural_code = res$natural_code,
  name = res$name,
  locality = res$locality,
  zone_sacbad = res$zone_sacbad,
  type_site = res$type_site,
  easting = res$easting,
  northing = res$northing,
  subbasin_id = ifelse(is.na(res$subbasin_id), "", res$subbasin_id),
  bna_cod_ssubc = ifelse(is.na(res$COD_SSUBC), "", res$COD_SSUBC),
  bna_nom_ssubc = ifelse(is.na(res$NOM_SSUBC), "", res$NOM_SSUBC),
  status = res$status,
  notes = res$notes,
  stringsAsFactors = FALSE
)
sites_out <- sites_out[order(sites_out$site_id), ]
write.csv(sites_out, file.path(reg, "sites.csv"), row.names = FALSE, fileEncoding = "UTF-8")

ss <- sites_out[nzchar(sites_out$subbasin_id),
                c("site_id", "subbasin_id")]
ss$method <- "spatial_join_BNA_SubSubCuencas"
ss$status <- "active"
write.csv(ss, file.path(reg, "site_subbasin.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cwfull <- merge(
  cw,
  unique(st_drop_geometry(bna)[, c("COD_SSUBC", "NOM_SSUBC")]),
  by.x = "cod_ssubc", by.y = "COD_SSUBC", all.x = TRUE
)
names(cwfull)[names(cwfull) == "NOM_SSUBC"] <- "bna_nom_ssubc"
write.csv(cwfull[order(cwfull$cod_ssubc), ],
          file.path(reg, "bna_subbasin_crosswalk.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

cat("Sites written:", nrow(sites_out), "\n")
print(table(sites_out$status))
cat("\nSubbasin assignment:\n")
print(table(sites_out$subbasin_id[nzchar(sites_out$subbasin_id)]))
