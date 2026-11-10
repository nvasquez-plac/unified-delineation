#!/bin/bash
#SBATCH --account=rrg-mclark
#SBATCH --job-name=delin_one_basin
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=3800M
#SBATCH --time=02:00:00
#SBATCH --output=delineation_%x_%j.out

#==================================================================================
# Delineate one CAMELS-MX basin on Fir (dem_refined), in your own clone.
# Run from your clone's jobSubmission folder:  sbatch delineate_one_basin_fir.sh
# Results: outputs/$USER/$basinId/ in your clone.
#==================================================================================
set -eo pipefail

# Basin to delineate (site_id from sites/sites.csv)
basinId=MX_22008

#==================================================================================
# Environment
#==================================================================================
module load StdEnv/2023 gcc/12.3 python/3.11 gdal/3.7.2
source /project/6079554/share/camels-mx/envs/unified_delineation/bin/activate
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
OUT=$ROOT/outputs/$USER
CTRL=$ROOT/0_control_files/tdx_one_basin
C=$CTRL/control_$basinId.toml
T=1_delineation/tdx
SNAPS=indexes/gauge_catalogs/tdx_snapping/global_500m/tdx_gauge_snaps_all.csv
cd $ROOT
echo "== $basinId  output: $OUT/$basinId"

#==================================================================================
# Gauge: take basin $basinId from sites/sites.csv (Estacion,site_id,longitude,latitude)
#==================================================================================
echo "site_id,latitude,longitude" > sites/sites_one.csv
grep "\"$basinId\"" sites/sites.csv | tr -d '"' | awk -F, '{print $2","$4","$3}' >> sites/sites_one.csv
cat sites/sites_one.csv

#==================================================================================
# 01 index TDX regions, 00 validate gauge
#==================================================================================
python $T/01_build_tdx_index.py --tdx-dir $TDX --index-dir indexes
python 1_delineation/common/00_prepare_gauge_catalog.py --catalog sites/sites_one.csv
CAT=indexes/gauge_catalogs/sites_one_validated.csv

#==================================================================================
# 02b snap gauge to TDX reach, 02e consolidate, 02f reach registry
#==================================================================================
python $T/02b_snap_gauge_catalog.py --catalog $CAT --region-index indexes/tdx_regions.csv \
  --tdx-root $TDX --output-dir indexes/gauge_catalogs/tdx_snapping/batch_500m \
  --start 0 --stop 1 --radius-m 500 --area-units m2
python $T/02e_consolidate_gauge_snaps.py --catalog $CAT
python $T/02f_build_shared_reach_registry.py --catalog $CAT --snaps $SNAPS

#==================================================================================
# 03a control file: Fir paths in the template, dem_refined, no observed area
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
# Region: 02 region file, 04 topology index, 04b nested plan
#==================================================================================
R=$(python -c "import tomllib; print(tomllib.load(open('$C','rb'))['input']['tdx_id'])")
mkdir -p $OUT/$basinId/diagnostics
python $T/02_select_tdx_region.py --control $C > $OUT/$basinId/diagnostics/tdx_region_selection.json
python $T/04_trace_tdx_upstream.py --control $C --build-topology-index --index-only
python $T/04b_plan_shared_nested_splits.py --region $R

#==================================================================================
# Basin: 03 outlet, 04 upstream, 05 DEM refine, 06 export, 07 validate
#==================================================================================
python $T/03_select_tdx_outlet.py --control $C --allow-review
python $T/04_trace_tdx_upstream.py --control $C --require-topology-index --require-shared-registry
python $T/05_refine_tdx_outlet.py --control $C --dem-min-accumulation-cells 100
python $T/06_export_cwarhm_shapefiles.py --control $C --allow-review --overwrite
python $T/07_validate_and_visualise.py --control $C --dpi 150

echo "== $basinId DONE  shapefiles: $OUT/$basinId/cwarhm_exports/tdx_clipped/shapefiles/"
