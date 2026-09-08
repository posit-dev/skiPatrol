# skiPatrol examples — Quarto

Quarto (`.qmd`) versions of the skiPatrol examples. Each document **runs unmodified in three
environments** — a local R session, the Posit Native App, and a Snowflake Workspace
Notebook — relying on `sfr_connect()`'s auto-detection rather than environment-specific
setup. Configure through `_config.R`, or not at all.

## Why these exist alongside `../notebooks/`

The `.ipynb` examples in `../notebooks/` were written for Snowflake Workspace Notebooks,
which run a **Python kernel with an `%%R` cell magic** supplied by the
`snowflake-notebook-multilang` bootstrap (`sfnb_setup.py`). That works well there and is
still the right thing to use in Workspace.

It does not travel. A Quarto `{r}` chunk is just R, so these documents need no magic, no
`sfnb_setup.py`, and no Python kernel — which means they run in Posit's tooling, where the
`.ipynb` versions do not. The `.qmd` route was validated end to end in the real Posit Native
App on 7 September 2026.

The two sets are **additive**: `.ipynb` for Workspace, `.qmd` everywhere. Nothing was
removed.

## The documents

| Document | Covers |
|---|---|
| `quickstart.qmd` | Connect, query, read/write tables, aggregate, bridge to DBI/`dbplyr` |

Further topics — feature store, model registry, model monitoring, forecasting, marketing,
`doSnowflake` parallelism, and the parallel SPCS lab — are being converted from
`../notebooks/`. Each merges the previously separate `local_*` and `workspace_*` pair into
one environment-agnostic document, the same way the credit-risk demo did.

## Running one

Open it in Positron or RStudio and render, or:

```bash
quarto render quickstart.qmd
```

You need a working Snowflake connection. Locally that means a profile in
`~/.snowflake/connections.toml`; in the Native App or a Workspace Notebook it is already
there and `sfr_connect()` will find it.

Set only what your environment actually needs:

```bash
export SFR_DATABASE=MY_DATABASE     # default: SKIPATROL_EXAMPLES
export SFR_SCHEMA=PUBLIC
export SFR_WAREHOUSE=MY_WAREHOUSE   # default: the profile's own
export SFR_CONNECTION_NAME=myprofile   # only if you have several local profiles
```

These documents create a small number of demo tables in `SFR_DATABASE`.`SFR_SCHEMA`. Each
has a commented-out cleanup chunk at the end — commented deliberately, so re-running a
document does not delete anything unexpectedly.
