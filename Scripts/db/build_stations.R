#!/usr/bin/env Rscript
# Fase 3: build stations registry + estaciones_automaticas from team metadata.

args <- commandArgs(trailingOnly = TRUE)
src <- args[1]   # estaciones_sacbad_pp70.csv
reg <- args[2]   # registry dir

d <- read.csv(src, sep = ";", stringsAsFactors = FALSE, encoding = "UTF-8",
              check.names = FALSE, dec = ",")
names(d) <- c("codigo_nacional","estacion","lat","lon","nombre_subcuenca",
              "calidad","id_short","id_subcuenca","name_subcuenca")

num <- function(x) as.numeric(gsub(",", ".", as.character(x)))
d$lat <- num(d$lat); d$lon <- num(d$lon); d$calidad <- round(num(d$calidad), 4)

agency <- ifelse(grepl("-", d$codigo_nacional), "DGA", "DMC")
code_clean <- gsub("[^0-9]", "", d$codigo_nacional)
d$station_id <- paste0("STN-", agency, "-", code_clean)
d$subbasin_id <- paste0("SUBB-", d$id_subcuenca)
d$agency <- agency

# estaciones_automaticas.csv
ea <- data.frame(
  station_id = d$station_id,
  codigo_nacional = d$codigo_nacional,
  name = d$estacion,
  agency = d$agency,
  lat = d$lat, lon = d$lon,
  subbasin_id = d$subbasin_id,
  calidad = d$calidad,
  variables = "VAR-PP-HYDRO;VAR-PP-CAL",
  metodo_descarga = ifelse(d$agency == "DGA", "DGA snia/explorador", "DMC explorador climatico"),
  fuente = d$agency,
  status = "active",
  stringsAsFactors = FALSE
)
# Add CQP temperature proxy station (320048) used for SPEI
ea <- rbind(ea, data.frame(
  station_id = "STN-DMC-320048", codigo_nacional = "320048",
  name = "Longotoma liceo (temperature)", agency = "DMC",
  lat = NA, lon = NA, subbasin_id = "SUBB-CQP", calidad = NA,
  variables = "VAR-TMAX;VAR-TMIN", metodo_descarga = "DMC explorador climatico",
  fuente = "DMC", status = "active", stringsAsFactors = FALSE
))
ea <- ea[order(ea$station_id), ]
write.csv(ea, file.path(reg, "estaciones_automaticas.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# stations.csv (entity registry)
st <- data.frame(
  station_id = ea$station_id,
  natural_code = ea$codigo_nacional,
  name = ea$name,
  agency = ea$agency,
  subbasin_id = ea$subbasin_id,
  lat = ea$lat, lon = ea$lon,
  status = "active",
  notes = "",
  stringsAsFactors = FALSE
)
st <- st[!duplicated(st$station_id), ]
write.csv(st, file.path(reg, "stations.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# station_subbasin.csv (bridge with role)
pp <- data.frame(station_id = d$station_id, subbasin_id = d$subbasin_id,
                 role = "pp", status = "active", stringsAsFactors = FALSE)
tmp <- data.frame(station_id = "STN-DMC-320048", subbasin_id = "SUBB-CQP",
                  role = "temp_proxy", status = "active", stringsAsFactors = FALSE)
ssb <- rbind(pp, tmp)
ssb <- ssb[!duplicated(paste(ssb$station_id, ssb$role)), ]
ssb <- ssb[order(ssb$station_id), ]
write.csv(ssb, file.path(reg, "station_subbasin.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cat("estaciones_automaticas:", nrow(ea), " stations:", nrow(st), " station_subbasin:", nrow(ssb), "\n")
cat("Subbasins covered by stations:\n")
print(sort(unique(st$subbasin_id)))
