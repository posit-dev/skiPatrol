# skiPatrol (development version)

## Package rename

- **This package was `snowflakeR`; it is now `skiPatrol`.** Snowflake's legal
  position required "snow" out of the *package name*; references to Snowflake
  in code and documentation are unaffected. Replace `library(snowflakeR)`
  with `library(skiPatrol)`.

- **The `sfr_*` function prefix and `doSnowflake` are unchanged**, as are
  `Snowflake()` and the DBI class names in the companion `skiLift` package
  (formerly `RSnowflake`), which `skiPatrol` uses for DBI connectivity.

## New features

- **Model monitoring now supports classification models.**
  `sfr_monitor_source()` gains `prediction_class_columns` and
  `actual_class_columns`. Previously it exposed only the regression-shaped
  `prediction_score_columns`/`actual_score_columns`, so `sfr_add_monitor()`
  failed outright for a classification model ("Actual score column(s) were
  specified, but model was of task: 'tabular_binary_classification'") and
  there was no way to monitor one at all. `COUNT`,
  `CLASSIFICATION_ACCURACY`, `F1_SCORE`, `PRECISION` and `RECALL` all compute
  once a monitor is attached.

  Two related constraints to be aware of: the model must have been logged
  with `task=` set, and drift metrics require a baseline that
  `sfr_monitor_source()` does not yet expose. `sfr_show_model_monitors()`
  returns an unparsed single-column representation -- use
  `sfr_get_monitor()` instead.

## Bug fixes

- **`sfr_connect()` no longer misidentifies a local session as a Workspace
  Notebook.** Detection asked whether a Snowpark session existed, but that
  returns *any* session live in the process -- including one an earlier
  `sfr_connect()` call had just created. A second connection in the same R
  session therefore reported "Connected via active Workspace Notebook
  session" on a laptop, skipped `connections.toml` entirely, and returned an
  empty `account` and `user`, which surfaced later as a misleading "Key-pair
  auth requires private_key_path" error from `sfr_dbi_connection()`.
  Detection now reads the environment directly. This only reproduced where
  several files share one R session -- Positron, Posit Workbench, and the
  Native App IDE; Jupyter gives each notebook its own kernel, which
  concealed it.

- **`sfr_deploy_model()` works from outside Workspace Notebooks.** Conda
  package versions were pinned to whatever R was running locally, which is
  only safe where R itself came from conda; elsewhere it produced an
  unsatisfiable environment (`r-base==4.6.0` against an `r-ranger` needing
  `<4.6.0a0`). `r-base` is now pinned exactly only when the running R is
  itself a conda build, and the solver is left to satisfy the bounds
  otherwise. User-supplied `r-base` pins are still never overridden.

- **Connections now succeed from Posit Workbench and the Posit Team Native
  App.** Three separate faults, each of which blocked the first connection:
  the OAuth token in a `connections.toml` profile was not read (the profile
  name is now handed to the Python connector, so the token never crosses
  into R); `reticulate` had no declared Python requirements and auto-selected
  Python 3.12 with no Snowflake SDK present, which would have hit every
  user's first session; and a session carrying no warehouse, database or
  schema crashed connection construction with "missing value where TRUE/FALSE
  needed", because the cleanup guards handled `NULL`, `""` and `"None"` but
  not a bare `NA`.

- **A new argument, `sfr_connect(session = )`,** supplies an existing Snowpark
  session deliberately. Previously the only way to do this was to rely on
  auto-detection finding any live session in the process -- the defect above.

- **Python bridge caches are scoped to the session rather than the process.**
  `_EXP_INSTANCE` was a single global that silently ignored its session
  argument after the first call; the feature-store and dataset caches were
  keyed on fields likely to be identical across a reconnect to the same
  project. All three now include the session in the cache key, so a second
  connection no longer inherits the first one's objects.

- A LaTeX build log containing local filesystem paths was being tracked and
  shipped; it has been removed and `*.log` is now excluded from the build.

## Documentation and packaging

- **The guide is now *The Piste Guide to R and Snowflake -- Working with
  skiLift and skiPatrol*.** A first published set of chapters covers platform
  basics, working from your own IDE, and core use of both packages; the
  remaining chapters are being restructured and will follow shortly.

- Added a Quarto example set, starting with a quickstart document.

- `connections.toml` and `.env` are now excluded from the source tarball, so
  credentials cannot be packaged by accident.

- The guide and `.pytest_cache/` are excluded from the source tarball, and a
  duplicate notebook and a development test harness are no longer installed
  as example content. Together with smaller logo assets this reduces the
  built package substantially.

- Added a top-level `NOTICE` recording Snowflake Labs as the origin of the
  work, Posit Software, PBC as copyright holder and funder, and Hex Field Ltd
  as maintainer, per Apache-2.0 section 4(b).

# skiPatrol 0.2.0

## New modules

### Model Monitoring

Full model-monitoring lifecycle for deployed models:

- `sfr_monitor_source()` / `sfr_monitor_config()` -- configure
  monitoring sources and settings
- `sfr_add_monitor()` / `sfr_get_monitor()` /
  `sfr_show_model_monitors()` / `sfr_delete_monitor()` -- CRUD for
  monitors
- `sfr_monitor_drift()` / `sfr_monitor_performance()` /
  `sfr_monitor_stats()` -- retrieve monitoring results
- `sfr_suspend_monitor()` / `sfr_resume_monitor()` /
  `sfr_describe_monitor()` -- lifecycle management
- `sfr_add_monitor_segment()` / `sfr_drop_monitor_segment()` -- segment
  drill-down
- `sfr_monitor_to_vetiver()` / `sfr_vetiver_to_metrics()` -- vetiver
  integration bridge

### Experiment Tracking

MLflow-style experiment tracking on Snowflake:

- `sfr_experiment()` / `sfr_start_run()` / `sfr_end_run()` /
  `sfr_delete_run()` / `sfr_delete_experiment()` -- experiment lifecycle
- `sfr_exp_log_param()` / `sfr_exp_log_params()` -- parameter logging
- `sfr_exp_log_metric()` / `sfr_exp_log_metrics()` -- metric logging
- `sfr_exp_log_model()` / `sfr_exp_log_artifact()` -- artifact logging
- `sfr_exp_list_artifacts()` / `sfr_exp_download_artifact()` -- artifact
  retrieval
- `sfr_experiment_from_tune()` / `sfr_experiment_log_best()` -- `tune`
  grid-search integration

## New Feature Store functions

- `sfr_attach_feature_desc()` -- attach human-readable descriptions to
  individual features
- `sfr_slice_feature_view()` -- create a column-subset slice of a
  Feature View
- `sfr_fv_lineage()` -- trace upstream/downstream lineage from a Feature
  View
- `sfr_list_fv_columns()` -- list columns and types for a registered
  Feature View
- `sfr_fv_to_df()` -- read a Feature View's data as a data.frame
- `sfr_fv_query()` -- retrieve the underlying SQL query for a Feature
  View
- `sfr_fv_fqn()` -- get the fully qualified name of a Feature View
- `sfr_load_fvs_from_dataset()` -- recover Feature Views associated with
  a Dataset
- `sfr_update_default_warehouse()` -- change the default warehouse for a
  Feature Store
- `sfr_storage_config()` -- create Iceberg-backed storage configurations

## New Model Registry functions

- `sfr_delete_model_version()` -- delete a specific model version
- `sfr_get_model_metric()` -- read a single metric by name
- `sfr_delete_model_metric()` -- delete a single metric
- `sfr_model_description()` -- get or set the version description
- `sfr_show_model_functions()` -- list callable functions on a model
  version
- `sfr_model_lineage()` -- trace upstream/downstream model lineage
- `sfr_export_model()` -- export model artifacts to a local directory
- `sfr_get_model_task()` -- get the task type of a model version
- `sfr_list_services()` -- list active SPCS services for a model version
- `sfr_run_batch()` -- run batch inference via SPCS
- `sfr_models()` -- list Model objects in a registry (vs `sfr_show_models()`
  which returns a summary DataFrame)

## New parameters on existing functions

### Feature Store

- `sfr_feature_store()`: `default_iceberg_external_volume`
- `sfr_feature_view()` / `sfr_create_feature_view()`: `initialize`,
  `refresh_mode`, `cluster_by`, `online_config`
- `sfr_register_feature_view()`: `block`
- `sfr_read_feature_view()`: `store_type`, `keys`, `feature_names`
- `sfr_refresh_feature_view()`: `store_type`
- `sfr_get_refresh_history()`: `store_type`
- `sfr_generate_training_data()`: `exclude_columns`,
  `include_feature_view_timestamp_col`, `auto_prefix`, `join_method`
- `sfr_generate_dataset()`: `exclude_columns`,
  `include_feature_view_timestamp_col`, `auto_prefix`, `join_method`,
  `output_type`
- `sfr_retrieve_features()`: `exclude_columns`,
  `include_feature_view_timestamp_col`, `auto_prefix`, `join_method`

### Model Registry

- `sfr_log_model()`: `user_files`, `code_paths`, `resource_constraint`,
  `python_version`
- `sfr_predict()`: `partition_column`, `strict_input_validation`
- `sfr_deploy_model()`: `image_build_compute_pool`, `cpu_requests`,
  `memory_requests`, `gpu_requests`, `num_workers`, `max_batch_rows`,
  `block`, `build_external_access_integrations`

## Bug fixes

- `sfr_read_feature_view()`: Fixed `reticulate` type conversion for
  `keys` (R character vectors now correctly converted to Python list of
  lists of strings) and `feature_names` parameters.
- `sfr_fv_to_df()`: Worked around a `reticulate` `TypeError` on
  `cluster_by` field type inference by using `fs.read_feature_view()`
  instead of `fv.to_df()`.
- `sfr_slice_feature_view()`: Fixed `AttributeError` when the
  `FeatureViewSlice` object lacks `name`/`version` attributes; now falls
  back to the original request values.
- `sfr_models()`: Fixed `rbind` failure when model `comment` is `NULL`
  by coercing to empty string.
- `sfr_add_monitor_segment()` / `sfr_drop_monitor_segment()`: Added
  missing `segment` parameter in the Python bridge call.

## doSnowflake

- Tasks and queue modes poll `LIST` on the job `results/` prefix before
  downloading chunk `.rds` files (defaults: 45s max wait, 3s poll), reducing
  Snowflake **253006** (“file does not exist”) when stage visibility lags
  Task graph `SUCCEEDED`. Tune with `result_sync_wait_sec` and
  `result_sync_poll_sec` in `registerDoSnowflake(...)`.
- **Tasks mode polling** now waits for **`n_chunks` child tasks** in
  `TASK_HISTORY(ROOT_TASK_NAME => …)` to reach `SUCCEEDED`, not only the root
  row (the root can report `SUCCEEDED` before SPCS workers finish, which led
  to very short runtimes and missing `result_*.rds` on `GET`).
- `GET` to a local directory now uses a **normalized `file:///…/` URI** with a
  trailing slash on the target folder (connector expectations).

## Documentation

- `DESCRIPTION` **Version** set to **0.2.0** (was 0.1.0), matching this
  changelog and the published feature set.
- New vignettes: `parallel-dosnowflake`, `experiments`, `model-monitoring`;
  many-model section in `model-registry`; expanded README module and notebook
  tables; `registerDoSnowflake()` details aligned with implemented modes.
- `vignette("workspace-notebooks")`: extended interactive notebook index;
  new section on parallel / SPCS labs (`workspace_parallel_spcs_*.ipynb`,
  `workspace_dosnowflake.ipynb`, `PARALLEL_SPCS_DEMO.md`).
- Regenerated NAMESPACE and man/ pages for all new exports.
- Extended Feature Store and Model Registry vignettes with new sections
  covering online serving, aggregation, introspection, slicing, Iceberg,
  lineage, aliases, SQL-direct inference, batch inference, advanced
  deployment, and more.
- Updated README.md module overview table and example notebooks table.
- Added this NEWS.md changelog.
