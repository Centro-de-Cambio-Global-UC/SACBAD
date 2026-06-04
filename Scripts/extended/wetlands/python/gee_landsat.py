# -*- coding: utf-8 -*-
"""
Created on Wed Jul 12 14:16:47 2023

@author: SACBAD supplementary repo
"""

import ee
import geemap

ee.Initialize(opt_url='https://earthengine-highvolume.googleapis.com')

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

def calculateDBSI(image):
    # Obtener las bandas necesarias

    # Calcular el índice DBSI
    DBSI = image.normalizedDifference(['SR_B5', 'SR_B2']).subtract(image.normalizedDifference(['SR_B4', 'SR_B3']))
    
    return DBSI.rename('DBSI')
def calculateDBSI2(image):
    # Obtener las bandas necesarias

    # Calcular el índice DBSI
    DBSI = image.normalizedDifference(['SR_B6', 'SR_B3']).subtract(image.normalizedDifference(['SR_B5', 'SR_B4']))
    
    return DBSI.rename('DBSI')
def calculateBU(image):
    # Obtener las bandas necesarias

    # Calcular el índice DBSI
    BU = image.normalizedDifference(['SR_B5', 'SR_B4']).subtract(image.normalizedDifference(['SR_B4', 'SR_B3']))
    
    return BU.rename('BU')
def calculateBU2(image):
    # Obtener las bandas necesarias

    # Calcular el índice DBSI
    BU = image.normalizedDifference(['SR_B6', 'SR_B5']).subtract(image.normalizedDifference(['SR_B5', 'SR_B4']))
    
    return BU.rename('BU')
def index_landsat5(roi):
    ndvi_collection_LT5 = ee.ImageCollection([])
    dbsi_collection_LT5 = ee.ImageCollection([])
    bu_collection_LT5 = ee.ImageCollection([])
    mosaic_collection = ee.ImageCollection([])
    for year in range(1992, 2008):
        start_date = str(year) + '-01-01'
        end_date = str(year) + '-12-31'
        print(year)
        # Filtra la colección por el año y la región de interés
        landsat_collection = ee.ImageCollection('LANDSAT/LT05/C02/T1_L2') \
            .filterBounds(roi) \
            .filterDate(start_date, end_date) \
            .filterMetadata('CLOUD_COVER', 'less_than', 10) \
            .map(maskL457sr)
        # Aplica el mosaico y calcula el NDVI
        mosaic_year = landsat_collection.median()
        ndvi =ee.ImageCollection([mosaic_year.normalizedDifference(['SR_B4', 'SR_B3']).rename('NDVI')])
        dbsi =ee.ImageCollection([calculateDBSI(mosaic_year).rename('DBSI')])
        bu = ee.ImageCollection([calculateBU(mosaic_year).rename('BU')])
        mos = ee.ImageCollection([mosaic_year])
        ndvi_collection_LT5 = ndvi_collection_LT5.merge(ndvi)
        dbsi_collection_LT5 = dbsi_collection_LT5.merge(dbsi)
        bu_collection_LT5 = bu_collection_LT5.merge(bu)
        mosaic_collection = mosaic_collection.merge(mos)
    return (ndvi_collection_LT5,bu_collection_LT5,mosaic_collection)

def index_landsat7(roi):
    ndvi_collection_LT7 = ee.ImageCollection([])
    dbsi_collection_LT7 = ee.ImageCollection([])
    bu_collection_LT7 = ee.ImageCollection([])
    mosaic_collection = ee.ImageCollection([])   
    for year in range(2011, 2014):
        start_date = str(year) + '-01-01'
        end_date = str(year) + '-12-31'
        print(year)
        # Filtra la colección por el año y la región de interés
        landsat_collection = ee.ImageCollection('LANDSAT/LE07/C02/T1_L2') \
            .filterBounds(roi) \
            .filterDate(start_date, end_date) \
            .filterMetadata('CLOUD_COVER', 'less_than', 30) \
            .map(correctStriping)\
            .map(maskL457sr)
        # Aplica el mosaico y calcula el NDVI
        mosaic_year = landsat_collection.median()
        mos = ee.ImageCollection([mosaic_year])
        ndvi =ee.ImageCollection([mosaic_year.normalizedDifference(['SR_B4', 'SR_B3']).rename('NDVI')])
        dbsi =ee.ImageCollection([calculateDBSI(mosaic_year).rename('DBSI')])
        bu = ee.ImageCollection([calculateBU(mosaic_year).rename('BU')])
        ndvi_collection_LT7 = ndvi_collection_LT7.merge(ndvi)
        dbsi_collection_LT7 = dbsi_collection_LT7.merge(dbsi)
        bu_collection_LT7 = bu_collection_LT7.merge(bu)
        mosaic_collection = mosaic_collection.merge(mos)
    return (ndvi_collection_LT7,bu_collection_LT7,mosaic_collection)

def descarga_landsat8(roi):
    ndvi_collection_LT8 = ee.ImageCollection([])
    dbsi_collection_LT8 = ee.ImageCollection([])
    bu_collection_LT8 = ee.ImageCollection([])
    mosaic_collection = ee.ImageCollection([])
    for year in range(2014, 2023):
        start_date = str(year) + '-01-01'
        end_date = str(year) + '-12-31'
        print(year)
       # Filtra la colección por el año y la región de interés
        landsat_collection = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2') \
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
