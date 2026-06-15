# SACBAD uc365 database registry scripts

Manage the **additive** catalog layer at `00_Database_Registry/` inside the
OneDrive project database. Does not modify existing `02_Tabular_Data` field files.

## Setup

```powershell
$env:SACBAD_DB_ROOT = "C:\Users\CCG UC\OneDrive - Universidad Católica de Chile\uc365_SACBAD Anillo 220055 - Database"
cd SACBAD_github
```

## Commands

```bash
# After copying team files into uc365
Rscript Scripts/db/register_team_files.R --db-root="$SACBAD_DB_ROOT"

# Validate foreign keys and paths
Rscript Scripts/db/check_integrity.R --db-root="$SACBAD_DB_ROOT"

# Build geospatial layer catalog (requires sf, terra)
Rscript Scripts/db/build_geo_inventory.R --db-root="$SACBAD_DB_ROOT"

# Full-database SHA256 manifest at database root
Rscript Scripts/db/build_manifest.R --db-root="$SACBAD_DB_ROOT"
```

Run `check_integrity.R` and update `CHANGELOG.md` before each Zenodo release.
