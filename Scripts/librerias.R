# ==============================================================================
# Carga de librerías del proyecto. Instala automáticamente las que faltan.
#
# Grupos:
#   Base de datos   : DBI, RPostgres, dotenv
#   Manipulación    : dplyr, tidyr, readr, stringr, lubridate, purrr
#   E/S Excel       : readxl, writexl
#   Imputación      : missForest
#   Geoespacial     : sf (opcional, sólo si usar_filtro_shapefile = TRUE)
#   Visualización   : ggplot2
# ==============================================================================

use_db_env <- tolower(Sys.getenv("ASC_USE_DB", unset = "false"))
use_db_cfg <- exists("use_database", inherits = TRUE) && isTRUE(get("use_database", inherits = TRUE))
use_db <- identical(use_db_env, "true") || use_db_cfg

bibliotecas_obligatorias <- c(
  "dplyr", "tidyr", "readr", "stringr", "lubridate", "purrr",
  "readxl", "writexl",
  "ggplot2"
)
if (use_db) {
  bibliotecas_obligatorias <- c("DBI", "RPostgres", "dotenv", bibliotecas_obligatorias)
}

# Las siguientes se cargan bajo demanda (sólo se instalan cuando se usan).
#   missForest → imputación (paso 4)
#   sf         → filtro espacial (paso 4.5)
#   trend      → tests Mann-Kendall y Theil-Sen (paso 6)
#   SPEI       → índices SPI y SPEI (paso 6)
bibliotecas_opcionales <- c("missForest", "sf", "trend", "SPEI")

instalar_si_falta <- function(paquete) {
  if (!requireNamespace(paquete, quietly = TRUE)) {
    message("Instalando paquete: ", paquete)
    install.packages(paquete, dependencies = TRUE)
  }
}

for (pkg in bibliotecas_obligatorias) {
  instalar_si_falta(pkg)
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

# Helper público para que otros scripts carguen paquetes opcionales.
cargar_paquete_opcional <- function(paquete) {
  if (!paquete %in% bibliotecas_opcionales) {
    warning("Paquete no está listado como opcional: ", paquete)
  }
  instalar_si_falta(paquete)
  suppressPackageStartupMessages(library(paquete, character.only = TRUE))
  invisible(paquete)
}
