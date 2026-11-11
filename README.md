# Unified Delineation

**Unified Delineation** is a research workflow for delineating watersheds, organizing river networks, and preparing geospatial inputs for distributed hydrological models. Its modular structure separates common data preparation and validation from delineation methods, allowing additional hydrofabric- and DEM-based methods to be incorporated over time.

The currently implemented and batch-tested workflow uses **TDX-Hydro** river networks and catchment polygons. It supports one gauge or a catalogue of gauges, including candidate gauge-to-river snapping, upstream-network tracing, nested/shared-reach analysis, per-basin CWARHM-style GIS exports, structural validation, and a combined ArcGIS review dataset.

> **Credit:** the delineation workflow and scripts in this repository are **Wouter Knoben's** (CAMELS-SPAT / CWARHM). This copy (branch `camels-mx`, forked from [Armanhd/unified-delineation](https://github.com/Armanhd/unified-delineation)) adds some fixes, the gauge list of 21 CAMELS-MX test basins, a Fir job script to run Wouter's workflow, and an example with its outputs (`examples/MX_22008/`); the hydrological method itself is unchanged. If you use these scripts or outputs, please cite:
>
> - Knoben, W. J. M., Thébault, C., Keshavarz, K., Torres-Rojas, L., Chaney, N. W., Pietroniro, A., and Clark, M. P. (2025). Catchment Attributes and MEteorology for Large-Sample SPATially distributed analysis (CAMELS-SPAT): streamflow observations, forcing data and geospatial data for hydrologic studies across North America. *Hydrology and Earth System Sciences*, 29, 5791–5833. <https://doi.org/10.5194/hess-29-5791-2025>
> - Knoben, W. J. M., Clark, M. P., Bales, J., Bennett, A., Gharari, S., Marsh, C. B., Nijssen, B., Pietroniro, A., Spiteri, R. J., Tang, G., Tarboton, D. G., and Wood, A. W. (2022). Community workflows to advance reproducibility in hydrologic modeling: Separating model-agnostic and model-specific configuration steps in applications of large-domain hydrologic models. *Water Resources Research*, 58(11), e2021WR031753. <https://doi.org/10.1029/2021WR031753>
>
> CAMELS-SPAT code: <https://github.com/CH-Earth/camels_spat> · data: <https://dx.doi.org/10.20383/103.01216>

> **Research / QA status:** Outputs are preliminary. A completed Slurm job, successful GIS export, or structural validation pass does **not** establish that a gauge location or watershed is hydrologically correct or approved for CWARHM/SUMMA production. Review status and any uncertainties must be preserved. **Please note you should corroborate that the basin delineation is correct**. 

## What the workflow does

| Component | Main scripts | Function |
|---|---|---|
| **1. Gauge catalogue** | `1_delineation/common/00_prepare_gauge_catalog.py` | Check station IDs, WGS84 coordinates, and optional reference drainage area. |
| **2. TDX source inventory** | `1_delineation/tdx/01_build_tdx_index.py` | Index TDX-Hydro regional basin and stream-network GeoPackages; report metadata problems. |
| **3. Gauge snapping** | `1_delineation/tdx/02b_snap_gauge_catalog.py`, `run_02b_snap_gauge_array.sh` | Identify candidate TDX reaches near gauges. Default initial search is 500 m; failed sites can be retried at 2,000 m. |
| **4. Snapping QA and nested gauges** | `02e_consolidate_gauge_snaps.py`, `02f_build_shared_reach_registry.py` | Consolidate candidate matches, reconcile retries, and identify gauges on shared TDX parent reaches. |
| **5. Basin configuration** | `1_delineation/common/03a_generate_batch_controls.py` | Generate a basin-specific TOML control and source-readiness manifest. |
| **6. Regional/network preparation** | `1_delineation/tdx/04b_plan_shared_nested_splits.py`, `04c_validate_shared_split_geometry.py`, `1_delineation/common/09_global_tdx_id_audit.py` | Prepare nested-reach candidates, test geometry/connectivity, and check TDX identifier consistency. |
| **7. Basin delineation** | `02_select_tdx_region.py`, `03_select_tdx_outlet.py`, `04_trace_tdx_upstream.py`, `05_refine_tdx_outlet.py`, `05b_build_nested_hru_preview.py` | Select the outlet, trace upstream catchments/reaches, and prepare the selected full/native or applicable refinement/nested previews. |
| **8. GIS export and validation** | `06_export_cwarhm_shapefiles.py`, `06b_export_nested_cwarhm_preview.py`, `07_validate_and_visualise.py`, `07b_validate_nested_cwarhm_preview.py` | Export CWARHM-style catchments and river geometries, with QA/validation summaries. |
| **9. Batch management** | `1_delineation/common/09_tdx_batch.py` | Prepare tasks, submit dependency-controlled Slurm arrays, and collect results. |
| **10. ArcGIS review** | `1_delineation/tdx/10_build_arcgis_review_layers.py` | Assemble available results for *all* gauges, including unmatched/failed sites, into one review GeoPackage. |

The TDX pipeline uses native TDX hydrological connectivity as the basis for the upstream catchment. The tested `--method full` setup retains native TDX HRUs; it does **not** imply that DEM-based trimming of the outlet HRU has been applied. Other methods can be introduced under `1_delineation/` without changing the purpose of the common components.

## Repository layout

```text
unified-delineation/
├── .gitignore
├── README.md
├── 0_control_files/
│   └── control_USGS_10343500.toml   # Example/template settings
├── 1_delineation/
│   ├── common/                       # Catalogue, controls, Slurm, ID audit
│   ├── tdx/                          # TDX-Hydro stages and ArcGIS review
│   ├── merit/                        # Space for additional methods
│   └── dem/                          # Space for DEM-based workflows
├── jobSubmission/
│   ├── delineate_one_basin_fir.sh   # Fir: one basin, all steps, dem_refined
│   ├── v01_1_prepare.sh             # Fir: all stations, shared preparation (sbatch)
│   ├── v01_2_submit.sh              # Fir: all stations, submit per-basin job arrays (bash)
│   ├── v01_basin_task.sh            # Fir: one basin per array task (used by v01_2_submit.sh)
│   └── logs/                        # Slurm logs (not tracked)
├── sites/
│   ├── sites.csv                    # 21 CAMELS-MX test basins
│   └── HS_verified_v09.txt          # Full CAMELS-MX station list for v01 (basinId|X|Y)
├── examples/
│   └── MX_22008/                    # Complete example outputs of the Fir job (MX_22008)
├── environments/
│   ├── setup_conda_env.sh
│   ├── load_module_env.sh
│   └── unified_delineation.yml
└── docs/
    └── Manual_TDX_Delineation.md
```

The `docs/` manual is a separate, detailed operating guide. The `merit/` and `dem/` paths do not necessarily contain complete, tested implementations. Generated inputs, temporary indexes, model-ready files, and batch outputs live outside version control; the only exception is the example in `examples/MX_22008/`.

## Inputs and prerequisites

- **Gauge catalogue (CSV):** `site_id`, `latitude`, `longitude` (EPSG:4326); optional `expected_area_km2` and `process_basin`.
- **TDX-Hydro inputs:** regional `*-basins.gpkg` and `*-streamnet.gpkg` files, supplied separately. Large source hydrofabrics are **not** included in this repository.
- **Control TOML:** a verified single-basin template containing source paths, delineation settings, and output settings.
- **Environment:** Python geospatial and raster libraries specified under `environments/`; the current parallel orchestration uses Slurm on an HPC system.

**First-time environment setup on the University of Calgary ARC system:**

```bash
cd /work/comphyd_lab/users/arman.haddadchi/unified_delineation_code
sbatch environments/setup_conda_env.sh
```

After the setup job completes successfully, activate in a new/current shell:

```bash
module load conda/base
conda activate unified_delineation
```

These absolute ARC paths and module names are installation-specific; other users must configure their own repository, TDX data, and environment locations.

## Quick start on Fir (Alliance): delineate one basin

The job below runs **Wouter's delineation scripts** unchanged (all steps from `1_delineation/`); `jobSubmission/delineate_one_basin_fir.sh` only chains them together with Fir paths.

On Fir everything is already installed in the `rrg-mclark` project space, so each person only needs their own clone. The Python package list, TDX-Hydro and the Copernicus GLO-30 DEM are shared and only read by the job:

| Shared input | Fir path |
|---|---|
| Python environment | built by each job in `$SLURM_TMPDIR` from `/project/6079554/share/camels-mx/envs/requirements_unified_delineation.txt` + `envs/wheels/` (modules `StdEnv/2023 gcc/12.3 python/3.11 gdal/3.7.2`) |
| TDX-Hydro (all of Mexico: regions 7020000010, 7020047840) | `/project/6079554/share/camels-mx/data/data_copied_hpc/TDX_hydrofabrics` |
| Copernicus GLO-30 DEM | `/project/6079554/share/camels-mx/data/data_copied_hpc/copernicus/glo-30` |
| Gauges (21 CAMELS-MX **test basins**) | `sites/sites.csv` in this repository |

**1. Clone (first time)**

```bash
mkdir -p /project/6079554/share/camels-mx/users/$USER
cd /project/6079554/share/camels-mx/users/$USER
git clone -b camels-mx https://github.com/nvasquez-plac/unified-delineation.git
```

Or, if you already have a clone, update it:

```bash
cd /project/6079554/share/camels-mx/users/$USER/unified-delineation
git checkout camels-mx
git pull
```

**2. Submit the job**

```bash
cd /project/6079554/share/camels-mx/users/$USER/unified-delineation/jobSubmission
sbatch delineate_one_basin_fir.sh
```

`jobSubmission/delineate_one_basin_fir.sh` runs the whole workflow for one basin (steps 01, 00, 02b, 02e, 02f, 03a, 02, 04 index, 04b, 03, 04, 05, 06, 07) with the DEM-refined outlet (`--method dem_refined`). MX_22008 takes about 6 minutes with 8 CPUs. Each block in the script is commented with the files it writes.

**3. Follow the job**

```bash
squeue -u $USER
tail -F delineation_delin_one_basin_<jobid>.out    # <jobid> is the number printed by sbatch
```

The log ends with the step 07 summary (`checks_pass`, `overall_status`) and a `DONE` line.

**4. Results** (inside your clone)

| What | Where |
|---|---|
| Basin shapefiles to use (HRUs clipped to the DEM) | `outputs/MX_22008/cwarhm_exports/tdx_clipped/shapefiles/` (`catchment/`, `river_basins/`, `river_network/`) |
| Same, with plain TDX HRUs | `outputs/MX_22008/cwarhm_exports/tdx_native/shapefiles/` |
| Validation summary and maps | `outputs/MX_22008/validation/` (`step07_validation_summary.json`, `*.jpg`) |
| Control file used | `0_control_files/tdx_one_basin/control_MX_22008.toml` |

**5. Another basin**

Change the line near the top of `jobSubmission/delineate_one_basin_fir.sh`:

```bash
basinId=MX_26282
```

and submit again. The 21 gauges in `sites/sites.csv` are **test basins** used to check the workflow, not the final CAMELS-MX station list. Any `site_id` there works, except the nested basins MX_12428, MX_12496 and MX_12532, which need the nested steps (05b/06b/07b).

Status `REVIEW` is expected: there is no observed drainage area for CAMELS-MX, so the outlet is chosen automatically and should be checked in a GIS.

**6. Example with outputs**

The repository now includes the complete outputs of one run of `jobSubmission/delineate_one_basin_fir.sh` for **MX_22008** (Boquilla Número 1) in `examples/MX_22008/`. Use it to see what the job produces before running it, or to compare with your own `outputs/MX_22008/` (they should match).

| Result | Value |
|---|---|
| Method | `dem_refined` (Copernicus GLO-30) |
| DEM-refined basin area (`tdx_clipped`) | 4,671.4 km² |
| Native TDX basin area (`tdx_native`) | 4,674.4 km² |
| HRUs / river reaches | 555 / 555 |
| Validation | both variants pass; DEM coverage by HRUs 100 %; status `REVIEW` |

| In `examples/MX_22008/` | Content | Step |
|---|---|---|
| `diagnostics/` (`step02/`, `step04/`, `step05/`, `*.json`, `*.jpg`) | Region choice, outlet candidates, upstream trace, DEM outlet refinement, preview maps | 02–05 |
| `tdx_upstream_native.gpkg` | Upstream TDX sub-basins and reaches | 04 |
| `tdx_upstream_refined.gpkg` | Same, with the outlet sub-basin redrawn from the DEM | 05 |
| `cwarhm_exports/tdx_clipped/shapefiles/` | **Final shapefiles to use**: `catchment/`, `river_basins/` (HRUs), `river_network/` | 06 |
| `cwarhm_exports/tdx_native/shapefiles/` | Same, with plain TDX HRUs | 06 |
| `cwarhm_exports/*/metadata/` | Export metadata and river/HRU diagnostics | 06 |
| `validation/` | `step07_validation_summary.json`, `validation_map.jpg`, `native_vs_clipped_comparison.jpg` | 07 |

Paths written inside the JSON files point to the Fir run (`/project/6079554/...`); the files themselves are complete. Your own runs go to `outputs/` (ignored by git), so they never overwrite the example.

## Delineating all stations on Fir (v01 batch)

To delineate the full CAMELS-MX station list (`sites/HS_verified_v09.txt`, ~870 stations) instead of one basin, use the three `v01_*` scripts in `jobSubmission/`. They run the same Wouter Knoben workflow steps as the single-basin job (dem_refined outlet, no observed area), but share the preparation across all stations and run one Slurm task per basin.

| Item | Location |
|---|---|
| Station list (`basinId\|X\|Y`, X = longitude, Y = latitude) | `sites/HS_verified_v09.txt` |
| All results | `/project/6079554/share/camels-mx/data/basin_delineation/v01/` |
| Control files (one per basin) | `v01/controls/control_<basinId>.toml` |
| Basin lists used by the job arrays | `v01/lists/` (`basins_normal.txt`, `basins_large.txt`, `not_snapped.txt`, `regions.txt`) |
| Basin outputs | `v01/<basinId>/` (same layout as `examples/MX_22008/`) |
| Logs | `jobSubmission/logs/v01_*.out` in the clone used to submit |

**Step 1: shared preparation (one job, a few hours)**

```bash
cd /project/6079554/share/camels-mx/users/$USER/unified-delineation
git pull
cd jobSubmission
sbatch v01_1_prepare.sh
tail -F logs/v01_prepare_<jobid>.out
```

`v01_1_prepare.sh` converts the station list to `sites/v01_sites.csv`, then runs 01 (TDX index), 00 (validation), 02b (snapping within 500 m, in blocks of 20), 02e, 02f, 03a (controls, `dem_refined`, `dem_max_cells = 400000000`) and the per-region steps 02, 04 (topology index), 04b and 04c. If a `basinId` appears twice in the station list, the **last** row is kept and the duplicates are printed at the top of the log. The job ends with `v01 prepare DONE`.

**Step 2: submit every basin (login node, after step 1 finished)**

```bash
cd /project/6079554/share/camels-mx/users/$USER/unified-delineation/jobSubmission
bash v01_2_submit.sh
```

This submits four job arrays that run `v01_basin_task.sh`, one task per basin:

| Array | Steps | Resources |
|---|---|---|
| `v01_dem_normal` | 02, 03, 04, 05 (DEM refinement) | 8 CPUs, ~30 GB, 3 h |
| `v01_dem_large` (TDX upstream area ≥ 20,000 km²) | 02, 03, 04, 05 | 32 CPUs, ~120 GB, 12 h |
| `v01_export_normal` | 06 + 07, or 05b + 06b + 07b if another station is inside the basin (nested) | 8 CPUs, 3 h |
| `v01_export_large` | same, for large basins | 32 CPUs, 12 h |

The export arrays start only after **all** DEM tasks have ended, because a nested basin needs the step-05 results of the stations upstream of it.

**Notes**

- Run the v01 batch from one clone only, and do not run the single-basin job in that same clone at the same time: both write the shared station indexes in the clone's `indexes/` folder, which the nested exports read.
- Stations with no TDX reach within 500 m are listed in `v01/lists/not_snapped.txt` and are not delineated.
- Every job builds its Python environment on the node's local disk (`$SLURM_TMPDIR`, ~10 s) from `envs/requirements_unified_delineation.txt` and `envs/wheels/`, so Python imports do not load `/project`.
- If a job fails within seconds with `Transport endpoint is not connected` for `/cvmfs`, the compute node lost its software mount. Resubmit (optionally with `--exclude=<node>`, node from `sacct -j <jobid> -X --format=NodeList`) and report the node to Alliance support.
- If `virtualenv` fails with `no .dist-info ... ~/.local/share/virtualenv`, an old cache in your home folder is broken: `rm -rf ~/.local/share/virtualenv` (the current scripts no longer use that cache).

## Running a TDX-Hydro batch: overview

The **[TDX-Hydro delineation manual](docs/Manual_TDX_Delineation.md)** contains the complete commands, retry/reconciliation code, validation checks, and Slurm guidance. In brief:

1. Validate the station catalogue and index the TDX source data.
2. Snap stations to candidate river reaches at 500 m; optionally retry only failed sites at 2,000 m, preserving the first pass and the selected search radius.
3. Consolidate matches, build the shared-reach registry, and generate per-basin TOML controls.
4. Prepare the batch manifests using `09_tdx_batch.py prepare` **before** `submit`.
5. Dry-run the submission, then launch regional, ID audit, basin, export, and collection tasks with Slurm.
6. Review collected QA results; create the combined ArcGIS review GeoPackage as a separate final step.

For example, after controls are prepared:

```bash
python 1_delineation/common/09_tdx_batch.py prepare \
  --label my_tdx_run \
  --controls-dir 0_control_files/my_tdx_controls

python 1_delineation/common/09_tdx_batch.py submit \
  --label my_tdx_run \
  --region-parallel 2 \
  --basin-parallel 8 \
  --export-parallel 6 \
  --dry-run

# If the dry-run is correct, repeat without --dry-run.
# After batch processing:
python 1_delineation/common/09_tdx_batch.py collect --label my_tdx_run
```

The current 500 m snapping Slurm wrapper and ArcGIS Slurm wrapper may contain dataset- or ARC-specific paths. Check and adapt their catalogue, project root, environment, and batch label before independent use.

## Outputs: what is saved, and where?

All paths below are **relative to the project root** unless otherwise noted. Replace `<site_id>` with the gauge ID and `<label>` with the batch name supplied to `09_tdx_batch.py`. Output folders are created by the relevant stages; a failed or skipped stage may not produce all listed files.

### A. Dataset-wide preparation outputs

| Output | Path | Contents |
|---|---|---|
| Validated stations | `indexes/gauge_catalogs/<dataset>_gauge_catalog_validated.csv` *(name depends on catalogue)* | Validated gauge IDs and coordinates. |
| TDX regional index | `indexes/tdx_regions.csv` | Regional TDX source inventory. |
| TDX health report | `indexes/tdx_local_health.csv` | Metadata issues and source availability. |
| Initial snap batches | `indexes/gauge_catalogs/tdx_snapping/batch_500m/` | Per-batch `tdx_gauge_snaps_*.csv`, candidate CSVs, and JSON summaries. |
| Consolidated 500 m matches | `indexes/gauge_catalogs/tdx_snapping/consolidated_500m/tdx_gauge_snaps_all.csv` | One row per gauge, with matching status. |
| Optional 2,000 m retry | `indexes/gauge_catalogs/tdx_snapping/retry_2000m/` | Separate retry outputs for initially failed gauges. |
| Reconciled snaps | `indexes/gauge_catalogs/tdx_snapping/reconciled_500m_2000m/tdx_gauge_snaps_all.csv` | Selected matches, original status, retry flag and selected radius. |
| Shared-reach registry | `indexes/gauge_catalogs/tdx_shared_network/` | Candidate parent-reach groups, split plans, and nested topology information. |
| Basin-specific controls | `0_control_files/<dataset_controls>/control_<site_id>.toml` | Per-gauge configuration. |
| Control manifest | `0_control_files/<dataset_controls>/batch_controls_manifest.csv` | Source readiness and processing flags; includes gauges not ready for automated processing. |

The demonstrated directory names reflect the CAMELS-SPAT workflow; other datasets should use separate catalogue, snap, registry, and controls directories to prevent accidental mixing.

### B. Individual basin GIS and diagnostic outputs

**Main root:** `outputs/<site_id>/`

```text
outputs/<site_id>/
├── tdx_upstream_native.gpkg                 # Upstream TDX subbasins and reaches (Step 04)
├── tdx_upstream_refined.gpkg                # Step 05 refinement geometry, when available
├── tdx_nested_partition_preview.gpkg       # Nested/shared-gauge candidate geometry, if applicable
├── diagnostics/                             # Outlet selection, topology and process QA
├── cwarhm_exports/
│   ├── tdx_native/                          # Native TDX HRU variant, when exported
│   │   ├── shapefiles/
│   │   │   ├── catchment/<site_id>_catchment.shp
│   │   │   ├── river_basins/<site_id>_river_basins.shp
│   │   │   └── river_network/<site_id>_river_network.shp
│   │   └── metadata/                        # Export provenance and diagnostics
│   ├── tdx_clipped/                         # Clipped/refined preview, when exported
│   │   └── shapefiles/...
│   └── tdx_nested_preview/                  # Nested catchment preview, if applicable
│       └── shapefiles/...
└── validation/                              # Step 07 / Step 07b structural checks
```

**Meaning of the three GIS shapefile groups:**

| Folder | Feature | Typical use |
|---|---|---|
| `shapefiles/catchment/` | Individual HRU/subbasin polygons with reach/HRU attributes | Distributed catchment discretization for modelling. |
| `shapefiles/river_basins/` | One merged watershed-boundary polygon | View/check the entire delineated basin boundary. |
| `shapefiles/river_network/` | River-reach polylines and connectivity attributes | River-network and routing preparation. |

Shapefiles are multi-file datasets (`.shp`, `.shx`, `.dbf`, `.prj`, etc.); retain all components when copying GIS outputs. Export variants are method- and validation-dependent: **do not assume every basin has all three variants**. Under the `full` method, refined/intermediate geometry may still be produced for diagnostics, but the native-TDX-HRU configuration is the reference interpretation.

Individual basin validation and diagnostics typically include files under `outputs/<site_id>/validation/` and `outputs/<site_id>/diagnostics/`. Review these before accepting a shapefile as a hydrologically valid product.

### C. Slurm batch results and QA

**Main root:** `batch_tdx/<label>/`

| File or directory | Purpose |
|---|---|
| `sites.csv` | Selected source-ready basin tasks (not necessarily every catalogue gauge). |
| `regions.csv` | Regional task assignments. |
| `run_config.json` | Batch configuration and source-ready counts. |
| `slurm_logs/` | Per-phase Slurm standard output and error logs. |
| `status/` | Per-site and regional processing status JSONs. |
| `id_audit/` | Global identifier audit and conflict diagnostics. |
| `tdx_batch_results.csv` | Processing outcomes for selected basin tasks. |
| `tdx_batch_all_gauges_status.csv` | Status records for the complete input catalogue, including stations not selected for delineation. |
| `tdx_batch_results_summary.json` | Cross-site progress and status totals. |

Slurm uses dependencies between regional preparation, the ID audit, basin processing, export and final collection. Some dependencies are `afterany`, so later jobs may start even when upstream tasks failed. Inspect the collected status reports rather than relying only on a `COMPLETED` job state.

### D. Final combined ArcGIS review dataset

**Main root:** `batch_tdx/<label>/arcgis_review/`

The final review is generated by:

```text
1_delineation/tdx/10_build_arcgis_review_layers.py
```

It reads the completed batch status and available per-site GIS outputs. For the currently implemented review script, the files are:

```text
batch_tdx/<label>/arcgis_review/
├── camels_spat_tdx_review.gpkg      # Combined multi-layer GeoPackage
├── all_basins_review_status.csv    # All-station spatial review/status table
├── gis_read_errors.csv            # GIS read/geometry problems, if any
└── review_layers_summary.json     # Layer and feature counts
```

The name `camels_spat_tdx_review.gpkg` is **currently hard-coded and CAMELS-SPAT-specific**; change/parameterize it before calling the reviewer dataset-independent. The intended GeoPackage layers are:

| Layer | Contents |
|---|---|
| **`basin_boundaries`** | Available delineated boundaries, with site/status/source information. |
| **`river_network`** | Available river reaches, with identifiers and review metadata. |
| **`original_gauges`** | Original station point for **every input gauge**, including failed/unmatched gauges. |
| **`selected_outlets`** | Candidate snapped outlet points wherever a match was available. |

The review script preferentially uses available CWARHM-exported geometries, with Step 04/05 GIS data as labelled fallbacks when later exports are missing. It **does not manufacture a missing basin polygon or outlet**. Fields identify review status, selected source, snapping distance, and problems, so failed and incomplete basins can be inspected alongside successful ones in ArcGIS Pro or QGIS.

After `collect`, check the review script and Slurm wrapper for the correct project path and label:

```bash
python 1_delineation/tdx/10_build_arcgis_review_layers.py --help
sed -n '1,120p' 1_delineation/tdx/run_10_arcgis_review.sbatch
```

If the installed script supports the documented options, the direct command is:

```bash
python 1_delineation/tdx/10_build_arcgis_review_layers.py \
  --root "$PWD" \
  --label my_tdx_run \
  --catalog path/to/my_validated_catalog.csv \
  --output-dir batch_tdx/my_tdx_run/arcgis_review
```

For a large batch, use `1_delineation/tdx/run_10_arcgis_review.sbatch` **only after checking its currently hard-coded paths** (the earlier wrapper referenced the old `common/` script location).

## Validation and interpretation

- **`REVIEW`**: A candidate gauge/reach or output requires checking; it is **not** approval.
- **`FAILED`**: A stage did not produce a usable result. The original station can still appear in the final ArcGIS review layer.
- **Structural pass**: Geometry/topology checks passed the coded criteria, but manual hydrological review may still be required.
- **Production export authorization**: Kept separate from preview success; the current batch workflow marks outputs as **not production-approved**.

Recommended GIS checks include gauge-to-outlet location, delineated drainage area versus reference area, river connectivity, nested HRU partition consistency, missing/invalid geometries, and exceptionally large snapping distances.

## Reproducibility and contributions

The code is intended to support additional delineation methods under `1_delineation/merit/`, `1_delineation/dem/`, or later method directories, while sharing common catalogue, orchestration, QA, and export conventions. Current TDX scripts and HPC wrappers contain some ARC/CAMELS-SPAT assumptions and must be parameterized for general-purpose distribution. Do not represent them as fully portable until those assumptions have been removed and tested.

Generated datasets are intentionally excluded from Git. Keep raw TDX source files, station observations, geospatial outputs, and Slurm logs outside version control. Include example inputs and licensing information before a public release; do not redistribute TDX data unless its terms permit it.

For detailed, reproducible commands, use **[`docs/Manual_TDX_Delineation.md`](docs/Manual_TDX_Delineation.md)**.
