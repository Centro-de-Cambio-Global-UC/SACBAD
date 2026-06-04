# -*- coding: utf-8 -*-
"""
Clip annual VIIRS GeoTIFFs to the SACBAD cut_area shapefile.

Usage (from repository root):
  python Scripts/extended/viirs/python/cut_20km.py
  python Scripts/extended/viirs/python/cut_20km.py --input Output/extended/viirs/Download/viirs_avg_rad_new_years
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import fiona
import rasterio
from rasterio.mask import mask

# Allow import of viirs_paths from Scripts/extended/viirs/
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from viirs_paths import VIIRS_ANNUAL, VIIRS_ANNUAL_CUT, cut_area_shp, ensure_workdirs


def clip_folder(input_dir: Path, output_dir: Path, shapefile_path: Path) -> int:
    if not shapefile_path.is_file():
        raise FileNotFoundError(f"Shapefile not found: {shapefile_path}")
    if not input_dir.is_dir():
        raise FileNotFoundError(
            f"Input folder not found: {input_dir}\n"
            "Run notebook 0)VIIRS_download.ipynb first (from Output/extended/viirs/)."
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    tif_files = sorted(input_dir.glob("*.tif"))
    if not tif_files:
        raise FileNotFoundError(f"No .tif files in {input_dir}")

    with fiona.open(str(shapefile_path), "r") as shapefile:
        shapes = [feature["geometry"] for feature in shapefile]

    n_ok = 0
    for tif in tif_files:
        out_path = output_dir / tif.name
        with rasterio.open(tif) as src:
            out_image, out_transform = mask(src, shapes, crop=True)
            out_meta = src.meta.copy()
        out_meta.update(
            {
                "driver": "GTiff",
                "height": out_image.shape[1],
                "width": out_image.shape[2],
                "transform": out_transform,
            }
        )
        with rasterio.open(out_path, "w", **out_meta) as dest:
            dest.write(out_image)
        n_ok += 1
        print(f"  wrote {out_path.name}")

    return n_ok


def main() -> None:
    parser = argparse.ArgumentParser(description="Clip VIIRS annual rasters to cut_area.")
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="Folder with annual VIIRS .tif (default: Output/extended/viirs/Download/viirs_avg_rad_new_years)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output folder (default: Output/extended/viirs/Download/viirs_avg_rad/cortado)",
    )
    args = parser.parse_args()

    ensure_workdirs()
    input_dir = args.input or VIIRS_ANNUAL
    output_dir = args.output or VIIRS_ANNUAL_CUT
    shp = cut_area_shp()

    print(f"Shapefile: {shp}")
    print(f"Input:     {input_dir}")
    print(f"Output:    {output_dir}")
    n = clip_folder(input_dir, output_dir, shp)
    print(f"Done. {n} raster(s) clipped.")


if __name__ == "__main__":
    main()
