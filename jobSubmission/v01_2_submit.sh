#!/bin/bash
#==================================================================================
# Basin delineation v01, part 2 of 2: submit every basin (run on the login node,
# from your clone's jobSubmission folder, after v01_1_prepare.sh finished):
#     bash v01_2_submit.sh
# Four job arrays, one task per basin:
#   dem_normal / dem_large       : steps 02-05            (start now)
#   export_normal / export_large : steps 06-07 or 05b-07b (start when ALL dem tasks ended,
#                                  because nested basins need their upstream stations)
# Large = TDX upstream area >= 20,000 km2 (more memory and time).
# Logs: jobSubmission/logs/v01_<phase>_<jobid>_<task>.out
#==================================================================================
set -eo pipefail
LISTS=/project/6079554/share/camels-mx/data/basin_delineation/v01/lists
NN=$(wc -l < $LISTS/basins_normal.txt)
NL=$(wc -l < $LISTS/basins_large.txt)
echo "basins: $NN normal, $NL large"
DEPS=""

if [ $NN -gt 0 ]; then
  J=$(sbatch --parsable --account=rrg-mclark --array=1-$NN --job-name=v01_dem_normal \
      --cpus-per-task=8 --mem-per-cpu=3800M --time=03:00:00 \
      --output=logs/v01_dem_normal_%A_%a.out v01_basin_task.sh dem $LISTS/basins_normal.txt)
  echo "dem_normal: $J"; DEPS=$J
fi
if [ $NL -gt 0 ]; then
  J=$(sbatch --parsable --account=rrg-mclark --array=1-$NL --job-name=v01_dem_large \
      --cpus-per-task=32 --mem-per-cpu=3800M --time=12:00:00 \
      --output=logs/v01_dem_large_%A_%a.out v01_basin_task.sh dem $LISTS/basins_large.txt)
  echo "dem_large: $J"; DEPS=${DEPS:+$DEPS:}$J
fi
if [ $NN -gt 0 ]; then
  J=$(sbatch --parsable --account=rrg-mclark --array=1-$NN --job-name=v01_export_normal \
      --dependency=afterany:$DEPS --cpus-per-task=8 --mem-per-cpu=3800M --time=03:00:00 \
      --output=logs/v01_export_normal_%A_%a.out v01_basin_task.sh export $LISTS/basins_normal.txt)
  echo "export_normal: $J (waits for $DEPS)"
fi
if [ $NL -gt 0 ]; then
  J=$(sbatch --parsable --account=rrg-mclark --array=1-$NL --job-name=v01_export_large \
      --dependency=afterany:$DEPS --cpus-per-task=32 --mem-per-cpu=3800M --time=12:00:00 \
      --output=logs/v01_export_large_%A_%a.out v01_basin_task.sh export $LISTS/basins_large.txt)
  echo "export_large: $J (waits for $DEPS)"
fi
