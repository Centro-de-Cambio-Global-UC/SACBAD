"""
Repository-relative paths for the VIIRS extended workflow.

All outputs live under Output/extended/viirs/ (gitignored).
Shapefiles are read from Input/extended/viirs/shapefiles/ (versioned).
"""
from __future__ import annotations

import os
from pathlib import Path


def find_repo_root(start: Path | None = None) -> Path:
    """Walk up from *start* until a directory containing Input/ is found."""
    here = (start or Path(__file__).resolve()).parent
    for cand in [here, *here.parents]:
        if (cand / "Input").is_dir() and (cand / "Scripts").is_dir():
            return cand
    raise FileNotFoundError(
        "Could not locate SACBAD repository root (expected Input/ and Scripts/)."
    )


REPO_ROOT = find_repo_root()
SHAPEFILES_SRC = REPO_ROOT / "Input" / "extended" / "viirs" / "shapefiles"
WORK_ROOT = REPO_ROOT / "Output" / "extended" / "viirs"
SHAPEFILES_WORK = WORK_ROOT / "shapefiles"

VIIRS_RAW = WORK_ROOT / "Download" / "viirs_avg_rad" / "raw"
VIIRS_CUT = WORK_ROOT / "Download" / "viirs_avg_rad" / "cut"
VIIRS_DENOISE = WORK_ROOT / "Download" / "viirs_avg_rad" / "background_denoise" / "denoise"
VIIRS_ANNUAL = WORK_ROOT / "Download" / "viirs_avg_rad_new_years"
VIIRS_ANNUAL_CUT = WORK_ROOT / "Download" / "viirs_avg_rad" / "cortado"
VIIRS_POSTPROCESSED = WORK_ROOT / "output_post-processed"


def ensure_workdirs() -> Path:
    """Create the VIIRS working tree and link/copy shapefiles into it."""
    import shutil

    for d in (
        WORK_ROOT,
        SHAPEFILES_WORK,
        VIIRS_RAW,
        VIIRS_CUT,
        VIIRS_DENOISE,
        VIIRS_ANNUAL,
        VIIRS_ANNUAL_CUT,
        VIIRS_POSTPROCESSED,
    ):
        d.mkdir(parents=True, exist_ok=True)

    if not SHAPEFILES_SRC.is_dir():
        raise FileNotFoundError(f"Missing shapefiles directory: {SHAPEFILES_SRC}")

    for name in ("cut_area", "point_control"):
        shp = SHAPEFILES_SRC / f"{name}.shp"
        if not shp.is_file():
            raise FileNotFoundError(f"Required shapefile not found: {shp}")
        for ext in (".shp", ".shx", ".dbf", ".prj", ".cpg", ".qix", ".qmd"):
            src = SHAPEFILES_SRC / f"{name}{ext}"
            if src.is_file():
                dst = SHAPEFILES_WORK / src.name
                if not dst.exists() or src.stat().st_mtime > dst.stat().st_mtime:
                    shutil.copy2(src, dst)

    gpkg = SHAPEFILES_SRC / "cut_area.gpkg"
    if gpkg.is_file():
        dst = SHAPEFILES_WORK / gpkg.name
        if not dst.exists() or gpkg.stat().st_mtime > dst.stat().st_mtime:
            shutil.copy2(gpkg, dst)

    return WORK_ROOT


def cut_area_shp() -> Path:
    return SHAPEFILES_WORK / "cut_area.shp"


def point_control_shp() -> Path:
    return SHAPEFILES_WORK / "point_control.shp"
