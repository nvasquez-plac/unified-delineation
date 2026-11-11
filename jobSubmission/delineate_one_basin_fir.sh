#!/bin/bash
#SBATCH --account=rrg-mclark
#SBATCH --job-name=delin_one_basin
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=3800M
#SBATCH --time=02:00:00
#SBATCH --output=logs/delineation_%x_%j.out

#==================================================================================
# Delineate one CAMELS-MX basin on Fir (dem_refined), in your own clone.
# Run from your clone's jobSubmission folder:  sbatch delineate_one_basin_fir.sh
# Results: outputs/$basinId/ in your clone.
#==================================================================================
set -eo pipefail

# Basin to delineate (site_id from sites/sites.csv)
basinId=MX_22008

#==================================================================================
# Environment: built on the node's local disk ($SLURM_TMPDIR) to keep IOPS off /project
# (~10 s). Packages: Alliance wheelhouse + pysheds/geojson wheels in envs/wheels.
# pyproj is removed so the proj module's pyproj 3.6.1 (matching PROJ 9.2.0) is used.
#==================================================================================
module load StdEnv/2023 gcc/12.3 python/3.11 gdal/3.7.2
ENVS=/project/6079554/share/camels-mx/envs
virtualenv --no-download --app-data $SLURM_TMPDIR/venv-cache $SLURM_TMPDIR/env
source $SLURM_TMPDIR/env/bin/activate
pip install -q --no-index --find-links $ENVS/wheels -r $ENVS/requirements_unified_delineation.txt
pip uninstall -q -y pyproj
export PYTHONNOUSERSITE=1
export EBPYTHONPREFIXES=$(echo "$EBPYTHONPREFIXES" | tr ':' '\n' | grep -v '/hdf5/' | paste -sd:)
export NUMBA_CACHE_DIR=$SLURM_TMPDIR/numba
umask 002

#==================================================================================
# Folders
#==================================================================================
ROOT=$(dirname $SLURM_SUBMIT_DIR)        # clone top folder (one above jobSubmission)
TDX=/project/6079554/share/camels-mx/data/data_copied_hpc/TDX_hydrofabrics
DEM=/project/6079554/share/camels-mx/data/data_copied_hpc/copernicus/glo-30
OUT=$ROOT/outputs
CTRL=$ROOT/0_control_files/tdx_one_basin
C=$CTRL/control_$basinId.toml
T=1_delineation/tdx
SNAPS=indexes/gauge_catalogs/tdx_snapping/global_500m/tdx_gauge_snaps_all.csv
cd $ROOT
echo "== $basinId  output: $OUT/$basinId"

#==================================================================================
# Gauge: take basin $basinId from sites/sites.csv (Estacion,site_id,longitude,latitude)
# Output: sites/sites_one.csv -> one row: site_id,latitude,longitude
#==================================================================================
echo "site_id,latitude,longitude" > sites/sites_one.csv
grep "\"$basinId\"" sites/sites.csv | tr -d '"' | awk -F, '{print $2","$4","$3}' >> sites/sites_one.csv
cat sites/sites_one.csv

#==================================================================================
# 01 index TDX regions: lists every TDX-Hydro region (basins + streamnet gpkg) and its extent
#    Output: indexes/tdx_regions.csv, indexes/tdx_local_health.csv (files found / readable)
# 00 validate gauge: checks ID, coordinates, duplicates
#    Output: indexes/gauge_catalogs/sites_one_validated.csv (+ _summary.json)
#==================================================================================
python $T/01_build_tdx_index.py --tdx-dir $TDX --index-dir indexes
python 1_delineation/common/00_prepare_gauge_catalog.py --catalog sites/sites_one.csv
CAT=indexes/gauge_catalogs/sites_one_validated.csv

#==================================================================================
# 02b snap gauge to the nearest TDX river reach (within 500 m)
#     Output: indexes/gauge_catalogs/tdx_snapping/batch_500m/
#             tdx_gauge_snaps_*.csv (chosen reach), tdx_snap_candidates_*.csv, tdx_snap_summary_*.json
# 02e consolidate the snap batches into one table and check them (PASS/FAIL)
#     Output: .../tdx_snapping/global_500m/tdx_gauge_snaps_all.csv, tdx_global_summary.json
# 02f reach registry: which gauges share a reach / sit upstream of each other
#     Output: indexes/gauge_catalogs/tdx_shared_network/tdx_gauge_reach_registry.csv (+ summary)
#==================================================================================
python $T/02b_snap_gauge_catalog.py --catalog $CAT --region-index indexes/tdx_regions.csv \
  --tdx-root $TDX --output-dir indexes/gauge_catalogs/tdx_snapping/batch_500m \
  --start 0 --stop 1 --radius-m 500 --area-units m2
# 02b names a whole-catalogue run "_all"; 02e looks for "_0000_0001"
cd indexes/gauge_catalogs/tdx_snapping/batch_500m
for f in tdx_gauge_snaps tdx_snap_candidates; do mv ${f}_all.csv ${f}_0000_0001.csv; done
mv tdx_snap_summary_all.json tdx_snap_summary_0000_0001.json
cd $ROOT
python $T/02e_consolidate_gauge_snaps.py --catalog $CAT
python $T/02f_build_shared_reach_registry.py --catalog $CAT --snaps $SNAPS

#==================================================================================
# 03a control file: Fir paths in the template, dem_refined, no observed area
#     Output: 0_control_files/template_one_basin.toml (template with Fir paths)
#             0_control_files/tdx_one_basin/control_$basinId.toml (settings for this basin,
#             read by every step below)
#==================================================================================
cp 0_control_files/control_USGS_10343500.toml 0_control_files/template_one_basin.toml
sed -i -e "s#^tdx_directory = .*#tdx_directory = \"$TDX\"#" \
       -e "s#^dem_directory = \"/work.*#dem_directory = \"$DEM\"#" \
       -e "s#^output_directory = .*#output_directory = \"$OUT\"#" \
       0_control_files/template_one_basin.toml
       
# 03a needs an expected area: give 1 km2 now, set it to 0 afterwards
python -c "import pandas as p; d=p.read_csv('$CAT'); d['expected_area_km2']=1; d.to_csv('indexes/gauge_catalogs/sites_one_area.csv', index=False)"
python 1_delineation/common/03a_generate_batch_controls.py \
  --template 0_control_files/template_one_basin.toml \
  --catalog indexes/gauge_catalogs/sites_one_area.csv --snaps $SNAPS \
  --registry indexes/gauge_catalogs/tdx_shared_network/tdx_gauge_reach_registry.csv \
  --region-index indexes/tdx_regions.csv \
  --output-dir $CTRL --method dem_refined --write --overwrite
sed -i 's/^observed_area_km2 = .*/observed_area_km2 = 0/' $C

#==================================================================================
# Region preparation (once per TDX region)
# 02  pick the TDX region that contains the gauge
#     Output: outputs/$basinId/diagnostics/tdx_region_selection.json
# 04  build the region's river topology index (who flows into whom), reused by step 04
#     Output: indexes/tdx_regional_topology/<region>_topology.sqlite
# 04b plan splits where another gauge sits inside this basin (none for a single gauge)
#     Output: indexes/gauge_catalogs/tdx_shared_network/nested_split_plans/
#==================================================================================
R=$(python -c "import tomllib; print(tomllib.load(open('$C','rb'))['input']['tdx_id'])")
mkdir -p $OUT/$basinId/diagnostics
python $T/02_select_tdx_region.py --control $C > $OUT/$basinId/diagnostics/tdx_region_selection.json
python $T/04_trace_tdx_upstream.py --control $C --build-topology-index --index-only
python $T/04b_plan_shared_nested_splits.py --region $R

#==================================================================================
# Basin steps, all written to outputs/$basinId/
# 03 outlet: choose the TDX reach/sub-basin at the gauge
#    Output: tdx_outlet_selection.json, diagnostics/step03/outlet_candidates.csv
# 04 upstream: trace every TDX sub-basin draining to the outlet (native TDX basin)
#    Output: tdx_upstream_native.gpkg, tdx_upstream_summary.json
# 05 DEM refine: re-draw the outlet sub-basin from the Copernicus DEM so the basin ends
#    exactly at the gauge (dem_refined)
#    Output: tdx_upstream_refined.gpkg, tdx_refinement_summary.json, diagnostics/step05/*.tif
# 06 export: shapefiles for SUMMA/mizuRoute (catchment, HRUs, river network)
#    Output: cwarhm_exports/tdx_clipped/shapefiles/ (folders catchment/, river_basins/, river_network/)
#            tdx_clipped = HRUs clipped to the Copernicus DEM (use this); tdx_native = plain TDX
# 07 validate: checks geometry/topology, makes maps
#    Output: validation/step07_validation_summary.json + maps (validation_map.jpg, native_vs_clipped_comparison.jpg)
#==================================================================================
python $T/03_select_tdx_outlet.py --control $C --allow-review
python $T/04_trace_tdx_upstream.py --control $C --require-topology-index --require-shared-registry
python $T/05_refine_tdx_outlet.py --control $C --dem-min-accumulation-cells 100
python $T/06_export_cwarhm_shapefiles.py --control $C --allow-review --overwrite
python $T/07_validate_and_visualise.py --control $C --dpi 150

echo "== $basinId DONE  shapefiles: $OUT/$basinId/cwarhm_exports/tdx_clipped/shapefiles/"
