#!/bin/bash
#==================================================================================
# Basin delineation v01: one basin per array task. Submitted by arc_v01_2_submit.sh (ARC).
#   bash arguments: PHASE (dem | export) and LIST (file with one site_id per line)
#   dem    : 02 region, 03 outlet, 04 upstream, 05 DEM refinement
#   export : ordinary basin -> 06 export + 07 validation
#            basin with another station inside -> 05b/06b/07b (nested)
#==================================================================================
set -eo pipefail
PHASE=$1
LIST=$2
basinId=$(sed -n "${SLURM_ARRAY_TASK_ID}p" $LIST)
OUT=/work/comphyd_lab/share/dataset_develop/camels_mx/basin_delineation_v01

ENV=/work/comphyd_lab/users/nvasquez/envs/unified_delineation
export PATH=$ENV/bin:$PATH
export PROJ_DATA=$ENV/share/proj GDAL_DATA=$ENV/share/gdal
export PYTHONNOUSERSITE=1
export NUMBA_CACHE_DIR=/tmp/numba_$SLURM_JOB_ID
umask 002

ROOT=$(dirname $SLURM_SUBMIT_DIR)
C=$OUT/controls/control_$basinId.toml
T=1_delineation/tdx
cd $ROOT
echo "== $basinId $PHASE  task $SLURM_ARRAY_TASK_ID  $(date)"

if [ "$PHASE" = dem ]; then
  mkdir -p $OUT/$basinId/diagnostics
  python $T/02_select_tdx_region.py --control $C > $OUT/$basinId/diagnostics/tdx_region_selection.json
  python $T/03_select_tdx_outlet.py --control $C --allow-review
  python $T/04_trace_tdx_upstream.py --control $C --require-topology-index --require-shared-registry
  python $T/05_refine_tdx_outlet.py --control $C --dem-min-accumulation-cells 100
else
  # Nested if a planned split reach is in this basin, or another station is upstream
  NESTED=$(python - $basinId $C $OUT <<'PY'
import csv, json, sys, tomllib
import geopandas as gpd
site, control, out = sys.argv[1:]
region = tomllib.load(open(control, 'rb'))['input']['tdx_id']
plan = f'indexes/gauge_catalogs/tdx_shared_network/nested_split_plans/{region}_nested_split_parents.csv'
parents = {r.get('parent_tdx_reach_id', '') for r in csv.DictReader(open(plan))}
reaches = gpd.read_file(f'{out}/{site}/tdx_upstream_native.gpkg', layer='upstream_reaches', columns=['reach_id'])
actual = {str(x).removesuffix('.0') for x in reaches['reach_id']}
topo = json.load(open(f'{out}/{site}/diagnostics/step04/{site}_tdx_shared_gauge_topology.json'))
print('yes' if parents & actual or int(topo.get('related_gauge_count', 0)) else 'no')
PY
)
  echo "   nested: $NESTED"
  if [ "$NESTED" = yes ]; then
    python $T/05b_build_nested_hru_preview.py --control $C --allow-review --overwrite
    python $T/06b_export_nested_cwarhm_preview.py --control $C --allow-review --overwrite
    python $T/07b_validate_nested_cwarhm_preview.py --control $C
  else
    python $T/06_export_cwarhm_shapefiles.py --control $C --allow-review --overwrite
    python $T/07_validate_and_visualise.py --control $C --dpi 150
  fi
fi
echo "== $basinId $PHASE DONE $(date)"
