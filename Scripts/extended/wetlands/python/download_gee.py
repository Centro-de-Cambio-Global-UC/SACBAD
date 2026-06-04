import ee
import geemap
import os
import geopandas as gpd
import rasterio
import numpy as np
from rasterio import features
from rasterio.features import geometry_mask
import numpy as np
import matplotlib.pyplot as plt
from rasterio.warp import calculate_default_transform, reproject, Resampling
from datetime import datetime 
import csv


def descarga_landsat8(roi,año_inicio,año_final,coleccion_landsat,ruta_actual):
    # input: -roi: geometria la zona a descargarm formato json 
    #        -año_inicio: indicar numericamente el año de inicio
    #        -año_final: seleccionar donde guardar 
    #        -ruta_actual: direccion de la ruta del codigo main 
    
    landsat_collection = ee.ImageCollection([])
    for year in range(año_inicio, año_final):
        start_date = str(year) + '-01-01'
        end_date = str(year) + '-12-31'
        print(year)
       # Filtra la colección por el año y la región de interés
        landsat_collection = ee.ImageCollection(coleccion_landsat) \
           .filterBounds(roi) \
           .filterDate(start_date, end_date) \
           .filterMetadata('CLOUD_COVER', 'less_than', 10) \
           .map(maskL8sr)
       # Aplica el mosaico y calcula el NDVI
        mosaic_year = landsat_collection.median()
        mos = ee.ImageCollection([mosaic_year])
        ndvi =ee.ImageCollection([mosaic_year.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI')])
        dbsi =ee.ImageCollection([calculateDBSI2(mosaic_year).rename('DBSI')])
        bu = ee.ImageCollection([calculateBU2(mosaic_year).rename('BU')])
        ndvi_collection_LT8 = ndvi_collection_LT8.merge(ndvi)
        dbsi_collection_LT8 = dbsi_collection_LT8.merge(dbsi)
        bu_collection_LT8 = bu_collection_LT8.merge(bu)
        mosaic_collection = mosaic_collection.merge(mos)
    return (ndvi_collection_LT8,bu_collection_LT8,mosaic_collection)