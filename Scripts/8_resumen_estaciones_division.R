# ==============================================================================
# Script 8 — Resumen histórico por estación y división (formato informe).
#
# Genera un Excel con columnas:
#   Id, Nombre, Variable, Promedio_anual, Tendencia decadal, valor P tendencia
#
# Fuentes (join):
#   1) Metadatos de estaciones (nombre, división/subcuenca, código nacional).
#   2) Promedios del período desde resumen_historico_consolidado.xlsx o *_historico.csv.
#   3) Tendencias decadales: CSV existente en dir_tendencias o cálculo desde series anuales
#      (pendiente lm × 10 + p-valor Mann-Kendall, compatible con flujo Teniente).
#
# Salida:
#   {dir_salida}/{grupo}_resumen_historico_por_division_{ini}_{fin}.xlsx
#     - hoja "todas_las_estaciones"
#     - una hoja por división (Name_subcuenca / ID_subcuenca)
# ==============================================================================

#' Sanitiza nombre de hoja Excel (máx. 31 caracteres).
#' @keywords internal
.sanitize_sheet_name <- function(x) {
  x <- gsub("[\\\\/*?:\\[\\]]", "_", x)
  if (nchar(x) > 31) substr(x, 1, 31) else x
}

#' Carga metadatos de estaciones desde archivo_fuente del grupo o dir_estaciones.
#' @keywords internal
.cargar_metadatos_estaciones <- function(grupos_estaciones,
                                         dir_estaciones,
                                         variables_activas,
                                         calidad_por_variable,
                                         ano_inicio,
                                         ano_fin) {
  rutas <- character(0)
  for (g in grupos_estaciones) {
    if (identical(g$modo, "archivo") && !is.null(g$archivo_fuente) &&
        file.exists(g$archivo_fuente)) {
      rutas <- c(rutas, g$archivo_fuente)
    }
  }
  if (length(rutas) == 0) {
    for (v in variables_activas) {
      cal <- calidad_por_variable[[v]]
      if (is.null(cal) || is.na(cal)) next
      for (g in grupos_estaciones) {
        r <- resolver_ruta_estaciones(dir_estaciones, g$nombre, v, cal,
                                      ano_inicio, ano_fin)
        if (!is.null(r)) rutas <- c(rutas, r)
      }
    }
  }
  rutas <- unique(rutas[rutas != ""])
  if (!length(rutas)) {
    warning("resumen: sin metadatos de estaciones; Id/Nombre/División limitados.")
    return(data.frame(
      codigo_nacional = character(0),
      Nombre = character(0),
      division = character(0),
      stringsAsFactors = FALSE
    ))
  }

  filas <- list()
  for (ruta in rutas) {
    df <- tryCatch(leer_csv_autodetect(ruta), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0) next
    nms <- names(df)
    nms_l <- tolower(trimws(nms))
    icod <- which(nms_l %in% c("codigo_nacional", "codigo"))[1]
    inom <- which(nms_l %in% c("estacion", "nombre", "nombre_estacion"))[1]
    idiv <- grep("name_subcuenca|nombre_subcuenca|division", nms_l, value = FALSE)[1]
    if (is.na(icod)) next
    cod <- trimws(as.character(df[[icod]]))
    nom <- if (!is.na(inom)) trimws(as.character(df[[inom]])) else cod
    div <- if (!is.na(idiv)) trimws(as.character(df[[idiv]])) else "Sin_division"
    div[!nzchar(div)] <- "Sin_division"
    filas[[length(filas) + 1L]] <- data.frame(
      codigo_nacional = cod,
      Nombre = nom,
      division = div,
      stringsAsFactors = FALSE
    )
  }
  out <- dplyr::bind_rows(filas)
  out <- out[!is.na(out$codigo_nacional) & nzchar(out$codigo_nacional), , drop = FALSE]
  out <- out[!duplicated(out$codigo_nacional), , drop = FALSE]
  out
}

#' Lee tabla histórica ancha (una fila por variable de serie).
#' @keywords internal
.cargar_historico_ancho <- function(dir_historico,
                                    grupo,
                                    variables_activas,
                                    calidad_por_variable,
                                    ano_inicio,
                                    ano_fin,
                                    ruta_xlsx = NULL) {
  if (!is.null(ruta_xlsx) && file.exists(ruta_xlsx)) {
    if (!requireNamespace("readxl", quietly = TRUE)) {
      stop("Instala 'readxl' para leer el histórico consolidado.")
    }
    raw <- readxl::read_excel(ruta_xlsx, sheet = "todas_las_series")
    return(as.data.frame(raw))
  }

  mapa <- list(pp = "pp", temp = c("t_max", "t_min"), q = "q")
  partes <- list()
  for (v in variables_activas) {
    cal <- calidad_por_variable[[v]]
    if (is.null(cal) || is.na(cal)) next
    for (v_serie in mapa[[v]]) {
      fn <- nombre_archivo_estandar(grupo, v_serie, cal, ano_inicio, ano_fin,
                                    sufijo = "_historico")
      path <- file.path(dir_historico, fn)
      if (!file.exists(path)) next
      df <- leer_csv_robusto(path)
      df$variable <- v_serie
      partes[[length(partes) + 1L]] <- df
    }
  }
  if (!length(partes)) {
    stop("No se encontraron archivos *_historico.csv en ", dir_historico)
  }
  dplyr::bind_rows(partes)
}

#' Tendencia decadal (lm) y p-valor MK sobre serie anual.
#' @keywords internal
.tendencia_anual_estacion <- function(y) {
  y <- as.numeric(y)
  y <- y[is.finite(y)]
  if (length(y) < 4L) {
    return(list(pend_decada = NA_real_, p_valor = NA_real_))
  }
  pend <- stats::coef(stats::lm(y ~ seq_along(y)))[2] * 10
  mkp <- tryCatch(
    trend::mk.test(y)$p.value,
    error = function(e) NA_real_
  )
  list(pend_decada = unname(pend), p_valor = unname(mkp))
}

#' Calcula tendencias anuales por estación y variable (fila mes = Anual).
#' @keywords internal
.calcular_tendencias_desde_anual <- function(dir_anual,
                                             grupo,
                                             variables_activas,
                                             calidad_por_variable,
                                             ano_inicio,
                                             ano_fin) {
  cargar_paquete_opcional("trend")
  mapa <- list(pp = "pp", temp = c("t_max", "t_min"), q = "q")
  filas <- list()

  for (v in variables_activas) {
    cal <- calidad_por_variable[[v]]
    if (is.null(cal) || is.na(cal)) next
    for (v_serie in mapa[[v]]) {
      fn <- nombre_archivo_estandar(grupo, v_serie, cal, ano_inicio, ano_fin,
                                    sufijo = "_anual")
      path <- file.path(dir_anual, fn)
      if (!file.exists(path)) next
      df <- leer_csv_robusto(path)
      df <- tryCatch(normalizar_columnas_fecha(df), error = function(e) df)
      cols <- columnas_estaciones(df)
      for (est in cols) {
        tr <- .tendencia_anual_estacion(df[[est]])
        filas[[length(filas) + 1L]] <- data.frame(
          estacion = est,
          var = v_serie,
          mes = "Anual",
          pend_decada = tr$pend_decada,
          p_valor = tr$p_valor,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (!length(filas)) return(data.frame())
  dplyr::bind_rows(filas)
}

#' @export
ejecutar_resumen_estaciones_division <- function(dir_historico,
                                                 dir_anual,
                                                 dir_tendencias,
                                                 dir_salida,
                                                 dir_estaciones,
                                                 grupos_estaciones,
                                                 variables_activas,
                                                 calidad_por_variable,
                                                 ano_inicio,
                                                 ano_fin,
                                                 columna_division = "Name_subcuenca",
                                                 ruta_historico_xlsx = NULL,
                                                 ruta_tendencias_csv = NULL,
                                                 nombre_archivo = NULL,
                                                 verbose = TRUE) {
  if (!dir.exists(dir_salida)) dir.create(dir_salida, recursive = TRUE)
  if (!dir.exists(dir_tendencias)) dir.create(dir_tendencias, recursive = TRUE)

  meta <- .cargar_metadatos_estaciones(
    grupos_estaciones, dir_estaciones, variables_activas,
    calidad_por_variable, ano_inicio, ano_fin
  )

  for (grupo in grupos_estaciones) {
    gnom <- grupo$nombre
    if (verbose) message("[8] Resumen histórico · grupo=", gnom)

    ruta_xlsx <- ruta_historico_xlsx
    if (is.null(ruta_xlsx)) {
      ruta_xlsx <- file.path(dir_historico, "resumen_historico_consolidado.xlsx")
    }

    raw <- tryCatch(
      .cargar_historico_ancho(
        dir_historico, gnom, variables_activas, calidad_por_variable,
        ano_inicio, ano_fin, ruta_xlsx = ruta_xlsx
      ),
      error = function(e) {
        warning("[8] ", gnom, ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(raw) || nrow(raw) == 0) next

    meta_cols <- c(
      "archivo_fuente", "grupo", "variable", "estadistico",
      "fecha_inicio_periodo", "fecha_fin_periodo"
    )
    meta_cols <- intersect(meta_cols, names(raw))
    station_cols <- setdiff(names(raw), meta_cols)

    raw <- raw |>
      dplyr::mutate(
        Variable = dplyr::case_when(
          .data$variable %in% c("pp", "q", "t_max", "t_min") ~ .data$variable,
          grepl("pp", .data$archivo_fuente, ignore.case = TRUE) ~ "pp",
          grepl("t_max", .data$archivo_fuente, ignore.case = TRUE) ~ "t_max",
          grepl("t_min", .data$archivo_fuente, ignore.case = TRUE) ~ "t_min",
          grepl("_q_", .data$archivo_fuente, ignore.case = TRUE) ~ "q",
          TRUE ~ as.character(.data$variable)
        )
      )

    # Tendencias
    ruta_tend <- ruta_tendencias_csv
    if (is.null(ruta_tend)) {
      ruta_tend <- file.path(dir_tendencias,
                             paste0(gnom, "_Tendencias_decadales.csv"))
    }
    if (file.exists(ruta_tend)) {
      if (verbose) message("  → tendencias desde ", basename(ruta_tend))
      tend_anual <- leer_csv_robusto(ruta_tend) |>
        dplyr::filter(as.character(.data$mes) == "Anual") |>
        dplyr::mutate(
          estacion = as.character(.data$estacion),
          var = dplyr::case_when(
            .data$var %in% c("Tx", "tx") ~ "t_max",
            .data$var %in% c("Tn", "tn") ~ "t_min",
            TRUE ~ as.character(.data$var)
          )
        ) |>
        dplyr::select(estacion, var, pend_decada, p_valor)
    } else {
      if (verbose) message("  → calculando tendencias desde series anuales")
      tend_anual <- .calcular_tendencias_desde_anual(
        dir_anual, gnom, variables_activas, calidad_por_variable,
        ano_inicio, ano_fin
      )
      if (nrow(tend_anual) > 0) {
        escribir_csv_robusto(tend_anual, ruta_tend)
        if (verbose) message("  → guardado ", basename(ruta_tend))
      }
    }

    long <- raw |>
      dplyr::select(Variable, dplyr::all_of(station_cols)) |>
      tidyr::pivot_longer(
        cols = dplyr::all_of(station_cols),
        names_to = "codigo_nacional",
        values_to = "Promedio_anual"
      ) |>
      dplyr::mutate(codigo_nacional = as.character(.data$codigo_nacional))

    # Id 1..N por estación (mismo Id para todas las variables de la misma estación)
    codigos_datos <- sort(unique(long$codigo_nacional))
    meta_g <- meta
    faltan_meta <- setdiff(codigos_datos, meta_g$codigo_nacional)
    if (length(faltan_meta) > 0) {
      meta_g <- dplyr::bind_rows(
        meta_g,
        data.frame(
          codigo_nacional = faltan_meta,
          Nombre = faltan_meta,
          division = "Sin_division",
          stringsAsFactors = FALSE
        )
      )
    }
    meta_g <- meta_g[meta_g$codigo_nacional %in% codigos_datos, , drop = FALSE]
    meta_g <- meta_g |>
      dplyr::arrange(.data$division, .data$Nombre, .data$codigo_nacional) |>
      dplyr::mutate(Id = dplyr::dense_rank(.data$codigo_nacional))

    out <- long |>
      dplyr::left_join(meta_g, by = "codigo_nacional") |>
      dplyr::left_join(
        tend_anual,
        by = c("codigo_nacional" = "estacion", "Variable" = "var")
      ) |>
      dplyr::transmute(
        Id = .data$Id,
        Nombre = dplyr::coalesce(.data$Nombre, .data$codigo_nacional),
        Variable = .data$Variable,
        Promedio_anual = as.numeric(.data$Promedio_anual),
        `Tendencia decadal` = .data$pend_decada,
        `valor P tendencia` = .data$p_valor,
        division = dplyr::coalesce(.data$division, "Sin_division")
      ) |>
      dplyr::filter(is.finite(.data$Promedio_anual)) |>
      dplyr::arrange(.data$Id, .data$Variable)

    if (nrow(out) == 0) {
      warning("[8] ", gnom, ": sin filas tras el join.")
      next
    }

    nm_out <- nombre_archivo
    if (is.null(nm_out) || !nzchar(nm_out)) {
      nm_out <- paste0(gnom, "_resumen_historico_por_division_",
                       ano_inicio, "_", ano_fin, ".xlsx")
    }
    ruta_out <- file.path(dir_salida, nm_out)

    hojas <- list()
    hojas[["todas_las_estaciones"]] <- out[, c(
      "Id", "Nombre", "Variable", "Promedio_anual",
      "Tendencia decadal", "valor P tendencia"
    )]

    divs <- sort(unique(out$division))
    for (d in divs) {
      sub <- out[out$division == d, , drop = FALSE]
      hojas[[.sanitize_sheet_name(d)]] <- sub[, c(
        "Id", "Nombre", "Variable", "Promedio_anual",
        "Tendencia decadal", "valor P tendencia"
      )]
    }

    escribir_xlsx_robusto(hojas, ruta_out)
    if (verbose) {
      message("  → ", basename(ruta_out),
              " (", length(hojas), " hojas, ", nrow(out), " filas)")
    }
  }

  invisible(dir_salida)
}
