# -*- coding: utf-8 -*-
"""
Created on Wed Sep 27 13:26:38 2023

@author: SACBAD supplementary repo
"""

import ee
import geemap
import os
import geopandas as gpd
import rasterio
from scipy import ndimage
import numpy as np
import cv2
from rasterio import features
from rasterio.features import geometry_mask
from scipy.signal import find_peaks
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import find_peaks, peak_prominences
from scipy.interpolate import interp1d
from scipy.ndimage import label
from rasterio.warp import calculate_default_transform, reproject, Resampling
from datetime import datetime 
import csv
from rasterio.features import shapes
def adquirir_fecha_hora_sentinel(ruta_csv, geometria):
    start_date = '2015-01-01'
    end_date = '2023-12-31'
    sentinel_collection = ee.ImageCollection("COPERNICUS/S2_HARMONIZED") \
        .filterBounds(geometria) \
        .filterDate(start_date, end_date) \
        .filterMetadata('CLOUDY_PIXEL_PERCENTAGE', 'less_than', 5) \
        .filterMetadata('MEAN_SOLAR_ZENITH_ANGLE', 'less_than', 78)

    image_list = sentinel_collection.aggregate_array('system:id').getInfo()

    with open(ruta_csv, mode='w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['Image_ID', 'Date', 'Time'])

        for image_id in image_list:
            # Extraer la fecha y hora del ID de la imagen
            date_str = image_id.split('/')[-1].split('T')[0]
            time_str = image_id.split('/')[-1].split('T')[1][:6]
            date = datetime.strptime(date_str, "%Y%m%d").strftime("%Y-%m-%d")
            time = datetime.strptime(time_str, "%H%M%S").strftime("%H:%M:%S")

            # Escribir en el CSV
            writer.writerow([image_id, date, time])

    print(f"Datos de fecha y hora guardados en {ruta_csv}")


def download_sentinel(final_path, geometry):
    # Define date range
    start_date = '2024-07-01'
    end_date = '2025-12-31'

    # Create a filtered image collection
    sentinel_collection = ee.ImageCollection("COPERNICUS/S2_HARMONIZED") \
        .filterBounds(geometry) \
        .filterDate(start_date, end_date) \
        .filterMetadata('CLOUDY_PIXEL_PERCENTAGE', 'less_than', 5) \
        .filterMetadata('MEAN_SOLAR_ZENITH_ANGLE', 'less_than', 78)

    # Get the number of images in the collection
    image_count = sentinel_collection.size()
    print("Number of available images:", image_count.getInfo())

    # Get a list of image IDs
    image_list = sentinel_collection.aggregate_array('system:id').getInfo()

    # Create directories if they do not exist
    paths = {
        'rgb': os.path.join(final_path, 'rgb'),
        'nir': os.path.join(final_path, 'nir'),
        'ndwi': os.path.join(final_path, 'ndwi')
    }

    for path in paths.values():
        os.makedirs(path, exist_ok=True)

    # Iterate over the list of images
    for i, image_id in enumerate(image_list):
        try:
            # Load the image from the collection
            image = ee.Image(image_id).clip(geometry)

            # Select bands
            band3 = image.select('B3')
            band8 = image.select('B8')
            rgb = image.select('B4', 'B3', 'B2')
            nir = image.select('B8')

            # Calculate NDWI
            ndwi = band3.subtract(band8).divide(band3.add(band8)).rename('NDWI')

            # Extract date and time from the image ID string
            parts = image_id.split('/')[-1].split('T')
            date_str = parts[0]  # Date (YYYYMMDD)
            time_str = parts[1][:6] if len(parts) > 1 else "000000"  # Time (HHMMSS) or 000000 if missing
            date_time_str = f"{date_str}T{time_str}"
            date_time = datetime.strptime(date_time_str, "%Y%m%dT%H%M%S").strftime("%Y-%m-%d_%H-%M-%S")

            # Local paths in the corresponding folders
            rgb_path = os.path.join(paths['rgb'], f'RGB_{date_time}.tif')
            nir_path = os.path.join(paths['nir'], f'NIR_{date_time}.tif')
            ndwi_path = os.path.join(paths['ndwi'], f'NDWI_{date_time}.tif')

            # Export locally to the corresponding folders
            geemap.ee_export_image(image.select(['B4', 'B3', 'B2']).visualize(min=0, max=4000, gamma=1.4),
                                   filename=rgb_path, scale=10, crs='EPSG:4326')
            geemap.ee_export_image(image.select(['B8']).visualize(min=0, max=4000, gamma=1.4),
                                   filename=nir_path, scale=10, crs='EPSG:4326')
            geemap.ee_export_image(ndwi, filename=ndwi_path, scale=10, crs='EPSG:4326')

            print(f"Exported locally: RGB for {date_time}")
            print(f"Exported locally: NIR for {date_time}")
            print(f"Exported locally: NDWI for {date_time}")

        except Exception as e:
            print(f"Error processing image ID: {image_id}")
            print(e)
def descarga_sentinel_old(ruta_final, geometria):
    # Definir rango de fechas
    start_date = '2024-07-01'
    end_date = '2025-12-31'

    # Crear una colección de imágenes filtrada
    sentinel_collection = ee.ImageCollection("COPERNICUS/S2_HARMONIZED") \
        .filterBounds(geometria) \
        .filterDate(start_date, end_date) \
        .filterMetadata('CLOUDY_PIXEL_PERCENTAGE', 'less_than', 5) \
        .filterMetadata('MEAN_SOLAR_ZENITH_ANGLE', 'less_than', 78)

    # Obtener el número de imágenes en la colección
    image_count = sentinel_collection.size()
    print("Número de imágenes disponibles:", image_count.getInfo())

    # Obtener una lista de IDs de imágenes
    image_list = sentinel_collection.aggregate_array('system:id').getInfo()

    # Iterar sobre la lista de imágenes
    for i, image_id in enumerate(image_list):
        try:
            # Cargar la imagen desde la colección
            image = ee.Image(image_id).clip(geometria)

            # Seleccionar bandas
            band3 = image.select('B3')
            band8 = image.select('B8')
            rgb = image.select('B4', 'B3', 'B2')
            nir = image.select('B8')

            # Calcular NDWI
            ndwi = band3.subtract(band8).divide(band3.add(band8)).rename('NDWI')

            # Reproyectar todas las bandas a la misma proyección y escala
            image = ee.Image.cat([rgb, nir, ndwi]).reproject(crs='EPSG:4326', scale=10)

            # Extraer la fecha y hora de la cadena del ID de la imagen
            parts = image_id.split('/')[-1].split('T')
            date_str = parts[0]  # Fecha (YYYYMMDD)
            time_str = parts[1][:6] if len(parts) > 1 else "000000"  # Hora (HHMMSS) o 000000 si falta
            date_time_str = f"{date_str}T{time_str}"
            date_time = datetime.strptime(date_time_str, "%Y%m%dT%H%M%S").strftime("%Y-%m-%d_%H-%M-%S")

            # Rutas locales en las carpetas correspondientes
            ruta_rgb = os.path.join(ruta_final, 'rgb', f'RGB_{date_time}.tif')
            ruta_nir = os.path.join(ruta_final, 'nir', f'NIR_{date_time}.tif')
            ruta_ndwi = os.path.join(ruta_final, 'ndwi', f'NDWI_{date_time}.tif')

            # Exportar localmente en las carpetas correspondientes
            geemap.ee_export_image(image.select(['B4', 'B3', 'B2']).visualize(min=0, max=4000, gamma=1.4),
                                   filename=ruta_rgb, scale=10, crs='EPSG:4326')
            geemap.ee_export_image(image.select(['B8']).visualize(min=0, max=4000, gamma=1.4),
                                   filename=ruta_nir, scale=10, crs='EPSG:4326')
            geemap.ee_export_image(ndwi, filename=ruta_ndwi, scale=10, crs='EPSG:4326')

            print(f"Exportado localmente: RGB para {date_time}")
            print(f"Exportado localmente: NIR para {date_time}")
            print(f"Exportado localmente: NDWI para {date_time}")

        except Exception as e:
            print(f"Error procesando el ID de la imagen: {image_id}")
            print(e)
        

def mask_nir(path_image):
    nir_path = os.path.abspath(os.path.join(path_image, 'nir'))
    mask_path = os.path.abspath(os.path.join(path_image, 'mask'))
    os.makedirs(mask_path, exist_ok=True)
    
    files_in_directory = os.listdir(nir_path)
    tif_files = [file for file in files_in_directory if file.lower().endswith('.tif')]
    
    for file in tif_files:
        image_path = os.path.join(nir_path, file)
        mask_name = 'mask' + file
        
        with rasterio.open(image_path) as src:
            profile = src.profile
        
        img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
        zero_values_mask = (img == 0)
        
        _, binary_mask = cv2.threshold(img, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        binary_mask[zero_values_mask] = 255
        
        labeled_regions, num_labels = ndimage.measurements.label(binary_mask)
        label_sizes = [(labeled_regions == label).sum() for label in range(num_labels + 1)]
        
        for label, size in enumerate(label_sizes):
            if size < 25:
                binary_mask[labeled_regions == label] = 255 
        
        kernel_size = 3
        kernel = np.ones((kernel_size, kernel_size), np.uint8)
        
        # Invert the mask
        inverted_mask = cv2.bitwise_not(binary_mask)
        
        # Apply dilation to expand black regions
        dilated_black_areas = cv2.dilate(inverted_mask, kernel, iterations=1)
        
        # Invert the dilated mask back
        final_mask = cv2.bitwise_not(dilated_black_areas)
        
        output_path = os.path.join(mask_path, mask_name)
        print(output_path)
        
        with rasterio.open(output_path, 'w', **profile) as dst:
            dst.write(final_mask, 1)
from rasterio.mask import mask
from rasterio.features import shapes


from rasterio.mask import mask
from rasterio.warp import reproject, Resampling
def extract_ndwi2(row_path, water_bodie_path):
    ndwi_path = os.path.abspath(os.path.join(water_bodie_path, 'ndwi'))
    mask_path = os.path.abspath(os.path.join(water_bodie_path, 'mask', 'cut'))
    general_dir = water_bodie_path
    
    files_in_directory = os.listdir(mask_path)
    tif_files_mask = [file for file in files_in_directory if file.lower().endswith('.tif')]
    
    files_in_directory = os.listdir(ndwi_path)
    tif_files_ndwi = [file for file in files_in_directory if file.lower().endswith('.tif')]
    
    final_path = os.path.abspath(os.path.join(general_dir, 'ndwi_wetland'))
    os.makedirs(final_path, exist_ok=True)
    
    for i in range(len(tif_files_mask)):
        mask_image = os.path.join(mask_path, tif_files_mask[i])
        ndwi_image = os.path.join(ndwi_path, tif_files_ndwi[i])
        tif_name = tif_files_ndwi[i]
        
        with rasterio.open(mask_image) as src_1:
            # Read the mask
            raster_array_1 = src_1.read(1)
            profile = src_1.profile
            
            # Read NDWI and reproject it to match the mask
            with rasterio.open(ndwi_image) as src_ndwi:
                ndwi_array = src_ndwi.read(1)
                ndwi_reprojected = np.empty_like(raster_array_1, dtype=np.float32)

                reproject(
                    source=ndwi_array,
                    destination=ndwi_reprojected,
                    src_transform=src_ndwi.transform,
                    src_crs=src_ndwi.crs,
                    dst_transform=src_1.transform,
                    dst_crs=src_1.crs,
                    resampling=Resampling.nearest,
                )

            # Create a new array combining the mask and the reprojected NDWI
            modified_raster_array = np.where(raster_array_1 == 0, ndwi_reprojected, raster_array_1)
            modified_raster_array[modified_raster_array == 1] = 255
            modified_raster_array[modified_raster_array == 255] = np.nan
            
            # Save the new raster to the final folder
            profile.update({
                "dtype": rasterio.float32
            })
            final_name = f'humedal_{tif_name}'
            final_dir = os.path.join(final_path, final_name)
            with rasterio.open(final_dir, 'w', **profile) as dst:
                dst.write(modified_raster_array, 1)
        
        print(f"Processed and saved: {final_name}")
def mascara_nir_planet(ruta_imagenes,ruta_final):
    archivos_en_directorio = os.listdir(ruta_imagenes)
    archivos_tif = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    for archivo in archivos_tif:
        image = os.path.join(ruta_imagenes,archivo)
        name = 'mask' + archivo
        
# Leer la imagen NIR usando Rasterio
        with rasterio.open(image) as src:
            nir = src.read(1).astype(np.uint8)  # Asegurarse de que la imagen es de tipo uint8
            profile = src.profile
            original_zero_mask = (nir == 0)
# Aplicar umbral adaptativo
        ret, thresh_global_otsu = cv2.threshold(nir, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
# Invertir la imagen para que el agua sea 1 y la tierra sea 0
# Esto es necesario porque label() encuentra componentes conectados de píxeles no cero
        water = np.where(thresh_global_otsu == 0, 1, 0)

# Encuentra los componentes conectados
        labeled_array, num_features = label(water)

# Filtra por área
        min_area = 17 * 17  # Mínima área en píxeles
        area_pixel_count = np.bincount(labeled_array.ravel())[1:]  # Ignora el fondo (label 0)

# Máscara para mantener solo los componentes de agua de área suficientemente grande
        filtered = np.isin(labeled_array, np.where(area_pixel_count >= min_area)[0] + 1)
        thresh_filtered = np.where(filtered, 0, 150)
        kernel_size = 10  # Tamaño del kernel para una expansión de aproximadamente 30 metros
        kernel = np.ones((kernel_size, kernel_size), np.uint8)

# Invertir la imagen para la dilatación (dilatar áreas de agua)
# Identificar las áreas de agua (valor 0)
        water_areas = thresh_filtered == 0

# Aplicar la dilatación
        dilated_water_areas = cv2.dilate(water_areas.astype(np.uint8), kernel, iterations=1)

# Invertir de nuevo para obtener el resultado final
        expanded_water = np.where(dilated_water_areas == 1, 0, 150)
        expanded_water = expanded_water.astype(float)
        expanded_water[original_zero_mask] = np.nan
        output = os.path.join(ruta_final,name)
        with rasterio.open(output, 'w', **profile) as dst:
            dst.write(expanded_water, 1)
def cut_coast(raw_path, water_body_path, path_geometry_coast):
    
    # Path to the coastline geometry file (GeoJSON)
    shape_path = path_geometry_coast
    image_path = os.path.abspath(os.path.join(water_body_path, 'mask'))
    
    files_in_directory = os.listdir(image_path)
    tif_files = [file for file in files_in_directory if file.lower().endswith('.tif')]
    
    # Load the coastline geometry
    gdf = gpd.read_file(shape_path)
    
    output_path = os.path.join(image_path, 'cut')
    os.makedirs(output_path, exist_ok=True)
    
    for file in tif_files:
        image = os.path.join(image_path, file)
        
        with rasterio.open(image) as src:
            # Create a boolean mask representing the GeoJSON region
            mask = geometry_mask(gdf.geometry, out_shape=(src.height, src.width), transform=src.transform, invert=True)

            # Read the raster values as a NumPy array
            raster_array = src.read(1)

            # Change the values matching the GeoJSON region to 255
            raster_array[mask] = 255

            # Create an output file copy
            output_file = os.path.join(output_path, file)
            with rasterio.open(output_file, 'w', driver='GTiff', width=src.width, height=src.height, count=1, dtype=np.uint8, crs=src.crs, transform=src.transform) as dst:
                dst.write(raster_array, 1)
                
def seleccionar_humedal(ruta_actual, carpeta_satelital):
    
    # Ruta del shapefile
    dire = 'shapes/ligua_petorca_costera/limit_area_final_product_wetland.geojson'
    ruta_shape = os.path.abspath(os.path.join(ruta_actual, dire))
    
    # Ruta de las imágenes TIFF
    ruta_imagenes = os.path.abspath(os.path.join(ruta_actual, carpeta_satelital, 'clasificacion'))
    
    # Crear carpeta de salida 'cortado' si no existe
    ruta_salida = os.path.join(ruta_imagenes, 'cortado')
    os.makedirs(ruta_salida, exist_ok=True)  # Crear si no existe
    
    # Cargar el shapefile
    gdf = gpd.read_file(ruta_shape)
    
    # Listar archivos TIFF en el directorio
    archivos_en_directorio = os.listdir(ruta_imagenes)
    archivos_tif = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    
    for archivo in archivos_tif:
        image = os.path.join(ruta_imagenes, archivo)
        
        with rasterio.open(image) as src:
            # Recortar el TIFF usando la geometría del shapefile
            out_image, out_transform = mask(src, gdf.geometry, crop=True)
            
            # Copiar metadatos del archivo original
            out_meta = src.meta.copy()
            out_meta.update({
                "driver": "GTiff",
                "height": out_image.shape[1],
                "width": out_image.shape[2],
                "transform": out_transform
            })
            
            # Crear el archivo TIFF de salida en la carpeta 'cortado'
            output = os.path.join(ruta_salida, archivo)
            
            # Guardar el archivo TIFF recortado
            with rasterio.open(output, 'w', **out_meta) as dst:
                dst.write(out_image)
    
    print("Extracción completada. Archivos guardados en:", ruta_salida)
def quitar_costa_planet(ruta_imagenes,ruta_shape):
    
    archivos_en_directorio = os.listdir(ruta_imagenes)
    archivos_tif = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    gdf = gpd.read_file(ruta_shape)
    
    for archivo in archivos_tif:
        image = os.path.join(ruta_imagenes,archivo)
        with rasterio.open(image) as src:
    # Crear una máscara booleana que representa la región del GeoJSON
            mask = geometry_mask(gdf.geometry, out_shape=(src.height, src.width), transform=src.transform, invert=True)

    # Leer los valores del raster como un arreglo NumPy
            raster_array = src.read(1)

    # Cambiar los valores que coinciden con el GeoJSON a 255
            raster_array[mask] = 255

    # Crear una copia del archivo de salida
            output = os.path.join(ruta_imagenes,'cortado',archivo)
            with rasterio.open(output, 'w', driver='GTiff', width=src.width, height=src.height, count=1, dtype=np.uint8, crs=src.crs, transform=src.transform) as dst:
                dst.write(raster_array, 1)
                

#def extraer_ndwi(rutamascara,rutandwi,dir_general):
def extraer_ndwi(ruta_actual,carpeta_satelital):    
    rutandwi = os.path.abspath(os.path.join(ruta_actual, carpeta_satelital,'ndwi'))
    rutamascara = os.path.abspath(os.path.join(ruta_actual, carpeta_satelital,'Mascaras\cortado'))
    dir_general = os.path.abspath(os.path.join(ruta_actual, carpeta_satelital))
    archivos_en_directorio = os.listdir(rutamascara)
    archivos_tif_mascara = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    archivos_en_directorio = os.listdir(rutandwi)
    archivos_tif_ndwi = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    ruta_final = os.path.abspath(os.path.join(dir_general,'ndwi_humedal'))
    os.makedirs(ruta_final, exist_ok=True)
    for i in range(len(archivos_tif_mascara)):
        image_mascara = os.path.join(rutamascara,archivos_tif_mascara[i])
        image_ndwi = os.path.join(rutandwi,archivos_tif_ndwi[i])
        name_tif = archivos_tif_ndwi[i]
        with rasterio.open(image_mascara) as src_1:
    # Leer los valores del primer raster como un arreglo NumPy
            raster_array_1 = src_1.read(1)
    
# Abrir el segundo raster de NDWI
        with rasterio.open(image_ndwi) as src_ndwi:
    # Leer los valores del raster de NDWI como un arreglo NumPy
            ndwi_array = src_ndwi.read(1)
            profile = src_ndwi.profile
# Crear un nuevo arreglo que reemplace los valores de 0 en el primer raster con los valores de NDWI
        modified_raster_array = np.where(raster_array_1 == 0, ndwi_array, raster_array_1)
        modified_raster_array[modified_raster_array == 1] = 255
        modified_raster_array[modified_raster_array == 255] = np.nan
        final_name = 'humedal'+archivos_tif_ndwi[i]
        dir_final = os.path.join(ruta_final, final_name)
        with rasterio.open(dir_final, 'w', **profile) as dst:
            dst.write(modified_raster_array, 1)
def extraer_ndwi_planet(rutamascara,rutandwi,dir_general):
    archivos_en_directorio = os.listdir(rutamascara)
    archivos_tif_mascara = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    archivos_en_directorio = os.listdir(rutandwi)
    archivos_tif_ndwi = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    for i in range(len(archivos_tif_mascara)):
        image_mascara = os.path.join(rutamascara,archivos_tif_mascara[i])
        image_ndwi = os.path.join(rutandwi,archivos_tif_ndwi[i])
        name_tif = archivos_tif_ndwi[i]
        with rasterio.open(image_mascara) as src_1:
    # Leer los valores del primer raster como un arreglo NumPy
            raster_array_1 = src_1.read(1)
    
# Abrir el segundo raster de NDWI
        with rasterio.open(image_ndwi) as src_ndwi:
    # Leer los valores del raster de NDWI como un arreglo NumPy
            ndwi_array = src_ndwi.read(1)
            profile = src_ndwi.profile
# Crear un nuevo arreglo que reemplace los valores de 0 en el primer raster con los valores de NDWI
# en este caso 1 significa agua, depende como se define la mascara, es que valor usar 
        modified_raster_array = np.where(raster_array_1 == 1, ndwi_array, raster_array_1)
        modified_raster_array = modified_raster_array.astype(float)
        modified_raster_array[modified_raster_array == 0] = np.nan
        final_name = 'humedal'+archivos_tif_ndwi[i]
        dir_final = os.path.join(dir_general,'ndwi_humedal', final_name)
        with rasterio.open(dir_final, 'w', **profile) as dst:
            dst.write(modified_raster_array, 1)
#def LL_WL(raster)
#    filtered_array = np.where(modified_raster_array == 255, np.nan, modified_raster_array)

# Calcular el histograma excluyendo los valores de 255
#    hist, bin_edges = np.histogram(filtered_array[~np.isnan(filtered_array)], bins=100)
#    window_size = 5  # Puedes ajustar esto según tus necesidades

# Aplicar un filtro de media móvil para suavizar el histograma
 #   smoothed_hist = np.convolve(hist, np.ones(window_size) / window_size, mode='same')
 #   peaks, _ = find_peaks(smoothed_hist, height=0)  # Ajusta la altura según tus necesidades

# Encuentra los dos picos más altos
  #  sorted_peak_indices = np.argsort(smoothed_hist[peaks])[::-1]
 #   top_two_peaks = peaks[sorted_peak_indices[:2]]

# Obtén los valores de los dos picos más altos
 #   values_of_top_two_peaks = smoothed_hist[top_two_peaks]
  #  prominence_of_peaks = []
 #   hight_peaks = []
  #  for peak_index in top_two_peaks:
  #      left_index = 0
 #       right_index = len(smoothed_hist) - 1

    # Extiende hacia la izquierda desde el pico
  #      while left_index < peak_index and smoothed_hist[left_index + 1] >= smoothed_hist[left_index]:
  #          left_index += 1

  #  # Extiende hacia la derecha desde el pico
  #      while right_index > peak_index and smoothed_hist[right_index - 1] >= smoothed_hist[right_index]:
  #          right_index -= 1

    # Encuentra el mínimo en cada intervalo alrededor del pico
  #      left_min = np.min(smoothed_hist[left_index:peak_index + 1])
  #      right_min = np.min(smoothed_hist[peak_index:right_index + 1])

    # Determina el nivel de referencia
#        reference_level = max(left_min, right_min)

    # Calcula la prominencia del pico
    #    prominence = smoothed_hist[peak_index] - reference_level
    #    hight_peaks.append(smoothed_hist[peak_index])
    #    prominence_of_peaks.append(prominence)

def maskL457sr(image):
  # Bit 0 - Fill
  # Bit 1 - Dilated Cloud
  # Bit 2 - Unused
  # Bit 3 - Cloud
  # Bit 4 - Cloud Shadow
  qaMask = image.select('QA_PIXEL').bitwiseAnd(int('11111', 2)).eq(0)
  saturationMask = image.select('QA_RADSAT').eq(0)

  # Apply the scaling factors to the appropriate bands.
  opticalBands = image.select('SR_B.').multiply(0.0000275).add(-0.2)
  thermalBand = image.select('ST_B6').multiply(0.00341802).add(149.0);

  # Replace the original bands with the scaled ones and apply the masks.
  return image.addBands(opticalBands, None, True) \
      .addBands(thermalBand, None, True) \
      .updateMask(qaMask) \
      .updateMask(saturationMask)

def maskL8sr(image):
  # Bit 0 - Fill
  # Bit 1 - Dilated Cloud
  # Bit 2 - Unused
  # Bit 3 - Cloud
  # Bit 4 - Cloud Shadow
  qaMask = image.select('QA_PIXEL').bitwiseAnd(int('11111', 2)).eq(0)
  saturationMask = image.select('QA_RADSAT').eq(0)

  # Apply the scaling factors to the appropriate bands.
  opticalBands = image.select('SR_B.').multiply(0.0000275).add(-0.2)
  thermalBand = image.select('ST_B.*').multiply(0.00341802).add(149.0)

  # Replace the original bands with the scaled ones and apply the masks.
  return image.addBands(opticalBands, None, True) \
      .addBands(thermalBand, None, True) \
      .updateMask(qaMask) \
      .updateMask(saturationMask)
      
def correctStriping(image):
    # Lista de bandas a corregir
    bands = ['SR_B1', 'SR_B2', 'SR_B3', 'SR_B4', 'SR_B5', 'SR_B7']
    
    # Obtener la imagen original
    original = image.select(bands)
    
    # Calcular la mediana por píxel en cada banda
    median = original.reduce(ee.Reducer.median())
    
    # Calcular la diferencia absoluta entre cada banda y la mediana
    diff = original.subtract(median).abs()
    
    # Crear una máscara donde la diferencia sea mayor a un umbral específico
    threshold = 500
    mask = diff.gt(threshold)
    
    # Rellenar los valores en cada banda utilizando la mediana
    filled = original.unmask(median, True)
    
    # Reconstruir cada banda utilizando la máscara
    reconstructed = filled.where(mask, original)
    
    # Retornar la imagen original con las bandas corregidas de bandeo
    return image.addBands(reconstructed.rename(bands))
def apply_scale_factors(image):
  optical_bands = image.select('SR_B.').multiply(0.0000275).add(-0.2)
  thermal_bands = image.select('ST_B.*').multiply(0.00341802).add(149.0)
  return image.addBands(optical_bands, None, True).addBands(
      thermal_bands, None, True
  )

def descarga_landsat5(ruta_final, geometria):
    start_date = '1985-01-01'
    end_date = '2015-10-31'

    # Crear las carpetas necesarias si no existen
    for folder in ['rgb', 'nir', 'ndwi']:
        os.makedirs(os.path.join(ruta_final, 'Descarga', folder), exist_ok=True)

    # Cargar la colección de imágenes de Landsat 5 y aplicar filtros
    landsat_collection = ee.ImageCollection("LANDSAT/LT05/C02/T1_L2") \
        .filterBounds(geometria) \
        .filterDate(start_date, end_date) \
        .filterMetadata('CLOUD_COVER', 'less_than', 10) \
        .map(apply_scale_factors) 

    # Obtener el número de imágenes en la colección
    image_list = landsat_collection.aggregate_array('system:id').getInfo()
    num_images = len(image_list)
    print(f"Total de imágenes disponibles para descarga (ordenadas por fecha): {num_images}")

    for i in range(num_images):
        image = ee.Image(landsat_collection.toList(landsat_collection.size()).get(i)).clip(geometria)
        band_names = image.bandNames()
        
        # Comprobar si la imagen tiene bandas vacías
        if not band_names.getInfo():
            print(f'Banda vacía para la imagen {image_list[i]}')
            continue  # Saltar a la siguiente imagen si está vacía
        else:
            image_name = image_list[i]

            # Extraer la información de la imagen (ID, fecha y hora)
            id_image = image_name.split('/')[-1]
            time_start = image.get('system:time_start').getInfo()
            time_datetime = datetime.utcfromtimestamp(time_start / 1000)
            date = time_datetime.strftime('%Y%m%d')
            time_str = time_datetime.strftime('%H_%M_%S')

            print(f"Procesando imagen {i+1}: {id_image} tomada el {date} a las {time_str}")

            # Selección de bandas RGB
            rgb = image.select('SR_B3', 'SR_B2', 'SR_B1')
            rgb_composite = rgb.visualize(min=0, max=0.6, gamma=1.4)

            # Visualización interactiva
            rgb_img = geemap.ee_to_numpy(rgb_composite, region=geometria, scale=10)
            plt.imshow(rgb_img)
            plt.title(f'Imagen RGB {id_image}')
            plt.show()

            # Confirmación para descarga
            respuesta = input(f"¿Deseas descargar esta imagen {id_image}? (s/n): ")
            if respuesta.lower() == 's':
                # Definir nombres de archivos para guardar las imágenes
                nombre_rgb = f'RGB{id_image}_{time_str}.tif'
                nombre_nir = f'NIR{id_image}_{time_str}.tif'
                nombre_ndwi = f'NDWI{id_image}_{time_str}.tif'

                ruta_rgb = os.path.join(ruta_final, 'Descarga', 'rgb', nombre_rgb)
                ruta_nir = os.path.join(ruta_final, 'Descarga', 'nir', nombre_nir)
                ruta_ndwi = os.path.join(ruta_final, 'Descarga', 'ndwi', nombre_ndwi)

                # Exportar imágenes localmente
                nir = image.select('SR_B4')
                ndwi = image.normalizedDifference(['SR_B2', 'SR_B4'])
                nir_composite = nir.visualize(min=0, max=0.6, gamma=1.4)

                geemap.ee_export_image(rgb_composite, filename=ruta_rgb, crs='EPSG:4326')
                geemap.ee_export_image(nir_composite, filename=ruta_nir, crs='EPSG:4326')
                geemap.ee_export_image(ndwi, filename=ruta_ndwi, crs='EPSG:4326')

                print(f'Imágenes descargadas: {nombre_rgb}, {nombre_nir}, {nombre_ndwi}')



def descarga_landsat8(ruta_final, geometria):
    start_date = '2010-01-01'
    end_date = '2023-10-31'

    # Crear las carpetas necesarias si no existen
    for folder in ['rgb', 'nir', 'ndwi']:
        os.makedirs(os.path.join(ruta_final, 'Descarga', folder), exist_ok=True)

    # Cargar la colección de imágenes de Landsat 5 y aplicar filtros
    landsat_collection = ee.ImageCollection("LANDSAT/LC08/C02/T1_L2") \
        .filterBounds(geometria) \
        .filterDate(start_date, end_date) \
        .filterMetadata('CLOUD_COVER', 'less_than', 10) \
        .map(apply_scale_factors) 

    # Obtener el número de imágenes en la colección
    image_list = landsat_collection.aggregate_array('system:id').getInfo()
    num_images = len(image_list)
    print(f"Total de imágenes disponibles para descarga (ordenadas por fecha): {num_images}")

    for i in range(num_images):
        image = ee.Image(landsat_collection.toList(landsat_collection.size()).get(i)).clip(geometria)
        band_names = image.bandNames()
        
        # Comprobar si la imagen tiene bandas vacías
        if not band_names.getInfo():
            print(f'Banda vacía para la imagen {image_list[i]}')
            continue  # Saltar a la siguiente imagen si está vacía
        else:
            image_name = image_list[i]

            # Extraer la información de la imagen (ID, fecha y hora)
            id_image = image_name.split('/')[-1]
            time_start = image.get('system:time_start').getInfo()
            time_datetime = datetime.utcfromtimestamp(time_start / 1000)
            date = time_datetime.strftime('%Y%m%d')
            time_str = time_datetime.strftime('%H_%M_%S')

            print(f"Procesando imagen {i+1}: {id_image} tomada el {date} a las {time_str}")

            # Selección de bandas RGB
            rgb = image.select('SR_B4', 'SR_B3', 'SR_B2')
            rgb_composite = rgb.visualize(min=0, max=0.6, gamma=1.4)

            # Visualización interactiva
            rgb_img = geemap.ee_to_numpy(rgb_composite, region=geometria, scale=10)
            plt.imshow(rgb_img)
            plt.title(f'Imagen RGB {id_image}')
            plt.show()

            # Confirmación para descarga
            respuesta = input(f"¿Deseas descargar esta imagen {id_image}? (s/n): ")
            if respuesta.lower() == 's':
                # Definir nombres de archivos para guardar las imágenes
                nombre_rgb = f'RGB{id_image}_{time_str}.tif'
                nombre_nir = f'NIR{id_image}_{time_str}.tif'
                nombre_ndwi = f'NDWI{id_image}_{time_str}.tif'

                ruta_rgb = os.path.join(ruta_final, 'Descarga', 'rgb', nombre_rgb)
                ruta_nir = os.path.join(ruta_final, 'Descarga', 'nir', nombre_nir)
                ruta_ndwi = os.path.join(ruta_final, 'Descarga', 'ndwi', nombre_ndwi)

                # Exportar imágenes localmente
                nir = image.select('SR_B5')
                ndwi = image.normalizedDifference(['SR_B3', 'SR_B5'])
                nir_composite = nir.visualize(min=0, max=0.6, gamma=1.4)

                geemap.ee_export_image(rgb_composite, filename=ruta_rgb, crs='EPSG:4326')
                geemap.ee_export_image(nir_composite, filename=ruta_nir, crs='EPSG:4326')
                geemap.ee_export_image(ndwi, filename=ruta_ndwi, crs='EPSG:4326')

                print(f'Imágenes descargadas: {nombre_rgb}, {nombre_nir}, {nombre_ndwi}')
def descarga_landsat9(ruta_final, geometria):
    start_date = '2010-01-01'
    end_date = '2023-10-31'

    # Crear las carpetas necesarias si no existen
    for folder in ['rgb', 'nir', 'ndwi']:
        os.makedirs(os.path.join(ruta_final, 'Descarga', folder), exist_ok=True)

    # Cargar la colección de imágenes de Landsat 5 y aplicar filtros
    landsat_collection = ee.ImageCollection("LANDSAT/LC09/C02/T1_L2") \
        .filterBounds(geometria) \
        .filterDate(start_date, end_date) \
        .filterMetadata('CLOUD_COVER', 'less_than', 10) \
        .map(apply_scale_factors) 

    # Obtener el número de imágenes en la colección
    image_list = landsat_collection.aggregate_array('system:id').getInfo()
    num_images = len(image_list)
    print(f"Total de imágenes disponibles para descarga (ordenadas por fecha): {num_images}")

    for i in range(num_images):
        image = ee.Image(landsat_collection.toList(landsat_collection.size()).get(i)).clip(geometria)
        band_names = image.bandNames()
        
        # Comprobar si la imagen tiene bandas vacías
        if not band_names.getInfo():
            print(f'Banda vacía para la imagen {image_list[i]}')
            continue  # Saltar a la siguiente imagen si está vacía
        else:
            image_name = image_list[i]

            # Extraer la información de la imagen (ID, fecha y hora)
            id_image = image_name.split('/')[-1]
            time_start = image.get('system:time_start').getInfo()
            time_datetime = datetime.utcfromtimestamp(time_start / 1000)
            date = time_datetime.strftime('%Y%m%d')
            time_str = time_datetime.strftime('%H_%M_%S')

            print(f"Procesando imagen {i+1}: {id_image} tomada el {date} a las {time_str}")

            # Selección de bandas RGB
            rgb = image.select('SR_B4', 'SR_B3', 'SR_B2')
            rgb_composite = rgb.visualize(min=0, max=0.6, gamma=1.4)

            # Visualización interactiva
            rgb_img = geemap.ee_to_numpy(rgb_composite, region=geometria, scale=10)
            plt.imshow(rgb_img)
            plt.title(f'Imagen RGB {id_image}')
            plt.show()

            # Confirmación para descarga
            respuesta = input(f"¿Deseas descargar esta imagen {id_image}? (s/n): ")
            if respuesta.lower() == 's':
                # Definir nombres de archivos para guardar las imágenes
                nombre_rgb = f'RGB{id_image}_{time_str}.tif'
                nombre_nir = f'NIR{id_image}_{time_str}.tif'
                nombre_ndwi = f'NDWI{id_image}_{time_str}.tif'

                ruta_rgb = os.path.join(ruta_final, 'Descarga', 'rgb', nombre_rgb)
                ruta_nir = os.path.join(ruta_final, 'Descarga', 'nir', nombre_nir)
                ruta_ndwi = os.path.join(ruta_final, 'Descarga', 'ndwi', nombre_ndwi)

                # Exportar imágenes localmente
                nir = image.select('SR_B5')
                ndwi = image.normalizedDifference(['SR_B3', 'SR_B5'])
                nir_composite = nir.visualize(min=0, max=0.6, gamma=1.4)

                geemap.ee_export_image(rgb_composite, filename=ruta_rgb, crs='EPSG:4326')
                geemap.ee_export_image(nir_composite, filename=ruta_nir, crs='EPSG:4326')
                geemap.ee_export_image(ndwi, filename=ruta_ndwi, crs='EPSG:4326')

                print(f'Imágenes descargadas: {nombre_rgb}, {nombre_nir}, {nombre_ndwi}')


def otsu(histogram):
    counts = ee.Array(ee.Dictionary(histogram).get('histogram'))
    means = ee.Array(ee.Dictionary(histogram).get('bucketMeans'))
    size = means.length().get([0])
    total = counts.reduce(ee.Reducer.sum(), [0]).get([0])
    sum = means.multiply(counts).reduce(ee.Reducer.sum(), [0]).get([0])
    mean = sum.divide(total)

    indices = ee.List.sequence(1, size)

    # Compute between sum of squares, where each mean partitions the data.

    def func_xxx(i):
        aCounts = counts.slice(0, 0, i)
        aCount = aCounts.reduce(ee.Reducer.sum(), [0]).get([0])
        aMeans = means.slice(0, 0, i)
        aMean = (
            aMeans.multiply(aCounts)
            .reduce(ee.Reducer.sum(), [0])
            .get([0])
            .divide(aCount)
        )
        bCount = total.subtract(aCount)
        bMean = sum.subtract(aCount.multiply(aMean)).divide(bCount)
        return aCount.multiply(aMean.subtract(mean).pow(2)).add(
            bCount.multiply(bMean.subtract(mean).pow(2))
        )

    bss = indices.map(func_xxx)

    # Return the mean value corresponding to the maximum BSS.
    return means.sort(bss).get([-1])



def extract_water(image,polygon):
    histogram = image.select('B8').reduceRegion(
        **{
            'reducer': ee.Reducer.histogram(255, 2),
            'geometry': polygon,
            'scale': 10,
            'bestEffort': True,
        }
    )
    threshold = otsu(histogram.get('B8'))
    water = image.select('B8').lt(threshold).selfMask()
    return water.set({"threshold": threshold})

def sturges(data):
    non_nan_data = data[~np.isnan(data)]
    num_data = len(non_nan_data)
    num_bins = int(np.log2(num_data)) + 1
    return num_bins
def freedman_diaconis(data):
    non_nan_data = data[~np.isnan(data)]
    num_data = len(non_nan_data)
    irq = np.percentile(non_nan_data, 75) - np.percentile(non_nan_data, 25)
    bin_width = 2 * irq / np.power(num_data, 1/3)
    num_bins = int((np.max(non_nan_data) - np.min(non_nan_data)) / bin_width) + 1
    return num_bins

def land_water_level(image_path, tif_files):
    LL_values_list = []
    WL_values_list = []
    valid_names = [] 
    
    for i in range(len(tif_files)):
        image = os.path.join(image_path, tif_files[i])
        print(i)
        
        with rasterio.open(image) as src:
            modified_raster_array = src.read(1)
        
        filtered_array = modified_raster_array
        numberbin = freedman_diaconis(modified_raster_array)
        
        # Calculate the histogram excluding values of 255
        hist, bin_edges = np.histogram(modified_raster_array, bins=numberbin, range=[-0.9, 0.9])
        window_size = 2  # You can adjust this based on your needs

        # Apply a moving average filter to smooth the histogram
        smoothed_hist = np.convolve(hist, np.ones(window_size) / window_size, mode='same')
        interpolation = interp1d(bin_edges[:-1], smoothed_hist, kind='linear')

        # Create an X set for interpolation
        x_interpolation = np.linspace(min(bin_edges[:-1]), max(bin_edges[:-1]), num=1000)

        # Calculate the interpolated Y values
        y_interpolation = interpolation(x_interpolation)
        
        # Find all the peaks in the smoothed histogram
        peaks, _ = find_peaks(y_interpolation, height=0)  # Adjust parameters as needed
        
        # If there are more than one peak, proceed
        if len(peaks) > 1:
            valid_names.append(tif_files[i])
            prominences = peak_prominences(y_interpolation, peaks)[0]
            peak_heights = y_interpolation[peaks]

            # Find the indices of the two largest peaks
            top_two_peak_indices = np.sort(peaks[np.argpartition(peak_heights, -2)[-2:]])

            # Take the prominences of the two largest peaks
            top_two_prominences = prominences[np.isin(peaks, top_two_peak_indices)]
            peak_heights = peak_heights[np.isin(peaks, top_two_peak_indices)]
            height_lp = peak_heights[0]  # Replace "height_value" with the correct value
            height_wp = peak_heights[1]
            prom_lp = top_two_prominences[0]
            prom_wp = top_two_prominences[0]

            # Calculate LL (Land Level) using the formula
            LL = height_lp - 0.9 * prom_lp
            WL = height_wp - 0.9 * prom_wp

            y_interpolation_MID = y_interpolation[top_two_peak_indices[0]:top_two_peak_indices[1]]
            x_interpolation_MID = x_interpolation[top_two_peak_indices[0]:top_two_peak_indices[1]]
            
            # Find the minimum value in this subset
            min_y_value = min(y_interpolation_MID)
            
            # Find the index of the minimum value within the subset
            min_y_ll = np.argmin(y_interpolation_MID)

            y_interpolation_LL = y_interpolation_MID[0:min_y_ll]
            x_interpolation_LL = x_interpolation_MID[0:min_y_ll]
            
            differences_LL = np.abs(y_interpolation_LL - LL)
            closest_index_LL = np.argmin(differences_LL)
            
            y_interpolation_WL = y_interpolation_MID[min_y_ll+1:len(y_interpolation_MID)-1]
            x_interpolation_WL = x_interpolation_MID[min_y_ll+1:len(y_interpolation_MID)-1]
            
            differences_WL = np.abs(y_interpolation_WL - WL)
            closest_index_WL = np.argmin(differences_WL)
            
            LL_value = x_interpolation_LL[closest_index_LL]
            WL_value = x_interpolation_WL[closest_index_WL]
            
            LL_values_list.append(LL_value)
            WL_values_list.append(WL_value)
        else:
            pass
    
    LL_values = np.array(LL_values_list)
    WL_values = np.array(WL_values_list)
    concatenated_vector = np.column_stack((LL_values, WL_values))
    
    return concatenated_vector, valid_names
            
#def sep_band_planet(ruta_imagenes_planet_raw):
    # Lista para almacenar los nombres de los archivos .tif
    # Lista de archivos .tif en el directorio especificado
    #archivos_tif = [archivo for archivo in os.listdir(ruta_imagenes_planet_raw) if archivo.endswith('.tif')]

# Filtrar la lista para incluir solo los archivos que contienen "AnalyticMS_SR_clip" en su nombre
    #archivos_filtrados = [archivo for archivo in archivos_tif if "AnalyticMS_SR_clip" in archivo]

# Procesar cada archivo filtrado
    #for name_tif in archivos_filtrados:
     #   image_path = os.path.join(ruta_imagenes_planet_raw, name_tif)

        #with rasterio.open(image_path) as src:
        # Leer las bandas NIR y G
           # nir = src.read(4).astype(float)
           # g = src.read(2).astype(float)

        # Calcular NDWI
           # suma_bandas = g + nir
           # suma_bandas[suma_bandas == 0] = np.nan
           # ndwi = (g - nir) / suma_bandas

        # Actualizar el perfil para la nueva imagen
           # profile = src.profile
           # profile.update(dtype=rasterio.float32, count=1)


    # Guardar la imagen NDWI
       # final_name_ndwi = 'ndwi_' + name_tif
       # dir_final_ndwi = os.path.join(ruta_imagenes_planet_raw, 'ndwi', final_name_ndwi)
       # with rasterio.open(dir_final_ndwi, 'w', **profile) as dst:
       #     dst.write(ndwi.astype(rasterio.float32), 1)

    # Guardar la imagen NIR
       # final_name_nir = 'nir_' + name_tif
       # dir_final_nir = os.path.join(ruta_imagenes_planet_raw, 'nir', final_name_nir)
       # with rasterio.open(dir_final_nir, 'w', **profile) as dst:
       #     dst.write(nir.astype(rasterio.float32), 1)


            
# Función para ajustar gamma
def adjust_gamma(image, gamma=1.0):
    invGamma = 1.0 / gamma
    table = np.array([((i / 255.0) ** invGamma) * 255 for i in np.arange(0, 256)]).astype("uint8")
    return cv2.LUT(image, table)

            
def sep_band_planet_nir_corrected(ruta_imagenes_planet_raw):
    ruta_nir = os.path.join(ruta_imagenes_planet_raw,'nir')
    archivos_tif = [archivo for archivo in os.listdir(ruta_nir) if archivo.endswith('.tif')]
    for name_tif in archivos_tif:
        image_path = os.path.join(ruta_imagenes_planet_raw,'nir', name_tif)

        with rasterio.open(image_path) as src:
        # Leer la banda NIR
            nir = src.read(1).astype(float)

        # Reescalar los valores de píxeles entre 0 y 1, y luego a 0-255
            nir_scaled = np.clip(nir, 0, 4500) / 4500  # Reescalar entre 0 y 1
            nir_scaled *= 255  # Reescalar entre 0 y 255 para representación de 8 bits
            #nir_scaled_squeezed = np.squeeze(nir_scaled)
        # Actualizar perfil para la imagen ajustada
            profile = src.profile
            profile.update(dtype=rasterio.uint8, count=1)

        # Guardar la imagen NIR ajustada
            final_name_nir = 'nir_gamma_' + name_tif
            dir_final_nir = os.path.join(ruta_imagenes_planet_raw, 'nir_corrected', final_name_nir)
            with rasterio.open(dir_final_nir, 'w', **profile) as dst:
                dst.write(nir_scaled, 1)
import rasterio
from rasterio.warp import calculate_default_transform, reproject, Resampling


# Tu función modificada
def sep_band_planet(ruta_imagenes_planet_raw,ruta_principal):
    archivos_tif = [archivo for archivo in os.listdir(ruta_imagenes_planet_raw) if archivo.endswith('.tif')]
    #archivos_filtrados = [archivo for archivo in archivos_tif if "AnalyticMS_SR_clip" in archivo]

    for name_tif in archivos_tif:
        image_path = os.path.join(ruta_imagenes_planet_raw, name_tif)

        with rasterio.open(image_path) as src:
    # Leer las bandas individuales
            #blue = src.read(1).astype(float)
            #green = src.read(2).astype(float)
            #red = src.read(3).astype(float)
            #nir = src.read(4).astype(float)

            blue = src.read(1).astype(rasterio.uint16)
            green = src.read(2).astype(rasterio.uint16)
            red = src.read(3).astype(rasterio.uint16)
            nir = src.read(4).astype(rasterio.uint16)

            blue = np.where(blue == 0, np.nan, blue)
            green = np.where(green == 0, np.nan, green)
            red = np.where(red == 0, np.nan, red)
            nir = np.where(nir == 0, np.nan, nir)
    # Calcular el NDWI
            
            #ndwi = np.nan_to_num(ndwi, nan=0.0)
    # Guardar los metadatos del raster original para usarlos en los nuevos rasters
            meta = src.meta.copy()
        # Actualizar el perfil para la nueva imagen
        ndwi = (green.astype(float) - nir) / (green + nir)
        # Guardar la imagen NDWI reproyectada
        final_name_ndwi = 'ndwi_' + name_tif
        dir_final_ndwi = os.path.join(ruta_principal, 'ndwi', final_name_ndwi)
        meta.update(count=1, dtype=rasterio.float32)
        with rasterio.open(dir_final_ndwi, 'w', **meta) as dst:
            dst.write(ndwi.astype(rasterio.float32), 1)
        # Guardar la imagen NIR reproyectada
        final_name_nir = 'nir_' + name_tif
        dir_final_nir = os.path.join(ruta_principal, 'nir', final_name_nir)
        with rasterio.open(dir_final_nir, 'w', **meta) as dst:
            dst.write(nir.astype(rasterio.float32), 1)
    
def reproject_planet(ruta_imagenes_planet_raw,output):
    archivos_tif = [archivo for archivo in os.listdir(ruta_imagenes_planet_raw) if archivo.endswith('.tif')]
    archivos_filtrados = [archivo for archivo in archivos_tif if 'AnalyticMS_SR_harmonized_clip' in archivo or 'AnalyticMS_SR_clip' in archivo]
    src_crs = 'EPSG:32719'  # Proyección original
    dst_crs = 'EPSG:4326'   # Proyección destino (WGS84)
    
    for name_tif in archivos_filtrados:
        image_path = os.path.join(ruta_imagenes_planet_raw, name_tif)
        with rasterio.open(image_path) as src:
            # Calcula la transformación y las dimensiones del nuevo raster
            transform, width, height = calculate_default_transform(
                src.crs, dst_crs, src.width, src.height, *src.bounds)

            # Define los metadatos para el nuevo raster
            kwargs = src.meta.copy()
            kwargs.update({
                'crs': dst_crs,
                'transform': transform,
                'width': width,
                'height': height
            })

            dir_final_nir = os.path.join(output, name_tif)

            # Crea el nuevo archivo raster reproyectado
            with rasterio.open(dir_final_nir, 'w', **kwargs) as dst:
                for i in range(1, src.count + 1):
                    # Reproyecta cada banda del raster
                    reproject(
                        source=rasterio.band(src, i),
                        destination=rasterio.band(dst, i),
                        src_transform=src.transform,
                        src_crs=src.crs,
                        dst_transform=transform,
                        dst_crs=dst_crs,
                        resampling=Resampling.nearest)
                    
                    # Cambiar los valores de 0 a NaN en la banda reproyecta
from rasterio.mask import mask
import tempfile  # Importar tempfile aquí

def reproject_and_clip_planet(ruta_imagenes_planet_raw, shapefile_path):
    archivos_tif = [archivo for archivo in os.listdir(ruta_imagenes_planet_raw) if archivo.endswith('.tif')]
    archivos_filtrados = [archivo for archivo in archivos_tif if "AnalyticMS_SR_clip" in archivo]
    src_crs = 'EPSG:32719'  # Proyección original
    dst_crs = 'EPSG:4326'   # Proyección destino (WGS84)

    geoms = gpd.read_file(shapefile_path)
    geoms = geoms.to_crs(dst_crs)

    for name_tif in archivos_filtrados:
        image_path = os.path.join(ruta_imagenes_planet_raw, name_tif)
        dir_final_nir = os.path.join(ruta_imagenes_planet_raw, 'planet_reproyectado', name_tif)

        with rasterio.open(image_path) as src:
            transform, width, height = calculate_default_transform(
                src.crs, dst_crs, src.width, src.height, *src.bounds)

            kwargs = src.meta.copy()
            kwargs.update({
                'crs': dst_crs,
                'transform': transform,
                'width': width,
                'height': height
            })

            # Crear un archivo temporal
            temp_file_path = tempfile.mktemp(suffix='.tif')
            with rasterio.open(temp_file_path, 'w', **kwargs) as dst:
                for i in range(1, src.count + 1):
                    reproject(
                        source=rasterio.band(src, i),
                        destination=rasterio.band(dst, i),
                        src_transform=src.transform,
                        src_crs=src.crs,
                        dst_transform=transform,
                        dst_crs=dst_crs,
                        resampling=Resampling.nearest)

            # Recortar el raster reproyectado con el shapefile
            with rasterio.open(temp_file_path) as src:
                out_image, out_transform = mask(src, geoms.geometry, crop=True)
                out_meta = src.meta
                out_meta.update({"driver": "GTiff",
                                 "height": out_image.shape[1],
                                 "width": out_image.shape[2],
                                 "transform": out_transform})

                with rasterio.open(dir_final_nir, "w", **out_meta) as dest:
                    dest.write(out_image)

            # Eliminar el archivo temporal
            os.remove(temp_file_path)
import shutil
def quitar_zonast(ruta_imagenes, ruta_shape):
    archivos_en_directorio = os.listdir(ruta_imagenes)
    archivos_tif = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    gdf = gpd.read_file(ruta_shape)
    
    for archivo in archivos_tif:
        image = os.path.join(ruta_imagenes, archivo)
        try:
            with rasterio.open(image) as src:
                mask = geometry_mask(gdf.geometry, out_shape=(src.height, src.width), transform=src.transform, invert=True)
                raster_array = src.read(1)
                raster_array[mask] = np.nan

            # Escribir en un archivo temporal
            temp_output = os.path.join(ruta_imagenes, 'temp_' + archivo)
            with rasterio.open(temp_output, 'w', driver=src.driver, width=src.width, height=src.height, count=1, dtype=raster_array.dtype, crs=src.crs, transform=src.transform) as dst:
                dst.write(raster_array, 1)
            
            # Reemplazar el archivo original con el temporal
            shutil.move(temp_output, image)

        except Exception as e:
            print(f"Error procesando el archivo {archivo}: {e}")
            
def recortar_raster_con_shape(ruta_imagenes, ruta_shape):
    archivos_en_directorio = os.listdir(ruta_imagenes)
    archivos_tif = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
    gdf = gpd.read_file(ruta_shape)

    for archivo in archivos_tif:
        image = os.path.join(ruta_imagenes, archivo)
        try:
            with rasterio.open(image) as src:
                # Recortar el raster usando el shapefile
                out_image, out_transform = mask(src, gdf.geometry, crop=False)
                out_meta = src.meta.copy()

            out_meta.update({"driver": "GTiff",
                             "height": out_image.shape[1],
                             "width": out_image.shape[2],
                             "transform": out_transform})

            # Escribir en un archivo temporal
            temp_output = os.path.join(ruta_imagenes, 'temp_' + archivo)
            with rasterio.open(temp_output, 'w', **out_meta) as dest:
                dest.write(out_image)

            # Reemplazar el archivo original con el temporal
            shutil.move(temp_output, image)

        except Exception as e:
            print(f"Error procesando el archivo {archivo}: {e}")