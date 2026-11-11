#!/bin/bash
#SBATCH --account=rrg-mclark
#SBATCH --job-name=v01_prepare
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=3800M
#SBATCH --time=08:00:00
#SBATCH --output=logs/v01_prepare_%j.out

#==================================================================================
# Basin delineation v01, part 1 of 2: shared preparation for ALL stations.
# Run from your clone's jobSubmission folder:   sbatch v01_1_prepare.sh
# When it finishes:                            bash v01_2_submit.sh
# Workflow and scripts: Wouter Knoben (CAMELS-SPAT); see README.
#==================================================================================
set -eo pipefail

# Station list (basinId|X|Y, X = longitude, Y = latitude) and output folder
STATIONS=sites/HS_verified_v09.txt
OUT=/project/6079554/share/camels-mx/data/basin_delineation/v01

#==================================================================================
# Environment (built on the node's local disk to keep IOPS off /project)
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
DEM=/project/6102189/data/geospatial-data/copernicus/glo-30
CTRL=$OUT/controls
LISTS=$OUT/lists
T=1_delineation/tdx
SNAPS=indexes/gauge_catalogs/tdx_snapping/global_500m/tdx_gauge_snaps_all.csv
REGISTRY=indexes/gauge_catalogs/tdx_shared_network/tdx_gauge_reach_registry.csv
PLANS=indexes/gauge_catalogs/tdx_shared_network/nested_split_plans
cd $ROOT
mkdir -p $OUT $CTRL $LISTS
echo "== v01 prepare  clone: $ROOT  output: $OUT  $(date)"

#==================================================================================
# Stations: HS_verified_v09.txt -> sites/v01_sites.csv (site_id,latitude,longitude)
# A basinId listed twice keeps its LAST row; the duplicates are printed here.
# Output: sites/v01_sites.csv
#==================================================================================
python - $STATIONS <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8-sig'), delimiter='|'))
keep, seen = {}, {}
for r in rows:
    s = r['basinId'].strip()
    seen[s] = seen.get(s, 0) + 1
    keep[s] = (r['Y'].strip(), r['X'].strip())
dups = sorted(s for s, n in seen.items() if n > 1)
print(f'stations: {len(rows)} rows, {len(keep)} unique basinId; duplicated (last row kept): {dups}')
with open('sites/v01_sites.csv', 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['site_id', 'latitude', 'longitude'])
    for s, (lat, lon) in keep.items():
        w.writerow([s, lat, lon])
PY

#==================================================================================
# 01 index TDX regions          -> indexes/tdx_regions.csv
# 00 validate stations          -> indexes/gauge_catalogs/v01_sites_validated.csv
#==================================================================================
python $T/01_build_tdx_index.py --tdx-dir $TDX --index-dir indexes
python 1_delineation/common/00_prepare_gauge_catalog.py --catalog sites/v01_sites.csv
CAT=indexes/gauge_catalogs/v01_sites_validated.csv
N=$(( $(wc -l < $CAT) - 1 ))
echo "== validated stations: $N"

#==================================================================================
# 02b snap each station to the nearest TDX reach (500 m), in blocks of 20
#     -> indexes/gauge_catalogs/tdx_snapping/batch_500m/tdx_gauge_snaps_<start>_<stop>.csv
# 02e consolidate the blocks    -> .../global_500m/tdx_gauge_snaps_all.csv
# 02f shared reach registry     -> indexes/gauge_catalogs/tdx_shared_network/
#==================================================================================
rm -rf indexes/gauge_catalogs/tdx_snapping/batch_500m
for START in $(seq 0 20 $((N-1))); do
  STOP=$(( START+20 < N ? START+20 : N ))
  echo "== 02b block $START-$STOP $(date)"
  python $T/02b_snap_gauge_catalog.py --catalog $CAT --region-index indexes/tdx_regions.csv \
    --tdx-root $TDX --output-dir indexes/gauge_catalogs/tdx_snapping/batch_500m \
    --start $START --stop $STOP --radius-m 500 --area-units m2
done
python $T/02e_consolidate_gauge_snaps.py --catalog $CAT
python $T/02f_build_shared_reach_registry.py --catalog $CAT --snaps $SNAPS

#==================================================================================
# 03a control files: Fir paths, dem_refined, no observed area, large DEM windows allowed
#     -> $OUT/controls/control_<site>.toml + batch_controls_manifest.csv
#==================================================================================
cp 0_control_files/control_USGS_10343500.toml $CTRL/template_v01.toml
sed -i -e "s#^tdx_directory = .*#tdx_directory = \"$TDX\"#" \
       -e "s#^dem_directory = \"/work.*#dem_directory = \"$DEM\"#" \
       -e "s#^output_directory = .*#output_directory = \"$OUT\"#" \
       -e "s#^dem_max_cells = .*#dem_max_cells = 400000000#" \
       $CTRL/template_v01.toml
# 03a needs an expected area: give 1 km2 now, set it to 0 afterwards
python -c "import pandas as p; d=p.read_csv('$CAT'); d['expected_area_km2']=1; d.to_csv('indexes/gauge_catalogs/v01_sites_area.csv', index=False)"
python 1_delineation/common/03a_generate_batch_controls.py \
  --template $CTRL/template_v01.toml \
  --catalog indexes/gauge_catalogs/v01_sites_area.csv --snaps $SNAPS --registry $REGISTRY \
  --region-index indexes/tdx_regions.csv \
  --output-dir $CTRL --method dem_refined --write --overwrite
sed -i 's/^observed_area_km2 = .*/observed_area_km2 = 0/' $CTRL/control_*.toml

#==================================================================================
# Basin lists for part 2 (stations with a TDX reach and a control file)
#     normal: TDX upstream area <  20,000 km2 -> $OUT/lists/basins_normal.txt
#     large : TDX upstream area >= 20,000 km2 -> $OUT/lists/basins_large.txt
#     not delineated (no reach within 500 m)  -> $OUT/lists/not_snapped.txt
#==================================================================================
python - $CTRL/batch_controls_manifest.csv $SNAPS $LISTS <<'PY'
import csv, sys
manifest, snaps, lists = sys.argv[1:]
area = {r['site_id']: float(r['tdx_upstream_area_km2'] or 0) for r in csv.DictReader(open(snaps))}
rows = list(csv.DictReader(open(manifest)))
ready = [r for r in rows if r['source_input_ready'] == 'true']
normal = [r['site_id'] for r in ready if area.get(r['site_id'], 0) < 20000]
large = [r['site_id'] for r in ready if area.get(r['site_id'], 0) >= 20000]
missing = sorted(set(area) - {r['site_id'] for r in ready})
for name, ids in (('basins_normal', normal), ('basins_large', large), ('not_snapped', missing)):
    open(f'{lists}/{name}.txt', 'w').write(''.join(i + '\n' for i in ids))
print(f'basins to delineate: {len(normal)} normal + {len(large)} large; not snapped: {len(missing)}')
regions = {}
for r in ready:
    regions.setdefault(r['tdx_id'], r['site_id'])
open(f'{lists}/regions.txt', 'w').write(''.join(f'{k} {v}\n' for k, v in sorted(regions.items())))
PY

#==================================================================================
# Region preparation (once per TDX region, using one station of that region)
# 02  region selection          -> $OUT/<site>/diagnostics/tdx_region_selection.json
# 04  river topology index      -> indexes/tdx_regional_topology/<region>_topology.sqlite
# 04b nested-station split plan -> indexes/gauge_catalogs/tdx_shared_network/nested_split_plans/
# 04c split geometry check (only if 04b planned splits)
#==================================================================================
while read R S; do
  echo "== region $R (via $S) $(date)"
  C=$CTRL/control_$S.toml
  mkdir -p $OUT/$S/diagnostics
  python $T/02_select_tdx_region.py --control $C > $OUT/$S/diagnostics/tdx_region_selection.json
  python $T/04_trace_tdx_upstream.py --control $C --build-topology-index --index-only
  python $T/04b_plan_shared_nested_splits.py --region $R
  SPLITS=$(python -c "import json; print(json.load(open('$PLANS/${R}_nested_summary.json')).get('candidate_parent_reaches_requiring_split',0))")
  echo "   planned nested splits: $SPLITS"
  if [ "$SPLITS" -gt 0 ]; then
    python $T/04c_validate_shared_split_geometry.py --region $R || echo "   WARNING: 04c failed for $R; nested basins in this region will fail in export"
  fi
done < $LISTS/regions.txt

echo "== v01 prepare DONE $(date). Next: bash v01_2_submit.sh"
