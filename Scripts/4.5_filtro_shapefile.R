# ==============================================================================
# Script 4.5 — Filtro espacial opcional por shapefile.
#
# Para cada grupo, busca `{dir_shapefiles}/{grupo}.shp`. Si existe, recorta:
#   - El CSV de estaciones (paso 1): genera una copia con sufijo '_filtrado_shp'.
#   - Las series rellenas (paso 4) a las estaciones que caen dentro del polígono.
#
# Entrada CSV de estaciones: {grupo}_{variable}_{calidad}_{ini}_{fin}.csv
# Entrada series rellenas  : {grupo}_{var_serie}_{calidad}_{ini}_{fin}_rellena.csv
# Salidas                  : con sufijo '_filtrado_shp' (estaciones) y sin cambio
#                            de nombre dentro de dir_rellenas_filtradas (series).
# ==============================================================================

#' Normaliza el nombre de las columnas de latitud/longitud.
.columnas_latlon <- function(nms) {
  col_lat <- if ("lat" %in% nms) "lat" else if ("Lat" %in% nms) "Lat" else NULL
  col_lon <- if ("lon" %in% nms) "lon" else if ("Lon" %in% nms) "Lon" else NULL
  if (is.null(col_lat) || is.null(col_lon)) {
    stop("El CSV de estaciones debe tener columnas lat/lon (o Lat/Lon).")
  }
  list(lat = col_lat, lon = col_lon)
}

#' Devuelve los codigos_nacional que caen dentro del shapefile.
.codigos_dentro_shp <- function(estaciones, shp_sf) {
  if (nrow(estaciones) == 0) return(character(0))
  ll <- .columnas_latlon(names(estaciones))
  pts <- sf::st_as_sf(estaciones,
                      coords = c(ll$lon, ll$lat),
                      crs = 4326, remove = FALSE)
  shp_sf <- sf::st_transform(shp_sf, sf::st_crs(pts))
  dentro <- lengths(sf::st_intersects(pts, shp_sf)) > 0
  as.character(estaciones$codigo_nacional[dentro])
}

#' Recorta un CSV ancho de series a un subconjunto de códigos nacionales.
.filtrar_serie_por_codigos <- function(ruta_origen, codigos, ruta_destino,
                                       verbose = TRUE) {
  if (!file.exists(ruta_origen)) {
    if (verbose) message("  (Omitido, no existe): ", basename(ruta_origen))
    return(invisible(NULL))
  }
  if (length(codigos) == 0) {
    if (verbose) message("  (Sin estaciones dentro del shapefile) ",
                         basename(ruta_origen))
    return(invisible(NULL))
  }
  df <- leer_csv_robusto(ruta_origen)
  df <- normalizar_columnas_fecha(df)
  cols_est_actuales <- columnas_estaciones(df)

  # Match directo y alternativo ('X' + dots): codigo "06010015-2" ⇄ "X06010015.2"
  mantener <- character(0)
  for (cod in codigos) {
    if (cod %in% cols_est_actuales) {
      mantener <- c(mantener, cod)
    } else {
      alt <- paste0("X", gsub("-", ".", cod, fixed = TRUE))
      if (alt %in% cols_est_actuales) mantener <- c(mantener, alt)
    }
  }

  if (length(mantener) == 0) {
    if (verbose) message("  (Sin columnas coincidentes): ", basename(ruta_origen))
    return(invisible(NULL))
  }

  cols_fecha <- intersect(c("fecha", "year", "month", "day"), names(df))
  df_out <- df[, c(cols_fecha, mantener), drop = FALSE]
  escribir_csv_robusto(df_out, ruta_destino)
  if (verbose) {
    message("  Recortado: ", basename(ruta_origen), " → ", basename(ruta_destino),
            " (", length(mantener), " estaciones, antes ",
            length(cols_est_actuales), ")")
  }
  invisible(df_out)
}

#' Guarda un mapa diagnóstico opcional del filtrado por shapefile.
.guardar_mapa_diagnostico <- function(estaciones, shp_sf, codigos_dentro,
                                      grupo, archivo_salida, verbose = TRUE) {
  if (nrow(estaciones) == 0) return(invisible(NULL))
  ll <- .columnas_latlon(names(estaciones))
  estaciones$.dentro <- as.character(estaciones$codigo_nacional) %in% codigos_dentro
  pts <- sf::st_as_sf(estaciones, coords = c(ll$lon, ll$lat),
                      crs = 4326, remove = FALSE)
  shp_wgs <- sf::st_transform(shp_sf, 4326)
  shp_union <- sf::st_union(shp_wgs)
  bb <- sf::st_bbox(shp_union)
  dx <- (bb["xmax"] - bb["xmin"]) * 0.18
  dy <- (bb["ymax"] - bb["ymin"]) * 0.18
  xlim <- c(unname(bb["xmin"] - dx), unname(bb["xmax"] + dx))
  ylim <- c(unname(bb["ymin"] - dy), unname(bb["ymax"] + dy))
  n_in <- sum(estaciones$.dentro)
  n_out <- nrow(estaciones) - n_in

  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = shp_union, fill = NA, color = "#08519c", linewidth = 0.9) +
    ggplot2::geom_sf(data = pts,
                     ggplot2::aes(color = .data$.dentro, shape = .data$.dentro),
                     size = 2.2, stroke = 0.35) +
    ggplot2::scale_color_manual(
      name = "Shapefile",
      values = c(`TRUE` = "#238b45", `FALSE` = "#cb181d"),
      labels = c(`TRUE` = "Dentro", `FALSE` = "Fuera"),
      breaks = c(TRUE, FALSE)
    ) +
    ggplot2::scale_shape_manual(
      name = "Shapefile",
      values = c(`TRUE` = 16, `FALSE` = 4),
      labels = c(`TRUE` = "Dentro", `FALSE` = "Fuera"),
      breaks = c(TRUE, FALSE)
    ) +
    ggplot2::coord_sf(xlim = xlim, ylim = ylim, expand = FALSE,
                      crs = sf::st_crs(4326)) +
    ggplot2::labs(
      title = sprintf("%s — dentro: %d / fuera: %d (total %d)",
                      grupo, n_in, n_out, nrow(estaciones))
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "bottom",
                   plot.title = ggplot2::element_text(face = "bold"))

  if (!dir.exists(dirname(archivo_salida))) {
    dir.create(dirname(archivo_salida), recursive = TRUE)
  }
  ggplot2::ggsave(archivo_salida, p, width = 9, height = 8, dpi = 160, bg = "white")
  if (verbose) message("  Mapa guardado: ", archivo_salida)
}

#' Orquestador del paso 4.5.
#' @export
ejecutar_filtro_shapefile <- function(dir_rellenas,
                                      dir_rellenas_filtradas,
                                      dir_estaciones,
                                      dir_shapefiles,
                                      dir_mapas = NULL,
                                      grupos,
                                      variables_activas,
                                      calidad_por_variable,
                                      ano_inicio,
                                      ano_fin,
                                      actualizar_estaciones = TRUE,
                                      generar_mapas_diagnostico = TRUE,
                                      verbose = TRUE) {
  cargar_paquete_opcional("sf")
  if (!dir.exists(dir_rellenas)) stop("No existe dir_rellenas: ", dir_rellenas)
  if (!dir.exists(dir_rellenas_filtradas)) {
    dir.create(dir_rellenas_filtradas, recursive = TRUE)
  }
  if (!dir.exists(dir_shapefiles)) {
    stop("No existe la carpeta de shapefiles: ", dir_shapefiles)
  }

  mapa_variables <- list(pp = "pp", q = "q", temp = c("t_max", "t_min"))

  for (grupo in grupos) {
    archivo_shp <- file.path(dir_shapefiles, paste0(grupo, ".shp"))
    if (!file.exists(archivo_shp)) {
      if (verbose) message("  (Omitido, no existe shapefile): ", archivo_shp)
      next
    }
    if (verbose) message("--- Grupo: ", grupo, " (", basename(archivo_shp), ") ---")
    shp_sf <- sf::st_read(archivo_shp, quiet = TRUE)

    for (var in variables_activas) {
      cal <- calidad_por_variable[[var]]
      if (is.null(cal) || is.na(cal)) next

      ruta_est <- resolver_ruta_estaciones(
        dir_estaciones = dir_estaciones, grupo = grupo, variable = var,
        calidad = cal, ano_inicio = ano_inicio, ano_fin = ano_fin
      )
      if (is.null(ruta_est)) {
        if (verbose) message("  (Omitido) no hay CSV de estaciones para ", var)
        next
      }
      estaciones <- leer_csv_robusto(ruta_est)
      codigos_dentro <- .codigos_dentro_shp(estaciones, shp_sf)
      if (verbose) {
        message("  ", var, ": ", length(codigos_dentro), " / ",
                nrow(estaciones), " estaciones dentro")
      }

      if (generar_mapas_diagnostico && !is.null(dir_mapas)) {
        ruta_mapa <- file.path(
          dir_mapas,
          paste0("mapa_shp_", grupo, "_", var, "_", ano_inicio, "_", ano_fin, ".png")
        )
        .guardar_mapa_diagnostico(estaciones, shp_sf, codigos_dentro,
                                  grupo, ruta_mapa, verbose = verbose)
      }

      if (actualizar_estaciones && length(codigos_dentro) > 0) {
        est_filt <- estaciones[as.character(estaciones$codigo_nacional)
                               %in% codigos_dentro, , drop = FALSE]
        ruta_est_out <- file.path(
          dir_estaciones,
          nombre_archivo_estandar(grupo, var, cal, ano_inicio, ano_fin,
                                  sufijo = "_filtrado_shp")
        )
        escribir_csv_robusto(est_filt, ruta_est_out)
        if (verbose) message("  CSV estaciones filtradas: ", basename(ruta_est_out))
      }

      for (v_serie in mapa_variables[[var]]) {
        nombre_serie <- nombre_archivo_estandar(grupo, v_serie, cal,
                                                ano_inicio, ano_fin,
                                                sufijo = "_rellena")
        .filtrar_serie_por_codigos(
          ruta_origen  = file.path(dir_rellenas, nombre_serie),
          codigos      = codigos_dentro,
          ruta_destino = file.path(dir_rellenas_filtradas, nombre_serie),
          verbose      = verbose
        )
      }
    }
  }

  invisible(dir_rellenas_filtradas)
}
