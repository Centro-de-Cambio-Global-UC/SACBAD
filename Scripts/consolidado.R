# Excel export (Hydroclimatic sheet) — post-pipeline SACBAD

repo_root <- Sys.getenv("ASC_REPO_ROOT", unset = getwd())
dir_output <- file.path(repo_root, dir_output_proyecto)
dir_export <- file.path(dir_output, "consolidado_export")
dir_scripts <- file.path(repo_root, "Scripts")

source(file.path(dir_scripts, "funciones_utilidad.R"))
source(file.path(dir_scripts, "7_consolidado_excel.R"))

message("\n=== Excel consolidation (Hydroclimatic) ===\n")

ejecutar_consolidado_excel(
  dir_mensual                  = file.path(dir_output, "series/mensual"),
  dir_anual                    = file.path(dir_output, "series/anual"),
  dir_historico                = file.path(dir_output, "series/historico"),
  dir_indicadores              = file.path(dir_output, "indicadores"),
  grupos_estaciones            = grupos_estaciones,
  variables_activas            = variables_activas,
  calidad_por_variable         = calidad_por_variable,
  ano_inicio                   = ano_inicio,
  ano_fin                      = ano_fin,
  indicadores_activos          = indicadores_activos,
  dir_salida                   = dir_export,
  archivo_estaciones_subcuenca = NULL,
  verbose                      = TRUE
)

xlsx_ts <- file.path(
  dir_export,
  sprintf("sacbad_timeseries_anual_%s_%s.xlsx", ano_inicio, ano_fin)
)
if (file.exists(xlsx_ts) && requireNamespace("readxl", quietly = TRUE)) {
  hc <- readxl::read_excel(xlsx_ts, sheet = "Hydroclimatic", n_max = 1)
  n_cqp <- sum(grepl("\\(CQP\\)", names(hc), fixed = FALSE))
  message("  (CQP) columns in Hydroclimatic: ", n_cqp)
  message("  -> ", xlsx_ts)
}
