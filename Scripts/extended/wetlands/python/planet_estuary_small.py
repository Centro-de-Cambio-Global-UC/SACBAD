import os
import geopandas as gpd
import rasterio
import numpy as np
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
import cv2
from rasterio.mask import mask

def sep_band_planet(ruta_imagenes_planet_raw,ruta_principal,ruta_shape):
    archivos_tif = [archivo for archivo in os.listdir(ruta_imagenes_planet_raw) if archivo.endswith('.tif')]
    #archivos_filtrados = [archivo for archivo in archivos_tif if "AnalyticMS_SR_clip" in archivo]
    gdf = gpd.read_file(ruta_shape)
    for name_tif in archivos_tif:
        image_path = os.path.join(ruta_imagenes_planet_raw, name_tif)

        with rasterio.open(image_path) as src:
    # Leer las bandas individuales
            #blue = src.read(1).astype(float)
            #green = src.read(2).astype(float)
            #red = src.read(3).astype(float)
            #nir = src.read(4).astype(float)
            mask = geometry_mask(gdf.geometry, out_shape=(src.height, src.width), transform=src.transform, invert=True)
            blue = src.read(1).astype(rasterio.uint16)
            green = src.read(2).astype(rasterio.uint16)
            red = src.read(3).astype(rasterio.uint16)
            nir = src.read(4).astype(rasterio.uint16)

            blue = np.where(blue == 0, np.nan, blue)
            green = np.where(green == 0, np.nan, green)
            red = np.where(red == 0, np.nan, red)
            nir = np.where(nir == 0, np.nan, nir)
            
            blue[mask] = np.nan
            green[mask] = np.nan
            red[mask] = np.nan
            nir[mask] = np.nan
    # Calcular el NDWI
            
            #ndwi = np.nan_to_num(ndwi, nan=0.0)
    # Guardar los metadatos del raster original para usarlos en los nuevos rasters
            meta = src.meta.copy()
        # Actualizar el perfil para la nueva imagen
        ndwi = (green.astype(float) - nir) / (green + nir)
        SR1 = nir/green
        SR2 = nir/red
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
        # Guardar la imagen SR1 reproyectada
        final_name_SR1 = 'SR1_' + name_tif
        dir_final_SR1 = os.path.join(ruta_principal, 'SR1', final_name_SR1)
        with rasterio.open(dir_final_SR1, 'w', **meta) as dst:
            dst.write(SR1.astype(rasterio.float32), 1)
        # Guardar la imagen SR2 reproyectada
        final_name_SR2 = 'SR2_' + name_tif
        dir_final_SR2 = os.path.join(ruta_principal, 'SR2', final_name_SR2)
        with rasterio.open(dir_final_SR2, 'w', **meta) as dst:
            dst.write(SR2.astype(rasterio.float32), 1)
# def mascara_nir_planet(ruta_imagenes,ruta_final):
#     archivos_en_directorio = os.listdir(ruta_imagenes)
#     archivos_tif = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
#     for archivo in archivos_tif:
#         image = os.path.join(ruta_imagenes,archivo)
#         name = 'mask' + archivo
        
# # Leer la imagen NIR usando Rasterio
#         with rasterio.open(image) as src:
#             nir = src.read(1)  # Asegurarse de que la imagen es de tipo uint8
#             profile = src.profile
#             original_zero_mask = (nir == 0)
# # Aplicar umbral adaptativo
#         nir = nir.astype('uint16')# imagenes satelitales planet son de 16 bits, no forzar a 8 bits, otsu en esta escala no funciona
#         original_zero_mask = (nir == 0)
#         minimus = np.nanmin(nir)
#         maximus = np.nanmax(nir) #
#         ret, thresh_global_otsu = cv2.threshold(nir, minimus, maximus, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
# # Invertir la imagen para que el agua sea 1 y la tierra sea 0
# # Esto es necesario porque label() encuentra componentes conectados de píxeles no cero
#         water = np.where(thresh_global_otsu == 0, 1, 0)

# # Encuentra los componentes conectados
#         labeled_array, num_features = label(water)

# # Filtra por área
#         min_area = 1 * 1  # Mínima área en píxeles
#         area_pixel_count = np.bincount(labeled_array.ravel())[1:]  # Ignora el fondo (label 0)

# # Máscara para mantener solo los componentes de agua de área suficientemente grande
#         filtered = np.isin(labeled_array, np.where(area_pixel_count >= min_area)[0] + 1)
#         thresh_filtered = np.where(filtered, 0, maximus/2)
#         kernel_size = 3  # expansion de las mascaras
#         kernel = np.ones((kernel_size, kernel_size), np.uint16)

# # Invertir la imagen para la dilatación (dilatar áreas de agua)
# # Identificar las áreas de agua (valor 0)
#         water_areas = thresh_filtered == 0

# # Aplicar la dilatación
#         dilated_water_areas = cv2.dilate(water.astype(np.uint8), kernel, iterations=1)

# # Invertir de nuevo para obtener el resultado final
#         expanded_water = np.where(dilated_water_areas == 1, 0, 0)
#         expanded_water = expanded_water.astype(float)
#         expanded_water[original_zero_mask] = np.nan
#         output = os.path.join(ruta_final,name)
#         with rasterio.open(output, 'w', **profile) as dst:
#             dst.write(dilated_water_areas, 1)
def mascara_nir_planet(ruta_imagenes,ruta_final,ruta_shape):
        from rasterio.mask import mask
        archivos_en_directorio = os.listdir(ruta_imagenes)
        archivos_tif = [archivo for archivo in archivos_en_directorio if archivo.lower().endswith('.tif')]
        gdf = gpd.read_file(ruta_shape)
        for archivo in archivos_tif:
                image = os.path.join(ruta_imagenes,archivo)
                name = 'mask' + archivo        
                with rasterio.open(image) as src:
                        nir = src.read(1)  # Asegurarse de que la imagen es de tipo uint8
    #profile = src.profile
    #original_zero_mask = (nir == 0,True, False)
                        nir, transform = mask(src, gdf.geometry, crop=True)
                        nir[nir == 0] = np.nan
                        nir = np.squeeze(nir)
    # Obtener el perfil de la imagen cortada
                        profile = src.profile
                masked = nir
                masked = np.where(~np.isnan(nir), 0, nir)
                nir = nir.astype('uint16') # las imagenes de planet, son de 16 bits en resolucion radiometrica
                normalized_img = cv2.normalize(nir, None, 0, 255, cv2.NORM_MINMAX, dtype=cv2.CV_8U)
                normalized_img = normalized_img+masked
                threshold = (normalized_img  <= 90)
                mask_water = threshold.astype(np.uint8)
                kernel = np.ones((7, 7), np.uint8)

# Aplicar la dilatación 22 metros 
                expanded_mask = cv2.dilate(mask_water, kernel, iterations=3)    
                output = os.path.join(ruta_final,name)
                with rasterio.open(output, 'w', **profile) as dst:
                        dst.write(expanded_mask, 1)
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
            raster_array[mask] = np.nan

    # Crear una copia del archivo de salida
            output = os.path.join(ruta_imagenes,'cortado',archivo)
            with rasterio.open(output, 'w', driver='GTiff', width=src.width, height=src.height, count=1, dtype=np.float32, crs=src.crs, transform=src.transform) as dst:
                dst.write(raster_array, 1)